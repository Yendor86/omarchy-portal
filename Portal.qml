import QtQuick
import Quickshell
import Quickshell.Io

// Captive portal assistant.
//
// NetworkManager already does the hard part: on every network change it
// fetches a known plain-HTTP URL and sets its connectivity state to "portal"
// when the answer is a redirect rather than the expected body. On Omarchy
// nothing listened for that, so a hotel or airport login page simply looked
// like broken wifi.
//
// This listens. `nmcli monitor` emits a line whenever the state changes, so
// there is no polling — the process sits idle until NetworkManager has
// something to say.
Item {
  id: root

  property var shell: null

  // Resolve the CLI next to this file rather than trusting PATH. Installing
  // via `omarchy plugin add` clones the repo straight into the plugins
  // directory and never runs install.sh, so ~/.local/bin/omarchy-portal will
  // not exist. Falling back to PATH keeps a symlinked dev checkout working.
  readonly property string cliPath:
    Qt.resolvedUrl("bin/omarchy-portal").toString().replace(/^file:\/\//, "")

  // Guard against re-opening the browser every time NM re-checks while the
  // user is still typing their room number into the login page.
  property string lastState: ""
  property double lastOpenedAt: 0
  readonly property int reopenCooldownMs: 90000

  function logEvent(event, details) {
    console.log("omarchy portal " + new Date().toISOString() + " " + event +
                (details ? ": " + details : ""))
  }

  function handleState(next) {
    if (next === root.lastState) return
    root.lastState = next
    logEvent("connectivity", next)
    // "portal" is the clean case. But a VPN kill switch, or a portal that
    // simply drops everything rather than redirecting, leaves NetworkManager
    // reporting "limited" or "none" instead — nothing answered, so it cannot
    // know a login page exists. Those are the states you actually hit in a
    // hotel with a VPN running, so treat them as candidates too and let the
    // CLI decide (it stays quiet when there is no network attached).
    if (next !== "portal" && next !== "limited" && next !== "none") return

    var now = Date.now()
    if (now - root.lastOpenedAt < root.reopenCooldownMs) {
      logEvent("suppressed", "portal seen again inside cooldown")
      return
    }
    root.lastOpenedAt = now
    logEvent("opening", "captive portal login page")
    openProcess.running = false
    openProcess.command = ["bash", "-lc",
      "if [ -x '" + root.cliPath + "' ]; then '" + root.cliPath + "' open; else omarchy-portal open; fi"]
    openProcess.running = true
  }

  // Event-driven: one line per change, nothing in between.
  Process {
    id: monitor
    running: true
    command: ["bash", "-lc", "nmcli monitor"]
    stdout: SplitParser {
      onRead: function (line) {
        var m = String(line).match(/Connectivity is now '([a-z]+)'/)
        if (m) root.handleState(m[1])
      }
    }
    onExited: function (code) {
      logEvent("monitor-exited", "code=" + code + ", restarting")
      restartTimer.restart()
    }
  }

  // nmcli monitor dies with NetworkManager; come back when it does.
  Timer {
    id: restartTimer
    interval: 4000
    onTriggered: monitor.running = true
  }

  // Catch the case where the shell starts while already behind a portal —
  // logging in is exactly when you are most likely to restart something.
  Process {
    id: initialProbe
    running: true
    command: ["bash", "-lc", "nmcli -t networking connectivity"]
    stdout: SplitParser {
      onRead: function (line) { root.handleState(String(line).trim()) }
    }
  }

  Process { id: openProcess }
}
