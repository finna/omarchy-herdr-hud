# Changelog

## 1.0.13

- Switch chat/terminal document format before replacing its content, avoiding a flash of serialized HTML while loading another agent.

## 1.0.12

- Allow an optional local backend command configuration for private adapters, including remote hosts.
- Keep the default local Herdr connection and pass all adapter arguments literally without a shell.
- Reject invalid adapter configuration before sending input.

## 1.0.11

- Show each agent's tab name beside its provider in the roster and in the selected conversation heading.
- Keep pane IDs available in the card tooltip; label numeric tabs as “Tab 1”, etc.

## 1.0.10

- Show silent completion and input-request alerts beside H while the panel is closed.
- Include the workspace name and a short Codex reply preview, with click-to-open and dismiss controls.
- Dismiss after eight seconds, pause on hover, and queue up to five alerts without changing keyboard focus.
- Skip startup/reconnect baselines, replaced agents, and repeated idle states. Preserve the unread badge after the alert expires.

## 1.0.9

- Sort agents by attention: unread replies and blocked agents first, working agents next, and already-read idle agents last.
- Keep the existing order within each group and stop treating a transition into working as an unread reply.

## 1.0.8

- Add a default Codex Chat view with shaded user prompts, labeled replies, paragraph spacing, bold list labels, and code formatting.
- Collapse recognized tool activity into expandable rows; retain unrecognized context and conversation recaps.
- Add a persistent Chat / Terminal switch. Other providers continue using Terminal.
- Preserve the working banner, separate model metadata, and stable output updates in both views.

## 1.0.7

- Keep terminal updates at the bottom in the same frame, avoiding cursor-driven scroll flashes.
- Preserve the last readable output through empty snapshots and connection interruptions.
- Suppress Codex's constantly changing terminal timer; activity remains visible in the HUD banner.

## 1.0.6

- Separate Codex's model and reasoning level into a labeled line above terminal output.
- Remove its trailing input prompt and model footer from the transcript viewer.

## 1.0.5

- Show a persistent animated working banner above the terminal while the selected agent is busy.
- Display observed elapsed time and distinguish new terminal output from waiting for output.

## 1.0.4

- Attach the panel to the H circle with a small visual connector.
- Move the panel with the circle, flip sides near screen edges, and fit the available space.

## 1.0.3

- Restore the original compact 800 × 590 panel size.

## 1.0.2

- Add an independent overlay visibility toggle, with Super+Shift+H setup instructions.
- Remember hidden state across restarts and pause roster polling while hidden.
- Keep Super+H as the panel toggle, including reopening a hidden overlay.

## 1.0.1

- Keep the draggable H button visible above the open panel so it can also close the panel.

## 1.0.0

- Native Omarchy panel with a draggable launcher and configurable keybind.
- Agent workspace names, status indicators, and attention badge.
- Resizable roster, live terminal viewer, and prompt composer.
- Saved launcher positions per monitor and roster width.
- Local Herdr bridge with identity checks before sending prompts.
- Fictional preview mode, install/update/removal instructions, and MIT license.
