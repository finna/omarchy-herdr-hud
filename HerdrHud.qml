import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "finna.herdr-hud"
  readonly property string pluginDir: (manifest && manifest.__sourceDir) || ""
  readonly property string bridgePath: String(Qt.resolvedUrl("bin/herdr-hud")).replace(/^file:\/\//, "")
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configDir: homeDir + "/.config/herdr-hud"
  readonly property string statePath: configDir + "/state.json"

  property bool opened: false
  property bool focusPrimed: false
  property string panelScreenName: ""
  property var agents: []
  property string selectedPane: ""
  property var unread: ({})
  property var lastSequence: ({})
  property var drafts: ({})
  property int dataRevision: 0
  property bool connected: false
  property bool sending: false
  property string errorText: "Connecting to Herdr…"
  property string noticeText: ""
  property string outputText: "Select an agent to view its terminal."
  property int rosterWidth: 196
  property var positions: ({})
  property int stateRevision: 0
  property bool stateReady: false

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color success: "#79dc94"
  readonly property color working: "#d5b46b"
  readonly property color gold: "#e8c67c"
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  readonly property color panelFill: Qt.rgba(background.r, background.g, background.b, 1)
  readonly property color terminalFill: Qt.rgba(0.035, 0.045, 0.052, 1)
  readonly property int edgeGap: 16
  readonly property int bubbleSize: 54

  function alpha(color, value) {
    return Qt.rgba(color.r, color.g, color.b, value)
  }

  function cloneObject(source) {
    var target = ({})
    for (var key in source) target[key] = source[key]
    return target
  }

  function screenByName(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function defaultScreenName() {
    var screen = screenByName(panelScreenName)
    return screen ? screen.name : ""
  }

  function positionFor(name, width, height) {
    stateRevision
    var saved = positions[name] || {}
    return {
      x: clamp(Number(saved.x === undefined ? width - bubbleSize - edgeGap : saved.x),
               edgeGap, Math.max(edgeGap, width - bubbleSize - edgeGap)),
      y: clamp(Number(saved.y === undefined ? 150 : saved.y),
               edgeGap, Math.max(edgeGap, height - bubbleSize - edgeGap))
    }
  }

  function clamp(value, lower, upper) {
    return Math.max(lower, Math.min(upper, value))
  }

  function savePosition(name, x, y) {
    var next = cloneObject(positions)
    next[name] = { x: Math.round(x), y: Math.round(y) }
    positions = next
    stateRevision++
    saveState()
  }

  function loadState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") {
        if (parsed.positions && typeof parsed.positions === "object") positions = parsed.positions
        if (Number(parsed.rosterWidth) > 0) rosterWidth = clamp(Number(parsed.rosterWidth), 150, 330)
      }
    } catch (error) {
      positions = ({})
    }
    stateReady = true
    stateRevision++
  }

  function saveState() {
    if (!stateReady) return
    stateFile.setText(JSON.stringify({
      version: 1,
      positions: positions,
      rosterWidth: Math.round(rosterWidth)
    }, null, 2) + "\n")
  }

  function open(payloadJson) {
    noticeText = ""
    if (focusedScreenProc.running) focusedScreenProc.running = false
    focusedScreenProc.exec([bridgePath, "focused-screen"])
  }

  function state(_arg) {
    var activeView = viewForScreen(panelScreenName || defaultScreenName())
    return JSON.stringify({
      opened: opened,
      panelScreenName: panelScreenName,
      bridgePath: bridgePath,
      screens: screenViews.instances.length,
      agents: agents.length,
      connected: connected,
      selectedPane: selectedPane,
      bubbleX: activeView ? Math.round(activeView.bubbleCurrentX) : null,
      bubbleY: activeView ? Math.round(activeView.bubbleCurrentY) : null,
      outputChars: outputText.length,
      notice: noticeText,
      error: errorText
    })
  }

  function openOnScreen(name) {
    panelScreenName = name || defaultScreenName()
    opened = true
    focusPrimed = false
    focusPrimeTimer.restart()
    refreshRoster()
    Qt.callLater(function() {
      var view = viewForScreen(panelScreenName)
      if (view) view.focusPrompt()
    })
  }

  function close() {
    opened = false
    focusPrimed = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function toggleOnScreen(name) {
    if (opened && panelScreenName === name) requestClose()
    else openOnScreen(name)
  }

  function viewForScreen(name) {
    for (var i = 0; i < screenViews.instances.length; i++) {
      var item = screenViews.instances[i]
      if (item && item.screenName === name) return item
    }
    return screenViews.instances.length ? screenViews.instances[0] : null
  }

  function agentForPane(pane) {
    for (var i = 0; i < agents.length; i++)
      if (String(agents[i].pane_id || "") === pane) return agents[i]
    return null
  }

  function selectAgent(pane) {
    var oldAgent = agentForPane(selectedPane)
    var view = viewForScreen(panelScreenName)
    if (oldAgent && view) {
      var nextDrafts = cloneObject(drafts)
      nextDrafts[selectedPane] = view.promptText()
      drafts = nextDrafts
    }
    selectedPane = pane
    var nextUnread = cloneObject(unread)
    delete nextUnread[pane]
    unread = nextUnread
    dataRevision++
    outputText = "Loading terminal output…"
    noticeText = ""
    Qt.callLater(function() {
      var activeView = viewForScreen(panelScreenName)
      if (activeView) activeView.setPromptText(String(drafts[pane] || ""))
      refreshOutput()
    })
  }

  function isReady(agent) {
    var status = String(agent ? agent.agent_status || "" : "")
    return status === "idle" || status === "done" || status === "blocked"
  }

  function statusLabel(agent) {
    var status = String(agent ? agent.agent_status || "" : "")
    if (status === "blocked") return "Needs your input"
    if (status === "idle" || status === "done") return "Ready for prompt"
    if (status === "working") return "Working"
    return "Status unknown"
  }

  function statusColor(agent) {
    if (!agent) return muted
    var pane = String(agent.pane_id || "")
    if (unread[pane] || isReady(agent)) return success
    if (String(agent.agent_status || "") === "working") return working
    return muted
  }

  function agentName(agent) {
    if (!agent) return "Agent"
    var type = String(agent.agent || "agent")
    return type.charAt(0).toUpperCase() + type.slice(1)
  }

  function attentionCount() {
    dataRevision
    var count = 0
    for (var i = 0; i < agents.length; i++) {
      var agent = agents[i]
      var pane = String(agent.pane_id || "")
      if (String(agent.agent_status || "") === "blocked" || unread[pane]) count++
    }
    return count
  }

  function refreshRoster() {
    if (rosterProc.running || bridgePath === "") return
    rosterProc.exec([bridgePath, "roster"])
  }

  function applyRoster(raw, error, exitCode) {
    if (exitCode !== 0) {
      connected = false
      errorText = String(error || "Herdr is unavailable").trim()
      return
    }
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var rows = Array.isArray(parsed.agents) ? parsed.agents : []
      var nextUnread = cloneObject(unread)
      var nextSequence = ({})
      var live = ({})
      for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        var pane = String(row.pane_id || "")
        var sequence = Number(row.state_change_seq || row.revision || 0)
        live[pane] = true
        nextSequence[pane] = sequence
        if (lastSequence[pane] !== undefined && lastSequence[pane] !== sequence
            && !(opened && pane === selectedPane)) nextUnread[pane] = true
      }
      for (var unreadPane in nextUnread) if (!live[unreadPane]) delete nextUnread[unreadPane]
      agents = rows
      unread = nextUnread
      lastSequence = nextSequence
      connected = true
      errorText = ""
      if (!agentForPane(selectedPane)) {
        selectedPane = rows.length ? String(rows[0].pane_id || "") : ""
        outputText = rows.length ? "Loading terminal output…" : "No agents are connected."
      }
      dataRevision++
      if (opened && selectedPane) refreshOutput()
    } catch (parseError) {
      connected = false
      errorText = "Herdr returned an unreadable response."
    }
  }

  function refreshOutput() {
    if (!opened || !selectedPane || outputProc.running) return
    outputProc.exec([bridgePath, "output", selectedPane])
  }

  function submitPrompt(message) {
    var agent = agentForPane(selectedPane)
    if (!agent || sending || !isReady(agent)) return
    if (!String(message || "").trim()) {
      noticeText = "Type a prompt first."
      return
    }
    sending = true
    noticeText = "Sending to " + selectedPane + "…"
    promptProc.exec([
      bridgePath,
      "prompt",
      selectedPane,
      String(agent.terminal_id || ""),
      String(message)
    ])
  }

  Component.onCompleted: {
    mkdirProc.running = true
    Qt.callLater(root.refreshRoster)
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
    onExited: function() { stateFile.reload() }
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Process {
    id: focusedScreenProc
    stdout: StdioCollector { id: focusedScreenOut; waitForEnd: true }
    stderr: StdioCollector { id: focusedScreenErr; waitForEnd: true }
    onExited: function(exitCode) {
      var name = ""
      if (exitCode === 0) {
        try { name = String(JSON.parse(focusedScreenOut.text).screen || "") }
        catch (error) { name = "" }
      }
      root.openOnScreen(name || root.defaultScreenName())
    }
  }

  Process {
    id: rosterProc
    stdout: StdioCollector { id: rosterOut; waitForEnd: true }
    stderr: StdioCollector { id: rosterErr; waitForEnd: true }
    onExited: function(exitCode) { root.applyRoster(rosterOut.text, rosterErr.text, exitCode) }
  }

  Process {
    id: outputProc
    stdout: StdioCollector { id: outputOut; waitForEnd: true }
    stderr: StdioCollector { id: outputErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.outputText = outputOut.text || "No terminal output yet."
      else root.noticeText = String(outputErr.text || "Could not read this agent.").trim()
    }
  }

  Process {
    id: promptProc
    stdout: StdioCollector { id: promptOut; waitForEnd: true }
    stderr: StdioCollector { id: promptErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.sending = false
      if (exitCode === 0) {
        var view = root.viewForScreen(root.panelScreenName)
        if (view) view.setPromptText("")
        var nextDrafts = root.cloneObject(root.drafts)
        nextDrafts[root.selectedPane] = ""
        root.drafts = nextDrafts
        root.noticeText = "Prompt sent."
        root.refreshRoster()
        outputDelay.restart()
      } else {
        root.noticeText = String(promptErr.text || "Could not send the prompt.").trim()
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: root.refreshRoster()
  }

  Timer {
    interval: 1200
    repeat: true
    running: root.opened
    onTriggered: root.refreshOutput()
  }

  Timer {
    id: outputDelay
    interval: 450
    onTriggered: root.refreshOutput()
  }

  Timer {
    id: focusPrimeTimer
    interval: 100
    onTriggered: root.focusPrimed = true
  }

  Variants {
    id: screenViews
    model: Quickshell.screens

    PanelWindow {
      id: overlayWindow
      required property var modelData
      readonly property string screenName: modelData.name
      readonly property bool panelVisible: root.opened && root.panelScreenName === screenName
      property bool draggingBubble: false
      property real bubbleX: root.positionFor(screenName, width, height).x
      property real bubbleY: root.positionFor(screenName, width, height).y
      readonly property real bubbleCurrentX: bubble.x
      readonly property real bubbleCurrentY: bubble.y
      property real rosterDragStart: 0
      property real rosterWidthStart: 0

      function focusPrompt() {
        if (panelVisible) {
          promptArea.forceActiveFocus()
          root.scrollOutputToBottom(outputScroll)
        }
      }

      function promptText() { return promptArea.text }
      function setPromptText(value) { promptArea.text = value }

      screen: modelData
      visible: true
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "herdr-hud"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: panelVisible
        ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
        : WlrKeyboardFocus.None

      mask: Region {
        Region {
          x: bubble.x
          y: bubble.y
          width: bubble.width
          height: bubble.height
          radius: bubble.width / 2
        }
        Region {
          x: panelCard.x
          y: panelCard.y
          width: overlayWindow.panelVisible ? panelCard.width : 0
          height: overlayWindow.panelVisible ? panelCard.height : 0
          radius: 18
        }
      }

      Rectangle {
        id: panelCard
        visible: overlayWindow.panelVisible
        width: Math.max(720, Math.min(parent.width - 48, 1220))
        height: Math.max(540, Math.min(parent.height - 64, 840))
        anchors.centerIn: parent
        color: root.panelFill
        radius: 18
        border.width: 2
        border.color: root.alpha(root.gold, 0.62)
        clip: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 18
          spacing: 12

          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            spacing: 12

            Text {
              text: "HERDR"
              color: root.gold
              font.family: Style.font.family
              font.pixelSize: 25
              font.bold: true
            }

            Rectangle {
              width: 1
              height: 26
              color: root.alpha(root.foreground, 0.22)
            }

            Text {
              Layout.fillWidth: true
              text: root.connected
                ? root.agents.length + " agent" + (root.agents.length === 1 ? "" : "s") + " connected"
                : "Herdr unavailable"
              color: root.muted
              font.family: Style.font.family
              font.pixelSize: 14
              elide: Text.ElideRight
            }

            Button {
              text: "Refresh"
              onClicked: root.refreshRoster()
              background: Rectangle {
                color: parent.hovered ? root.alpha(root.foreground, 0.14) : root.alpha(root.foreground, 0.07)
                radius: 8
                border.width: 1
                border.color: root.alpha(root.foreground, 0.2)
              }
              contentItem: Text {
                text: parent.text
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }

            Button {
              text: "×"
              implicitWidth: 42
              implicitHeight: 38
              onClicked: root.requestClose()
              background: Rectangle {
                color: parent.hovered ? root.alpha(root.foreground, 0.14) : root.alpha(root.foreground, 0.07)
                radius: 8
                border.width: 1
                border.color: root.alpha(root.foreground, 0.2)
              }
              contentItem: Text {
                text: parent.text
                color: root.foreground
                font.pixelSize: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
            }
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
              anchors.fill: parent
              spacing: 0

              Rectangle {
                Layout.preferredWidth: root.rosterWidth
                Layout.fillHeight: true
                color: root.alpha(root.foreground, 0.035)
                radius: 10
                border.width: 1
                border.color: root.alpha(root.foreground, 0.12)

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 8

                  Text {
                    Layout.fillWidth: true
                    text: "AGENTS"
                    color: root.muted
                    font.family: Style.font.family
                    font.pixelSize: 11
                    font.bold: true
                    leftPadding: 5
                  }

                  ListView {
                    id: rosterList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 7
                    model: root.agents
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                      id: agentRow
                      required property var modelData
                      width: ListView.view.width
                      height: 86
                      radius: 9
                      color: String(modelData.pane_id || "") === root.selectedPane
                        ? root.alpha(root.gold, 0.15)
                        : (agentMouse.containsMouse ? root.alpha(root.foreground, 0.08) : "transparent")
                      border.width: 1
                      border.color: String(modelData.pane_id || "") === root.selectedPane
                        ? root.alpha(root.gold, 0.72)
                        : root.alpha(root.foreground, 0.12)

                      MouseArea {
                        id: agentMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.selectAgent(String(agentRow.modelData.pane_id || ""))
                      }

                      RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 9

                        Rectangle {
                          Layout.alignment: Qt.AlignTop
                          Layout.topMargin: 4
                          width: 10
                          height: 10
                          radius: 5
                          color: root.statusColor(agentRow.modelData)
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 3

                          Text {
                            Layout.fillWidth: true
                            text: String(agentRow.modelData.workspace_label || "Untitled space")
                            color: root.gold
                            font.family: Style.font.family
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                          }
                          Text {
                            Layout.fillWidth: true
                            text: root.agentName(agentRow.modelData) + " · " + String(agentRow.modelData.pane_id || "")
                            color: root.muted
                            font.family: Style.font.family
                            font.pixelSize: 12
                            elide: Text.ElideRight
                          }
                          Text {
                            Layout.fillWidth: true
                            text: (root.unread[String(agentRow.modelData.pane_id || "")] ? "Unseen update · " : "")
                              + root.statusLabel(agentRow.modelData)
                            color: root.unread[String(agentRow.modelData.pane_id || "")] ? root.success : root.muted
                            font.family: Style.font.family
                            font.pixelSize: 11
                            elide: Text.ElideRight
                          }
                        }
                      }
                    }

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                  }
                }
              }

              Rectangle {
                id: rosterDivider
                Layout.preferredWidth: 10
                Layout.fillHeight: true
                color: dividerMouse.containsMouse || dividerMouse.pressed
                  ? root.alpha(root.gold, 0.35) : "transparent"

                Rectangle {
                  anchors.centerIn: parent
                  width: 2
                  height: parent.height
                  color: dividerMouse.containsMouse || dividerMouse.pressed
                    ? root.gold : root.alpha(root.foreground, 0.18)
                }

                MouseArea {
                  id: dividerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.SplitHCursor
                  onPressed: function(mouse) {
                    overlayWindow.rosterDragStart = mouse.x
                    overlayWindow.rosterWidthStart = root.rosterWidth
                  }
                  onPositionChanged: function(mouse) {
                    if (pressed) root.rosterWidth = root.clamp(
                      overlayWindow.rosterWidthStart + mouse.x - overlayWindow.rosterDragStart,
                      150, 330)
                  }
                  onReleased: root.saveState()
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 4
                spacing: 8

                Text {
                  Layout.fillWidth: true
                  text: {
                    var agent = root.agentForPane(root.selectedPane)
                    return agent ? String(agent.workspace_label || "Untitled space") + " / " + root.agentName(agent) : "Choose an agent"
                  }
                  color: root.gold
                  font.family: Style.font.family
                  font.pixelSize: 16
                  font.bold: true
                  elide: Text.ElideRight
                }

                Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  color: root.terminalFill
                  radius: 8
                  border.width: 1
                  border.color: root.alpha(root.foreground, 0.1)
                  clip: true

                  ScrollView {
                    id: outputScroll
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    TextArea {
                      id: outputArea
                      text: root.connected ? root.outputText : ""
                      readOnly: true
                      selectByMouse: true
                      wrapMode: TextEdit.WrapAnywhere
                      color: root.foreground
                      selectionColor: root.alpha(root.gold, 0.35)
                      selectedTextColor: root.foreground
                      font.family: "monospace"
                      font.pixelSize: 13
                      padding: 10
                      background: null
                      onTextChanged: Qt.callLater(function() { root.scrollOutputToBottom(outputScroll) })
                    }
                  }
                }

                Rectangle {
                  visible: !root.connected
                  Layout.fillWidth: true
                  Layout.preferredHeight: visible ? 108 : 0
                  color: root.alpha(root.urgent, 0.08)
                  radius: 8
                  border.width: 1
                  border.color: root.alpha(root.urgent, 0.35)

                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 5
                    Text {
                      Layout.fillWidth: true
                      text: "Herdr is not connected"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: 14
                      font.bold: true
                    }
                    Text {
                      Layout.fillWidth: true
                      text: root.errorText + "\nInstall or start Herdr, then choose Refresh."
                      color: root.muted
                      wrapMode: Text.Wrap
                      font.family: Style.font.family
                      font.pixelSize: 12
                    }
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 86
                  Layout.minimumHeight: 86
                  Layout.maximumHeight: 86
                  spacing: 10

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.alpha(root.foreground, 0.04)
                    radius: 8
                    border.width: 1
                    border.color: promptArea.activeFocus
                      ? root.alpha(root.gold, 0.78) : root.alpha(root.foreground, 0.14)

                    ScrollView {
                      anchors.fill: parent
                      anchors.margins: 3
                      clip: true
                      ScrollBar.vertical.policy: ScrollBar.AsNeeded

                      TextArea {
                        id: promptArea
                        placeholderText: root.selectedPane ? "Prompt this agent…" : "Choose an agent first"
                        enabled: !!root.selectedPane && !root.sending
                        wrapMode: TextEdit.Wrap
                        color: root.foreground
                        placeholderTextColor: root.muted
                        selectionColor: root.alpha(root.gold, 0.35)
                        selectedTextColor: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: 14
                        padding: 8
                        background: null

                        Keys.onPressed: function(event) {
                          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                              && (event.modifiers & Qt.ControlModifier)) {
                            root.submitPrompt(text)
                            event.accepted = true
                          } else if (event.key === Qt.Key_Escape) {
                            root.requestClose()
                            event.accepted = true
                          }
                        }
                      }
                    }
                  }

                  Button {
                    Layout.preferredWidth: 118
                    Layout.fillHeight: true
                    text: root.sending ? "Sending…" : "Send prompt"
                    enabled: {
                      var agent = root.agentForPane(root.selectedPane)
                      return !root.sending && root.isReady(agent) && promptArea.text.trim().length > 0
                    }
                    onClicked: root.submitPrompt(promptArea.text)
                    background: Rectangle {
                      color: parent.enabled
                        ? (parent.hovered ? root.alpha(root.gold, 0.55) : root.alpha(root.gold, 0.38))
                        : root.alpha(root.foreground, 0.06)
                      radius: 9
                      border.width: 1
                      border.color: parent.enabled ? root.alpha(root.gold, 0.75) : root.alpha(root.foreground, 0.12)
                    }
                    contentItem: Text {
                      text: parent.text
                      color: parent.enabled ? root.foreground : root.muted
                      font.family: Style.font.family
                      font.pixelSize: 13
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      wrapMode: Text.Wrap
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 20
                  text: root.noticeText || "Ctrl+Enter to send · Esc to close · drag the divider to resize agents"
                  color: root.noticeText ? root.gold : root.muted
                  font.family: Style.font.family
                  font.pixelSize: 12
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      Item {
        id: bubble
        width: root.bubbleSize
        height: root.bubbleSize
        x: overlayWindow.bubbleX
        y: overlayWindow.bubbleY

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: bubbleHover.hovered ? root.alpha(root.background, 0.98) : root.alpha(root.background, 0.92)
          border.width: 2
          border.color: root.attentionCount() > 0 ? root.success : root.alpha(root.gold, 0.82)

          Text {
            anchors.centerIn: parent
            text: "H"
            color: root.gold
            font.family: Style.font.family
            font.pixelSize: 25
            font.bold: true
          }
        }

        Rectangle {
          visible: root.attentionCount() > 0
          width: Math.max(19, badgeText.implicitWidth + 8)
          height: 19
          radius: 10
          anchors.right: parent.right
          anchors.top: parent.top
          color: root.success
          border.width: 2
          border.color: root.background

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.attentionCount() > 99 ? "99+" : String(root.attentionCount())
            color: "#102317"
            font.family: Style.font.family
            font.pixelSize: 10
            font.bold: true
          }
        }

        HoverHandler {
          id: bubbleHover
          cursorShape: bubbleDrag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onTapped: root.toggleOnScreen(overlayWindow.screenName)
        }

        DragHandler {
          id: bubbleDrag
          target: bubble
          acceptedButtons: Qt.LeftButton
          xAxis.minimum: root.edgeGap
          xAxis.maximum: Math.max(root.edgeGap, overlayWindow.width - bubble.width - root.edgeGap)
          yAxis.minimum: root.edgeGap
          yAxis.maximum: Math.max(root.edgeGap, overlayWindow.height - bubble.height - root.edgeGap)

          onActiveChanged: {
            if (active) {
              overlayWindow.draggingBubble = true
            } else if (overlayWindow.draggingBubble) {
              overlayWindow.bubbleX = bubble.x
              overlayWindow.bubbleY = bubble.y
              root.savePosition(overlayWindow.screenName, bubble.x, bubble.y)
              overlayWindow.draggingBubble = false
            }
          }
        }
      }
    }
  }

  function scrollOutputToBottom(scrollView) {
    if (!scrollView || !scrollView.contentItem) return
    var flick = scrollView.contentItem
    if (flick.contentY === undefined) return
    flick.contentY = Math.max(flick.originY || 0,
      (flick.contentHeight || 0) - (flick.height || 0))
  }
}
