"""Exercise HUD theme bindings with the installed Omarchy components."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SHELL = Path('/usr/share/omarchy/shell')


@unittest.skipUnless(shutil.which('quickshell') and SHELL.exists(), 'Omarchy is required')
class ThemeTests(unittest.TestCase):
    def test_alert_uses_panel_chrome(self):
        source = (ROOT / 'HerdrHud.qml').read_text()
        alert = source[source.index('      Ui.BorderSurface {\n        id: completionAlert'):source.index('      Item {\n        id: bubble')]
        self.assertIn('color: root.wowMode ? "transparent" : root.panelFill', alert)
        self.assertIn('borderSpec: root.wowMode ? Border.none() : root.panelBorderSpec', alert)
        self.assertIn('radius: root.cornerRadius', alert)
        self.assertIn('WowFrame {', alert)
        self.assertIn('fillColor: root.panelFill', alert)
        self.assertIn('visible: root.wowMode', alert)
        self.assertNotIn('border.color:', alert)

    def test_live_palette_and_border(self):
        source = (ROOT / 'HerdrHud.qml').read_text()
        palette = source[source.index('  property string uiMode'):source.index('  function cloneObject')]
        render = source[source.index('  function renderConversation()'):]
        render = render[:render.rfind('}')]
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            (temp / 'Commons').symlink_to(SHELL / 'Commons')
            (temp / 'Ui').symlink_to(SHELL / 'Ui')
            for name in ('HerdrHud.qml', 'Roster.js', 'Alerts.js', 'WowFrame.qml', 'WowLauncher.qml'):
                (temp / name).write_text((ROOT / name).read_text())
            qml = '''import QtQuick
import Quickshell
import qs.Commons
import qs.Ui as Ui
Scope {
 id: root
 PALETTE
 property int stateRevision: 0
 property var screenViews: ({instances: []})
 property int saves: 0
 property bool alertsEnabled: true
 function saveState() { saves++ }
 property string blocksJson: '[{"kind":"prompt","html":"hello"}]'
 property var expandedTools: ({})
 readonly property string chatHtml: renderConversation()
 RENDER
 Ui.BorderSurface { id: surface; width: 200; height: 100; radius: 18; borderSpec: root.panelBorderSpec }
 function check(value, message) { if (!value) throw new Error(message) }
 Timer {
 interval: 100; running: true
 onTriggered: {
 try {
 var hud = Qt.createComponent("HerdrHud.qml")
 check(hud.status === Component.Ready || (!Quickshell.env("WAYLAND_DISPLAY") && hud.errorString().includes("No PanelWindow backend loaded")), "full HUD compilation: " + hud.errorString())
 Color.loadUserShell("")
 Color.loadColors('background = "#111111"\\nforeground = "#eeeeee"\\naccent = "#336699"')
 Color.loadShell('[popups]\\nborder = "#336699"')
 check(Qt.colorEqual(root.panelBorder, "#336699"), "dark border")
 var previousHtml = root.chatHtml
 Color.loadColors('background = "#ffffff"\\nforeground = "#222222"\\naccent = "#884422"')
 Color.loadShell('[hyprland]\\nactive-border = "#884422 #225588 45deg"\\n[popups]\\nborder = "hyprland.active-border"\\nborder-width = "1 2 3 4"\\nborder-alpha = 0.5')
 check(root.panelBorderSpec.gradient.enabled, "gradient")
 check(surface.usesOverlayBorder, "gradient renderer")
 check(surface.borderLeft === 4 && surface.borderBottom === 3, "per-side widths")
 check(Math.abs(root.panelBorder.a - 0.5) < 0.01, "alpha")
 check(root.chatHtml !== previousHtml && root.chatHtml.includes("#884422"), "live rich text")
 check(root.terminalFill.r > 0.9, "light terminal")
 check(Qt.colorEqual(root.accentText, root.background), "contrasting label: " + root.accentText + " bg " + root.background + " fg " + root.foreground + " direct " + root.contrastColor(root.accent, root.foreground, root.background))
 Color.loadShell("")
 check(Qt.colorEqual(root.panelBorder, root.accent), "missing border fallback")
 root.toggleUiMode()
 check(root.uiMode === "wow" && root.cornerRadius === 4 && root.saves === 1, "switch and save WoW")
 check(Qt.colorEqual(root.launcherAccent, "#884422"), "normal launcher ignores WoW panel palette")
 var wowBackground = root.background, wowAccent = root.accent
 Color.loadColors('background = "#123456"\\nforeground = "#abcdef"\\naccent = "#ff00ff"')
 check(Qt.colorEqual(root.background, wowBackground) && Qt.colorEqual(root.accent, wowAccent), "WoW independent of Omarchy")
 for (var launcher = 0; launcher < 5; launcher++) {
   root.launcherStyle = launcher
   check(Qt.colorEqual(root.launcherAccent, "#ff00ff"), "normal launcher follows live theme in WoW mode")
   check(Qt.colorEqual(root.launcherBackground, Color.popups.background), "launcher background follows theme")
   check(Qt.colorEqual(root.launcherText, root.contrastColor(Color.accent, Color.popups.text, Color.popups.background)), "launcher label contrast follows theme")
 }
 root.launcherStyle = 5
 var medallionAccent = root.launcherAccent, medallionBackground = root.launcherBackground
 var medallionText = root.launcherText, medallionSuccess = root.launcherSuccess
 Color.loadColors('background = "#ffffff"\\nforeground = "#222222"\\naccent = "#336699"')
 check(Qt.colorEqual(root.launcherAccent, medallionAccent) && Qt.colorEqual(root.launcherBackground, medallionBackground), "WoW launcher ignores theme changes")
 check(Qt.colorEqual(root.launcherText, medallionText) && Qt.colorEqual(root.launcherSuccess, medallionSuccess), "WoW badge ignores theme changes")
 root.toggleUiMode()
 check(root.uiMode === "omarchy" && root.cornerRadius === 0 && root.saves === 2, "switch and save Omarchy")
 check(Qt.colorEqual(root.accent, "#336699"), "restore current Omarchy theme")
 check(Qt.colorEqual(root.launcherAccent, medallionAccent), "WoW launcher ignores panel mode")
 root.launcherStyle = 0
 check(Qt.colorEqual(root.launcherAccent, "#336699"), "normal launcher restores current theme")
 var widths = [54, 54, 32, 32, 96, 54]
 var heights = [54, 54, 32, 32, 28, 54]
 for (var style = 0; style < 6; style++) {
   check(root.launcherStyle === style, "launcher carousel order")
   check(root.bubbleWidth === widths[style] && root.bubbleHeight === heights[style], "launcher dimensions")
   root.cycleLauncherStyle()
 }
 check(root.launcherStyle === 0 && root.saves === 8, "launcher wraps and saves")
 console.log("HUD_THEME_PASS")
 } catch (error) { console.error(error) }
 Qt.quit()
 }
 }
}
'''.replace('PALETTE', palette).replace('RENDER', render)
            (temp / 'shell.qml').write_text(qml)
            result = subprocess.run(
                ['quickshell', '--no-color', '-p', str(temp / 'shell.qml')],
                env={**os.environ, 'HOME': directory, 'QT_QPA_PLATFORM': 'wayland' if os.environ.get('WAYLAND_DISPLAY') else 'offscreen'},
                capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HUD_THEME_PASS', output)
            self.assertNotIn('failed to load', output.lower())
