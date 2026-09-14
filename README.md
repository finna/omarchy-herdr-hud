# Herdr HUD for Omarchy

Herdr HUD keeps your [Herdr](https://herdr.dev/) agents inside your game. A small draggable **H** button stays above fullscreen apps; click it or use a keybind to open a larger terminal and prompt panel without minimizing the game.

![Herdr HUD opening and closing over a fullscreen terminal](assets/demo.gif)

![Herdr HUD open over a fullscreen app](assets/herdr-hud.png)

## Features

- See every connected agent, its agent type, workspace title, pane, and live status.
- Distinguish agents sharing a workspace by their tab names, such as “local” and “mac studio”.
- Agents needing attention appear first, followed by working agents and already-read idle agents. Reading a reply moves it down; agents blocked on input remain at the top.
- Read live terminal output that follows the newest response automatically.
- Use Codex Chat view for shaded prompts, separate replies, bold list labels, and expandable tool activity. Chat fills the panel from the top; unrecognized output remains visible as plain text.
- See Codex model and reasoning metadata by hovering the selected agent card, with its trailing terminal composer and model footer removed from the viewer.
- See a persistent animated working indicator, including when no new terminal output is arriving. Its elapsed timer shows how long HUD has observed the agent working.
- Prompt ready agents without switching windows.
- Green attention badge for blocked agents and unseen status changes.
- Silent alerts beside H when an agent finishes or needs input while the panel is closed. Click to open that agent, hover to keep the alert visible, or dismiss it with ×. Alerts disappear after eight seconds; the unread badge remains. Codex alerts include a short reply preview when available.
- Drag the H button anywhere; its position is saved separately for each monitor.
- Drag the roster divider to give the terminal more room.
- Appears over fullscreen apps and games on Omarchy's Hyprland desktop.

## Requirements

- Omarchy Quattro with `omarchy-shell`
- [Herdr](https://herdr.dev/) 0.9.0 or later installed and running, available as `herdr`
- Python 3 (included with Omarchy)

The panel shows a setup message when Herdr is missing or unavailable.

Chat view formats recognized Codex terminal patterns, rather than reading a structured message history. It shows the recent captured output, preserves unrecognized context, and displays plain captured output when formatted blocks are unavailable.

By default, Herdr HUD reads through the local `herdr` and `hyprctl` commands and sends prompts through Herdr’s local socket API. It does not add a service, request elevated privileges, or send data to a separate server.

## Install

```bash
omarchy plugin add https://github.com/finna/omarchy-herdr-hud.git --enable
```

The H button appears immediately. Click it to open the panel.

To add a keyboard shortcut, put this in `~/.config/hypr/bindings.lua` using any free chord:

```lua
o.bind("SUPER + H", "Toggle Herdr panel", "omarchy-shell shell toggle finna.herdr-hud '{}'")
o.bind("SUPER + SHIFT + H", "Show or hide Herdr HUD", "omarchy-shell shell call finna.herdr-hud toggleVisibility '{}'")
```

Then reload Hyprland with `hyprctl reload`. Omarchy keeps keybind choice in user config so this plugin does not overwrite an existing shortcut.

## Use

- **Click H:** open or close the panel on that monitor. The button stays visible above the panel.
- **Super+H** (after binding): toggle the panel; the H launcher remains available.
- **Super+Shift+H** (after binding): hide everything, including the H circle; press again to show the circle. Super+H also brings back a hidden overlay and opens its panel.
- **Drag H:** reposition the button and its attached panel. The panel flips sides near screen edges and stays within the screen.
- **Click an agent:** select its terminal and clear its unread indicator.
- **Ctrl+Enter:** send the current prompt.
- **Esc:** close the panel.
- **Drag the vertical divider:** resize the agent roster.

State is stored in `~/.config/herdr-hud/state.json`.
The overlay remembers whether it is hidden across shell restarts. Roster polling pauses while hidden.

The terminal shows the most recent 180 lines and refreshes while the panel is open. It is a text viewer with a prompt composer, rather than an interactive terminal emulator. Blocked agents show an attention badge; approvals must be answered in Herdr before more prompts can be sent. Unread indicators track agent status changes, not individual chat messages.

Tested on Omarchy Quattro 4.0.2 with a fullscreen terminal. Individual games and multiple-monitor setups have not yet been verified. Windows, macOS, and other Wayland compositors are not supported.

## Update and remove

```bash
omarchy plugin update finna.herdr-hud
omarchy plugin remove finna.herdr-hud
```

Removal unloads the plugin and deletes its checkout. To also remove saved UI preferences:

```bash
rm -rf ~/.config/herdr-hud
```

Remove your Herdr HUD keybind from `~/.config/hypr/bindings.lua` as well, if you added one.

## Prompt privacy and process limits

Prompt text travels from QML to the bridge as a JSON string on stdin, then directly
to Herdr's local `agent.prompt` socket method. It never appears in command-line
arguments. The bridge asks `herdr status server` for the socket of the selected
session, rechecks the selected terminal and readiness, and validates the prompt
acknowledgement. A failed or ambiguous submission is never automatically retried;
check Herdr before manually sending again. Herdr's API does not provide an atomic
expected-terminal guard, so the preflight check cannot eliminate every concurrent
pane-replacement race.

Every child command has a 12-second deadline (3 seconds for monitor queries),
1 MiB stdout and 64 KiB stderr limits enforced while streaming. On overflow or
timeout, the bridge kills the owned process group and reaps its children,
including orphaned descendants in that group. It does not buffer an unlimited
response and truncate afterward. Prompts are limited to 64 KiB UTF-8; serialized
HUD responses to 8 MiB; displayed errors to 4096 characters. Oversized responses
produce an error instead of reaching the shell collector.

## Custom backends

Optional `~/.config/herdr-hud/backend.json` can provide command arrays:

```json
{
  "command": ["/path/to/read-adapter"],
  "prompt_command": ["/path/to/stdin-prompt-adapter"]
}
```

The read adapter receives Herdr CLI arguments and must preserve the CLI JSON
shapes, uniquely scoping agent and terminal IDs when combining machines.
The prompt adapter receives **only pane ID and expected terminal ID** as two
appended arguments and the **raw UTF-8 message on stdin**, closed after writing.
It must validate the current target/readiness, retain stdin or socket transport
through any remote hops, and return `{"ok":true}` only after acknowledging delivery.
Never copy prompt text into an SSH command string or another process's arguments.

An older adapter with only `command` remains usable for reading but cannot send
prompts until `prompt_command` is configured. This is deliberate: the bridge never
falls back to exposing text in argv, nor routes an adapter target to the local
server. Omit the file for normal local Herdr. Machine addresses and credentials
belong in local configuration, not this repository.

## Development

```bash
omarchy plugin validate .
python -m unittest discover -s tests -v
node --test tests/*.mjs
```

The QML UI uses Omarchy's plugin lifecycle and Quickshell layer surfaces. `bin/herdr-hud` is a standard-library-only bridge that invokes Herdr with argument arrays, rechecks the selected agent before prompting, and never evaluates prompt text in a shell. The tests use controlled processes and a fake socket server; no test prompts are sent to user agents. When Quickshell is available, an offscreen test runs the actual QML submit function and stdin wiring through a fake backend.

For a screenshot with fictional agents and prompt sending disabled:

```bash
omarchy-shell shell summon finna.herdr-hud '{"demo":true}'
```

Closing the preview restores the real roster. Review the surrounding desktop before sharing captures.

Herdr HUD is a community project and is not affiliated with Herdr or Basecamp.
