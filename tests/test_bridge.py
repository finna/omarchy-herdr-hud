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

    def test_missing_command_and_timeout_have_actionable_errors(self):
        cases = [
            (FileNotFoundError(), "is not installed"),
            (subprocess.TimeoutExpired(["herdr"], 12), "did not respond in time"),
        ]
        for error, message in cases:
            with self.subTest(message=message), patch.object(bridge.subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(bridge.BridgeError, message):
                    bridge.run(["herdr"])

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
            [dict(self.agent, agent_status="blocked")],
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

    def test_codex_footer_becomes_metadata(self):
        transcript = "• Here is the answer.\n\n─ Worked for 3m 26s ─────"
        captured = transcript + "\n\n› Ask Codex to do anything\n\n  gpt-6-astra high · ~\n"
        self.assertEqual(bridge.terminal_view(captured, "codex"), {
            "text": transcript, "model": "gpt-6-astra", "reasoning": "high",
        })

    def test_codex_wrapped_composer_and_changed_model(self):
        captured = "• Result\n\n› Summarize the changes in\n  this repository\n\n  gpt-5.6-sol medium · ~/work"
        self.assertEqual(bridge.terminal_view(captured, "codex"), {
            "text": "• Result", "model": "gpt-5.6-sol", "reasoning": "medium",
        })

    def test_preserves_model_mentions_and_other_agent_output(self):
        examples = [
            "The placeholder is Ask Codex to do anything.\n  gpt-6-astra high · ~",
            "› A previous prompt\n\n• This is the actual answer.\n  gpt-6-astra high · ~",
            "A code example:\n```\n› Ask Codex to do anything\n```\n  gpt-6-astra high · ~",
            "› Ask Codex to do anything\n\n  Unrecognized status footer",
        ]
        for captured in examples:
            with self.subTest(captured=captured):
                self.assertEqual(bridge.terminal_view(captured, "codex")["text"], captured)
        captured = "An answer\n› Ask Codex to do anything\n\n  gpt-6-astra high · ~"
        self.assertEqual(bridge.terminal_view(captured, "hermes")["text"], captured)

    def test_output_returns_transcript_and_metadata(self):
        with patch.object(bridge, "herdr", return_value="• Answer\n\n› Ask Codex to do anything\n\n  gpt-6-astra high · ~"), patch.object(bridge, "response") as response:
            bridge.output("w4:p1", "codex")
        self.assertEqual(response.call_args.args[0]["text"], "• Answer")
        self.assertEqual(response.call_args.args[0]["model"], "gpt-6-astra")

    def test_working_timer_does_not_change_transcript(self):
        for elapsed in ("3s", "2m 50s", "1h 20m"):
            captured = "• Still checking the files.\n\n• Working (" + elapsed + " • esc to interrupt) · 1 background terminal\n  running · /ps to view · /stop to close\n\n› Ask Codex to do anything\n\n  gpt-6-astra high · ~"
            with self.subTest(elapsed=elapsed):
                self.assertEqual(bridge.terminal_view(captured, "codex")["text"], "• Still checking the files.")

    def test_preserves_completed_turn_and_activity_quotes(self):
        for body in (
            "• Answer\n\n─ Worked for 3m 26s ─────",
            "• Working (3s • esc to interrupt)\n\n• This line explains the example above.",
        ):
            captured = body + "\n\n› Ask Codex to do anything\n\n  gpt-6-astra high · ~"
            self.assertEqual(bridge.terminal_view(captured, "codex")["text"], body)

    def test_conversation_separates_prompts_replies_and_tools(self):
        text = "Earlier fragment\n\n› Fix this\n  please\n\n• Ran pytest\n  └ 12 passed\n\n• Fixed it.\n\n  - Tests: all passed\n\n─ Worked for 20s ───"
        blocks = bridge.conversation_blocks(text, "codex")
        self.assertEqual([b["kind"] for b in blocks],
                         ["context", "prompt", "tool", "reply", "status"])
        self.assertIn("please", blocks[1]["html"])
        self.assertIn("12 passed", blocks[2]["html"])
        self.assertIn("<b>Tests:</b>", blocks[3]["html"])
        self.assertEqual(bridge.conversation_blocks(text, "hermes"), [])

    def test_conversation_preserves_code_and_escapes_markup(self):
        text = '• Example\n  ```text\n› literal prompt\n• Ran literal command\n  ```\n  <img src="https://example.com/private">\n\n• Added a helpful feature.'
        blocks = bridge.conversation_blocks(text, "codex")
        self.assertEqual([b["kind"] for b in blocks], ["reply", "reply"])
        self.assertIn("literal prompt", blocks[0]["html"])
        self.assertNotIn("<img", blocks[0]["html"])
        self.assertIn("&lt;img", blocks[0]["html"])

    def test_tool_identity_survives_streaming_and_scrollback(self):
        before = bridge.conversation_blocks("• Ran pytest\n  └ running", "codex")
        after = bridge.conversation_blocks("› Test it\n\n• Ran pytest\n  └ done", "codex")
        self.assertEqual(before[0]["id"], after[1]["id"])

    def test_recap_and_repeated_tools_keep_their_content_and_identity(self):
        blocks = bridge.conversation_blocks(
            "• Ran tests\n  first result\n• Ran tests\n  second result\n"
            "─ Conversation recap ─────\n\n  Keep this important summary.", "codex")
        self.assertNotEqual(blocks[0]["id"], blocks[1]["id"])
        self.assertIn("Keep this important summary.", blocks[2]["html"])


if __name__ == "__main__":
    unittest.main()
