"""Run the actual QML submit function and Process wiring with a fake backend."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from test_bridge import BRIDGE_PATH


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required for the QML integration check')
class QMLPromptTests(unittest.TestCase):
    def test_qml_bridge_adapter_stdin_roundtrip(self):
        source = (BRIDGE_PATH.parents[1]/'HerdrHud.qml').read_text()
        submit = source[source.index('  function submitPrompt(message)'):source.index('  Component.onCompleted:')]
        process = source[source.index('  Process {\n    id: promptProc'):]
        process = process[:process.index('    onExited:')]
        message = '-private 🐑\n$(whoami) `false` "quote"'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adapter = root/'adapter.py'
            adapter.write_text('''import json,sys,os
from pathlib import Path
if sys.argv[1:] == ['agent','list']:
 print(json.dumps({'result':{'agents':[{'pane_id':'w1:p1','terminal_id':'terminal','agent_status':'idle'}]}}))
else:
 message=sys.stdin.read()
 assert sys.argv[1:]==['w1:p1','terminal']
 assert message==json.loads((Path(__file__).parent/'expected.json').read_text())
 for pid in [os.getpid(),os.getppid()]:
  assert message.encode() not in Path('/proc',str(pid),'cmdline').read_bytes()
 (Path(__file__).parent/'passed').write_text('stdin arrived; bridge and adapter argv contain no prompt')
 print(json.dumps({'ok':True}))
''')
            (root/'expected.json').write_text(json.dumps(message))
            config = root/'.config/herdr-hud/backend.json';config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'command':['python3',str(adapter)],'prompt_command':['python3',str(adapter)]}))
            qml = '''import QtQuick
import Quickshell
import Quickshell.Io
Scope {
 id: root
 property bool demoMode: false
 property bool sending: false
 property string selectedPane: "w1:p1"
 property string promptPane: ""
 property string promptMessage: ""
 property string noticeText: ""
 property string bridgePath: BRIDGE
 function agentForPane(pane) { return {terminal_id:"terminal"} }
 function isReady(agent) { return true }
 SUBMIT
 Component.onCompleted: submitPrompt(MESSAGE)
 PROCESS
 onExited: function(code) { console.log("HUD_TEST_EXIT",code,promptErr.text); Qt.quit() }
 }
 Timer { interval: 5000; running:true; onTriggered: Qt.quit() }
}
'''.replace('BRIDGE',json.dumps(str(BRIDGE_PATH))).replace('SUBMIT',submit).replace('MESSAGE',json.dumps(message)).replace('PROCESS',process)
            (root/'shell.qml').write_text(qml)
            result = subprocess.run(['quickshell','--no-color','-p',str(root/'shell.qml')],env={**os.environ,'HOME':directory,'QT_QPA_PLATFORM':'offscreen'},capture_output=True,text=True,timeout=8)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertTrue((root/'passed').exists(),result.stdout+result.stderr)
            self.assertIn('HUD_TEST_EXIT 0',result.stdout+result.stderr)
