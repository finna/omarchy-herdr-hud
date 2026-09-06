import importlib.util
from importlib.machinery import SourceFileLoader
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


BRIDGE_PATH = Path(__file__).parents[1] / "bin" / "herdr-hud"
SPEC = importlib.util.spec_from_loader(
    "herdr_hud_bridge", SourceFileLoader("herdr_hud_bridge", str(BRIDGE_PATH))
)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.agent = {
            "pane_id": "w2:p1",
            "terminal_id": "original",
            "agent_status": "idle",
        }

    def test_run_passes_literal_arguments_without_a_shell(self):
        unsafe = "$(touch /tmp/herdr-hud-must-not-exist); `false`"
        completed = subprocess.CompletedProcess([], 0, stdout="ok", stderr="")
        with patch.object(bridge.subprocess, "run", return_value=completed) as run:
            bridge.run(["herdr", "agent", "prompt", "w2:p1", unsafe])
        self.assertEqual(run.call_args.args[0][-1], unsafe)
        self.assertFalse(run.call_args.kwargs.get("shell", False))

    def test_prompt_rechecks_agent_identity_and_readiness(self):
        with patch.object(bridge, "agents", return_value=[self.agent]), patch.object(
            bridge, "herdr", return_value=""
        ) as herdr:
            bridge.prompt("w2:p1", "original", "hello")
        herdr.assert_called_once_with("agent", "prompt", "w2:p1", "hello")

        invalid_rows = [
            [],
            [dict(self.agent, terminal_id="replacement")],
            [dict(self.agent, agent_status="working")],
        ]
        for rows in invalid_rows:
            with self.subTest(rows=rows), patch.object(bridge, "agents", return_value=rows), patch.object(
                bridge, "herdr"
            ) as herdr:
                with self.assertRaises(bridge.BridgeError):
                    bridge.prompt("w2:p1", "original", "hello")
                herdr.assert_not_called()

    def test_roster_adds_workspace_titles(self):
        agents_json = json.dumps({
            "result": {"agents": [{"pane_id": "w3:p1", "workspace_id": "w3"}]}
        })
        workspaces_json = json.dumps({
            "result": {"workspaces": [{"workspace_id": "w3", "label": "My build"}]}
        })
        with patch.object(bridge, "herdr", side_effect=[agents_json, workspaces_json]), patch.object(
            bridge, "response"
        ) as response:
            bridge.roster()
        self.assertEqual(response.call_args.args[0]["agents"][0]["workspace_label"], "My build")


if __name__ == "__main__":
    unittest.main()
