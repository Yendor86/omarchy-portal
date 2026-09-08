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

  // A "limited" blip is common and short — this machine's journal shows
  // full -> limited -> full three times in twelve minutes on working wifi.
  // Acting on the first sight of it fired a critical VPN notification, or
  // opened a browser, for a network that was fine two seconds later. So a
  // non-"portal" state has to still be there after a pause before we act.
  readonly property int settleMs: 7000

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

    if (next === "portal") {
      root.act("portal")
    } else {
      // limited/none: let it settle first.
      settleTimer.pending = next
      settleTimer.restart()
    }
  }

  function act(why) {
    var now = Date.now()
    if (now - root.lastOpenedAt < root.reopenCooldownMs) {
      logEvent("suppressed", "inside cooldown")
      return
    }
    logEvent("running", why)
    openProcess.running = false
    // Path passed as an ARGUMENT, not concatenated into the script text: the
    // plugin directory is not attacker-controlled, but a space or a quote in
    // it broke the quoting outright.
    openProcess.command = ["bash", "-lc",
      "if [ -x \"$1\" ]; then exec \"$1\" open; else exec omarchy-portal open; fi",
      "omarchy-portal", root.cliPath]
    openProcess.running = true
  }

  // Re-read the state after the pause; only act if it is still not "full".
  Timer {
    id: settleTimer
    property string pending: ""
    interval: root.settleMs
    onTriggered: recheck.running = true
  }

  Process {
    id: recheck
    command: ["env", "LC_ALL=C", "nmcli", "-t", "networking", "connectivity"]
    stdout: SplitParser {
      onRead: function (line) {
        var st = String(line).trim()
        if (st === "full" || st === "unknown") {
          root.logEvent("settled", "was " + settleTimer.pending + ", now " + st + " — ignoring")
          return
        }
        root.act(st + " (settled)")
      }
    }
  }

  // Event-driven: one line per change, nothing in between.
  Process {
    id: monitor
    running: true
    command: ["env", "LC_ALL=C", "nmcli", "monitor"]
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
    command: ["env", "LC_ALL=C", "nmcli", "-t", "networking", "connectivity"]
    stdout: SplitParser {
      onRead: function (line) { root.handleState(String(line).trim()) }
    }
  }

  Process {
    id: openProcess
    // Arm the cooldown only when the CLI actually opened something. Setting
    // it on every trigger meant a dropped connection could suppress the real
    // portal thirty seconds later.
    onExited: function (code) {
      if (code === 0) {
        root.lastOpenedAt = Date.now()
        root.logEvent("opened", "login page")
      } else {
        root.logEvent("no-action", "cli exit " + code)
      }
    }
  }
}
