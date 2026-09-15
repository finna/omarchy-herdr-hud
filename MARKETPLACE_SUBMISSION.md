### Repository URL

https://github.com/finna/omarchy-herdr-hud

### Category

Developer Tools

### Tags

ai, games, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Current release: v1.0.17. A persistent UI toggle switches between Omarchy and a standalone WoW style. The HUD follows Omarchy theme colors, including popup border gradients and light/dark surface contrast. Chat extends to the top of the panel, with branding and agent count in the sidebar. H and Esc close the panel; polling is automatic. The selected card identifies the agent, and its tooltip shows available model details. Recognized conversations use formatted chat, with plain output preserved when formatting is unavailable.

Herdr HUD is a native Omarchy Quattro panel for monitoring and prompting local Herdr agents over fullscreen apps. It includes a draggable launcher, workspace names, attention indicators, an adjustable roster, and live terminal output.

Requires Herdr 0.9.0+ running and on PATH, and Python 3. It reads via local Herdr and Hyprland commands and sends prompts via the local socket API, installs no service, and needs no elevated privileges. The optional keybind is documented for manual setup; the plugin does not edit Hyprland configuration. Blocked-agent approvals remain in Herdr.

Addresses both requested process-boundary fixes: prompts use stdin/socket transport, and command stdout/stderr have streaming byte caps with process-group termination and reaping on overflow or timeout. Custom backends require an explicit stdin-capable prompt adapter.

Validated with `omarchy plugin validate`, Python process/socket/QML integration tests, and JavaScript roster/alert tests. Tested on Omarchy Quattro 4.0.2 over a fullscreen terminal. Specific games and multiple monitors have not yet been verified. Screenshots and the demo use fictional agents.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
