pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.veigapunk.usage-tray"

  readonly property string tool: {
    const url = Qt.resolvedUrl("bin/ai-usage").toString()
    if (url.startsWith("file://"))
      return decodeURIComponent(url.slice(7))
    return "ai-usage"
  }

  property string chip: "usage"

  readonly property bool opened: false
  function open() { root.run(["cycle", "next"]) }
  function close() {}
  function toggle() { root.run(["cycle", "next"]) }
  function closeForPopoutSwitch() {}

  function run(args) {
    Quickshell.execDetached([root.tool].concat(args))
    refreshTimer.restart()
  }

  function refresh() {
    if (!probe.running)
      probe.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: probe
    command: [root.tool, "waybar"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        const line = text.trim()
        try {
          const parsed = JSON.parse(line)
          if (parsed.text)
            root.chip = parsed.text
        } catch (error) {
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.chip
    tooltipText: "Usage"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton)
        root.run(["identity", "next"])
      else if (buttonCode === Qt.LeftButton)
        root.run(["cycle", "next"])
    }
  }
}
