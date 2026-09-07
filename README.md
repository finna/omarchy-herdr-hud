# Herdr HUD for Omarchy

Herdr HUD keeps your [Herdr](https://herdr.dev/) agents inside your game. A small draggable **H** button stays above fullscreen apps; click it or use a keybind to open a larger terminal and prompt panel without minimizing the game.

![Opening and closing Herdr HUD with Super+H](assets/demo.gif)

![Herdr HUD open over a fullscreen app](assets/herdr-hud.png)

## Features

- See every connected agent, its agent type, workspace title, pane, and live status.
- Read live terminal output that follows the newest response automatically.
- Prompt ready agents without switching windows.
- Green attention badge for blocked agents and unseen status changes.
- Drag the H button anywhere; its position is saved separately for each monitor.
- Drag the roster divider to give the terminal more room.
- Appears over fullscreen apps and games on Omarchy's Hyprland desktop.

## Requirements

- Omarchy Quattro with `omarchy-shell`
- [Herdr](https://herdr.dev/) installed and available as `herdr`
- Python 3 (included with Omarchy)

The panel shows a setup message when Herdr is missing or unavailable.

Herdr HUD talks only to the local `herdr` and `hyprctl` commands. It does not add a service, request elevated privileges, or send data to a separate server.

## Install

```bash
omarchy plugin add https://github.com/finna/omarchy-herdr-hud.git --enable
```

The H button appears immediately. Click it to open the panel.

To add a keyboard shortcut, put this in `~/.config/hypr/bindings.lua` using any free chord:

```lua
o.bind("SUPER + H", "Toggle Herdr HUD", "omarchy-shell shell toggle finna.herdr-hud '{}'")
```

Then reload Hyprland with `hyprctl reload`. Omarchy keeps keybind choice in user config so this plugin does not overwrite an existing shortcut.

## Use

- **Click H:** open the panel on that monitor.
- **Super+H** (after binding): toggle the panel; the H launcher remains available.
- **Drag H:** reposition the button.
- **Click an agent:** select its terminal and clear its unread indicator.
- **Ctrl+Enter:** send the current prompt.
- **Esc:** close the panel.
- **Drag the vertical divider:** resize the agent roster.

State is stored in `~/.config/herdr-hud/state.json`.

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

## Development

```bash
omarchy plugin validate .
python -m unittest discover -s tests -v
```

The QML UI uses Omarchy's plugin lifecycle and Quickshell layer surfaces. `bin/herdr-hud` is a standard-library-only bridge that invokes Herdr with argument arrays, rechecks the selected agent before prompting, and never evaluates prompt text in a shell.

For a screenshot with fictional agents and prompt sending disabled:

```bash
omarchy-shell shell summon finna.herdr-hud '{"demo":true}'
```

Closing the preview restores the real roster. Review the surrounding desktop before sharing captures.

Herdr HUD is a community project and is not affiliated with Herdr or Basecamp.
