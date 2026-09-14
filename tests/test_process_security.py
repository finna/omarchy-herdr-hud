import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from test_bridge import bridge, BRIDGE_PATH


class ProcessSecurityTests(unittest.TestCase):
    def test_stdout_stderr_caps_and_exact_boundary(self):
        for fd, limit in [(1, bridge.STDOUT_LIMIT), (2, bridge.STDERR_LIMIT)]:
            with self.subTest(fd=fd):
                script = f'import os;os.write({fd},b"x"*{limit})'
                result = bridge.run([sys.executable, '-c', script])
                self.assertEqual(len(result), limit if fd == 1 else 0)
                with self.assertRaisesRegex(bridge.BridgeError, 'exceeded'):
                    bridge.run([sys.executable, '-c', script + f';os.write({fd},b"x")'])

    def test_stdin_and_both_output_pipes_do_not_deadlock(self):
        script = 'import os,sys;os.write(2,b"e"*60000);os.write(1,b"o"*60000);data=sys.stdin.buffer.read();os.write(1,data)'
        prompt = b'p' * bridge.PROMPT_LIMIT
        self.assertEqual(bridge.run([sys.executable, '-c', script], input_data=prompt), 'o'*60000 + prompt.decode())

    def test_timeout_and_overflow_reap_descendants_even_after_leader_exits(self):
        for action in ['time.sleep(10)', 'os._exit(0)', 'os.write(1,b"x"*2000000);time.sleep(10)']:
            with self.subTest(action=action), tempfile.TemporaryDirectory() as directory:
                pidfile = Path(directory)/'pids'
                script = f'''import os,time,signal
child=os.fork()
if child == 0:
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 time.sleep(10)
else:
 open({str(pidfile)!r},'w').write(str(os.getpid())+' '+str(child))
 {action}
'''
                start = time.monotonic()
                with self.assertRaises(bridge.BridgeError):
                    bridge.run([sys.executable, '-c', script], timeout=0.3)
                self.assertLess(time.monotonic()-start, 2)
                for pid in pidfile.read_text().split():
                    self.assertFalse(Path('/proc', pid).exists(), f'process {pid} survived cleanup')

    def test_error_and_qml_response_are_bounded(self):
        with self.assertRaises(bridge.BridgeError) as caught:
            bridge.run([sys.executable,'-c','import sys;sys.stderr.write("e"*50000);sys.exit(1)'])
        self.assertLessEqual(len(str(caught.exception)), bridge.ERROR_LIMIT)
        with patch.object(bridge, 'RESPONSE_LIMIT', 20), self.assertRaises(bridge.BridgeError):
            bridge.response({'text':'x'*21})

    def test_custom_prompt_uses_only_stdin_and_acknowledges(self):
        message = '-secret 🐑\n$(whoami) `false` "quoted"'
        # Inspect the real process cmdline as well as sys.argv; no prompt text.
        script = '''import sys,json
text=sys.stdin.read()
assert text.encode() not in open('/proc/self/cmdline','rb').read()
assert len(sys.argv)==3 and sys.argv[1:]==['w2:p1','terminal']
assert text.startswith('-secret') and '\\n' in text
print(json.dumps({'ok':True}))'''
        with patch.object(bridge,'backend_config',return_value={'prompt_command':[sys.executable,'-c',script]}):
            bridge.send_prompt('w2:p1','terminal',message)

    def test_custom_adapter_fails_closed_without_stdin_contract(self):
        with patch.object(bridge,'backend_config',return_value={'command':['adapter']}), patch.object(bridge,'run') as run:
            with self.assertRaisesRegex(bridge.BridgeError,'stdin-capable'):
                bridge.send_prompt('w2:p1','terminal','secret')
            run.assert_not_called()

    def test_prompt_cli_requires_stdin_and_rejects_legacy_argv(self):
        result = subprocess.run([str(BRIDGE_PATH),'prompt','w2:p1','terminal','legacy'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('legacy',result.stderr)

    def test_read_prompt_preserves_unicode_multiline_and_rejects_large_input(self):
        script = f"import runpy; b=runpy.run_path({str(BRIDGE_PATH)!r}); print(b['read_prompt'](),end='')"
        for message in ['-secret 🐑\n$(whoami) "quote"', 'x'*(bridge.PROMPT_LIMIT+1)]:
            result = subprocess.run([sys.executable,'-c',script],input=json.dumps(message)+'\n',capture_output=True,text=True)
            if len(message.encode()) > bridge.PROMPT_LIMIT:
                self.assertNotEqual(result.returncode,0)
            else:
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout,message)

    def test_socket_delivery_and_identity_recheck(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory)/'api.sock')
            server = socket.socket(socket.AF_UNIX);server.bind(path);server.listen()
            received=[]
            def serve():
                for _ in range(2):
                    connection,_=server.accept()
                    with connection:
                        request=json.loads(connection.makefile('rb').readline())
                        received.append(request)
                        agent={'terminal_id':'terminal','agent_status':'idle'}
                        result={'type':'agent_info' if request['method']=='agent.get' else 'agent_prompted','agent':agent}
                        connection.sendall((json.dumps({'id':request['id'],'result':result})+'\n').encode())
            thread=threading.Thread(target=serve,daemon=True);thread.start()
            try:
                with patch.object(bridge,'backend_config',return_value={}), patch.object(bridge,'herdr',return_value='socket: '+path):
                    bridge.send_prompt('w2:p1','terminal','private 🐑\ntext')
                thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertEqual([r['method'] for r in received],['agent.get','agent.prompt'])
                self.assertEqual(received[1]['params'],{'target':'w2:p1','text':'private 🐑\ntext'})
            finally: server.close()
        for agent in [{'terminal_id':'replacement','agent_status':'idle'}, {'terminal_id':'terminal','agent_status':'blocked'}]:
            with patch.object(bridge,'backend_config',return_value={}), patch.object(bridge,'herdr',return_value='socket: /fake'), patch.object(bridge,'socket_request',return_value={'agent':agent}) as request:
                with self.assertRaisesRegex(bridge.BridgeError,'changed'):
                    bridge.send_prompt('w2:p1','terminal','secret')
                self.assertEqual(request.call_count,1)

    def test_failed_or_unknown_delivery_is_never_retried(self):
        agent={'pane_id':'w2:p1','terminal_id':'terminal','agent_status':'idle'}
        with patch.object(bridge,'agents',return_value=[agent]), patch.object(bridge,'send_prompt',side_effect=OSError('lost connection')) as send:
            with self.assertRaisesRegex(bridge.BridgeError,'uncertain'):
                bridge.prompt('w2:p1','terminal','private')
            send.assert_called_once()

    def test_socket_overflow_timeout_disconnect_and_bad_ack_fail_closed(self):
        for mode in ['overflow','timeout','disconnect','wrong-id','rejected','malformed']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                path=str(Path(directory)/'api.sock')
                server=socket.socket(socket.AF_UNIX);server.bind(path);server.listen()
                def serve():
                    connection,_=server.accept()
                    with connection:
                        request=json.loads(connection.makefile('rb').readline())
                        try:
                            if mode=='overflow': connection.sendall(b'x'*(bridge.STDOUT_LIMIT+1))
                            elif mode=='timeout': time.sleep(0.2)
                            elif mode=='wrong-id': connection.sendall(b'{"id":"wrong","result":{}}\n')
                            elif mode=='rejected': connection.sendall((json.dumps({'id':request['id'],'error':{'code':'agent_blocked'}})+'\n').encode())
                            elif mode=='malformed': connection.sendall(b'not json\n')
                        except BrokenPipeError: pass
                thread=threading.Thread(target=serve,daemon=True);thread.start()
                try:
                    with self.assertRaises((bridge.BridgeError,OSError,ValueError)):
                        bridge.socket_request(path,'agent.prompt',{'target':'fake','text':'test'},timeout=0.1)
                    thread.join(1)
                    self.assertFalse(thread.is_alive())
                finally: server.close()
