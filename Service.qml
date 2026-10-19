import QtQuick
import Quickshell.Io

// Headless singleton for the Usage Tray plugin.
//
// The chip only renders the cache (`ai-usage waybar`); the cache is written by
// `ai-usage refresh`. A bar widget is created once per monitor, so the probe
// belongs here: one process per plugin refreshes the cache that every monitor's
// widget then re-renders.
Item {
  id: root

  // Emitted after every refresh run, successful or not: listeners re-read the
  // cache and show whatever the last probe wrote.
  signal probed()

  // Same resolution as BarWidget.qml: the CLI shipped next to this file when
  // the plugin is loaded from a checkout, the PATH binary otherwise.
  readonly property string tool: {
    const url = Qt.resolvedUrl("bin/ai-usage").toString()
    if (url.startsWith("file://"))
      return decodeURIComponent(url.slice(7))
    return "ai-usage"
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    // Skip a tick, don't queue one: `refresh` probes the roster serially, so a
    // slow run must not be joined by a second process writing the same cache.
    onTriggered: if (!probe.running) probe.running = true
  }

  Process {
    id: probe
    command: [root.tool, "refresh"]
    // `refresh` prints one progress line per provider. Without a stdout/stderr
    // parser Quickshell closes those pipes and the CLI would write into a
    // closed pipe; the collectors keep both drained.
    stdout: StdioCollector { }
    stderr: StdioCollector { }
    onExited: root.probed()
  }
}