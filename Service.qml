import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One omaShare engine per shell session, not one per monitor.
//
// The bar instantiates its widgets once per screen, so the receiver helper,
// the transfer state, and the IPC target all live here in the `service`
// entry point, which the shell loads exactly once. Every bar widget is a
// view onto this object and owns nothing but its own cursor and popup.
Item {
  id: root

  // Injected by the shell when the service is created.
  property var shell: null
  property var manifest: null

  readonly property string manifestPluginId: "smo.omashare"
  readonly property string metadataSourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : ""
  readonly property string pluginDir: metadataSourceDir !== ""
    ? metadataSourceDir
    : (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/" + manifestPluginId
  readonly property string helperPath: pluginDir + "/helpers/omashare-helper"

  // Settings come from the shell config, not from the widgets. The widget is
  // built once per monitor and gets its `settings` a tick after creation, so
  // it cannot report the persisted state at the moment the receiver starts,
  // and several widgets reporting the same state is redundant.
  readonly property var configEntry: shell && shell.shellConfig
    ? Model.barEntry(shell.shellConfig, manifestPluginId)
    : null
  readonly property bool configured: configEntry !== null
  readonly property var entrySettings: configEntry ? configEntry.settings : ({})
  readonly property bool receiverEnabled: Model.receiverEnabledIn(configEntry)
  readonly property string deviceName: String(entrySettings.deviceName || "").trim()
  readonly property string destinationDir: String(entrySettings.destinationDir || "").trim()

  property bool qsMissing: true
  property string qsPath: ""
  property string qsVersion: ""
  property string helperVersion: ""
  property string effectiveDeviceName: ""
  property string effectiveOutDir: ""

  property bool listening: false
  property bool transferring: false
  property string transferSender: ""
  property string lastError: ""
  property int restartAttempts: 0
  property int pendingFiles: 0

  // Recent incoming files, newest last. `qs` reports a path per saved file;
  // sizes are not available from the CLI, so keep the list lean.
  property var recent: []

  // Outgoing transfer and device scan state.
  property bool scanning: false
  property var devices: []
  property bool sending: false
  property string sendTarget: ""
  property string sendPath: ""
  property string sendError: ""

  readonly property string installCommand: "cargo install --git https://github.com/martinalderson/qs"

  // The helper is restarted when receiver settings change: command identity
  // is what Quickshell's Process uses to decide that a running child has to
  // be replaced, so fold the settings that feed it into the command.
  // The env indirection injects RUST_LOG into `qs receive`: Quickshell's
  // Process has no environment property, and this keeps the receiver's
  // protocol activity (incl. the Wi-Fi bandwidth upgrade) visible in the
  // shell log via the helper's stderr.
  readonly property var helperCommand: [
    "/usr/bin/env",
    "RUST_LOG=info,rqs_lib=debug,mdns_sd=warn",
    helperPath,
    destinationDir !== "" ? "--out" : "",
    destinationDir !== "" ? destinationDir : "",
    deviceName !== "" ? "--name" : "",
    deviceName !== "" ? deviceName : ""
  ].filter(function(part) { return part !== "" })

  function persistSettings(props) {
    if (!shell) return
    var settings = Object.assign({}, entrySettings, props)
    if (Model.hasStringBarEntry(shell.shellConfig, manifestPluginId)
        && typeof shell.mutateShellConfig === "function") {
      shell.mutateShellConfig(function(config) {
        Model.promoteStringBarEntry(config, manifestPluginId, settings)
      })
      return
    }
    shell.updateEntryInline(manifestPluginId, settings)
  }

  function toggleReceiver() {
    if (!configured) return
    persistSettings({ receiverEnabled: !receiverEnabled })
  }

  function setDeviceName(name) {
    persistSettings({ deviceName: String(name || "").trim() })
  }

  function setDestinationDir(dir) {
    persistSettings({ destinationDir: String(dir || "").trim() })
  }

  function summonView(action) {
    if (!shell) return "unknown"
    var ok = false
    try {
      ok = shell[action](manifestPluginId, "{}")
    } catch (e) {
      ok = false
    }
    return ok === true ? "ok" : "unknown"
  }

  function send(command) {
    if (!helperProcess.running) return
    helperProcess.write(JSON.stringify(command) + "\n")
  }

  function notifyReceived(count) {
    var body = count > 0
      ? "Received " + count + " file" + (count === 1 ? "" : "s") + " via Quick Share"
      : "Received a transfer via Quick Share"
    Quickshell.execDetached(["notify-send", "-a", "OmaShare", "Quick Share", body])
  }

  function openDestination() {
    var dir = effectiveOutDir !== "" ? effectiveOutDir : (Quickshell.env("HOME") || "") + "/Downloads"
    if (dir !== "") Quickshell.execDetached(["xdg-open", dir])
  }

  function openFile(path) {
    var value = String(path || "")
    if (value !== "") Quickshell.execDetached(["xdg-open", value])
  }

  function openFolderOf(path) {
    var value = String(path || "")
    var at = value.lastIndexOf("/")
    if (at <= 0) return
    Quickshell.execDetached(["xdg-open", value.substring(0, at)])
  }

  function rescanQs() {
    qsProbe.running = false
    qsProbeKickTimer.restart()
  }

  function scanDevices() {
    if (scanning || qsMissing || qsPath === "") return
    scanning = true
    devices = []
    devicesProcess.command = [qsPath, "devices", "--json", "--timeout", "10"]
    devicesProcess.running = true
  }

  function sendFile(path, target) {
    var file = String(path || "").trim()
    var dest = String(target || "").trim()
    if (sending || qsMissing || qsPath === "" || file === "" || dest === "") return
    sendError = ""
    sendPath = file
    sendTarget = dest
    sending = true
    sendProcess.command = [qsPath, "send", file, "--to", dest, "--timeout", "30"]
    sendProcess.running = true
  }

  function handleEvent(event) {
    if (!event || !event.event) return
    switch (event.event) {
      case "ready":
        helperVersion = String(event.version || "")
        qsVersion = String(event.qsVersion || "")
        effectiveDeviceName = String(event.deviceName || "")
        effectiveOutDir = String(event.outDir || "")
        restartAttempts = 0
        break
      case "listening":
        listening = true
        lastError = ""
        break
      case "transfer_starting":
        transferring = true
        transferSender = String(event.sender || "")
        pendingFiles = 0
        break
      case "file_received": {
        var path = String(event.path || "")
        if (path !== "") {
          pendingFiles += 1
          var next = recent.slice()
          next.push({ path: path, ts: Date.now() })
          while (next.length > 15) next.shift()
          recent = next
        }
        break
      }
      case "transfer_done":
        transferring = false
        var count = Number(event.fileCount) || 0
        if (count < pendingFiles) count = pendingFiles
        pendingFiles = 0
        if (count > 0) notifyReceived(count)
        break
      case "transfer_failed":
        transferring = false
        pendingFiles = 0
        lastError = "Transfer " + String(event.reason || "failed")
        break
      case "receiver_error":
        listening = false
        lastError = String(event.detail || "")
        break
      case "receiver_restarting":
        listening = false
        break
      case "stopped":
        listening = false
        transferring = false
        lastError = ""
        break
      case "error":
        if (String(event.code || "") === "qs_missing") {
          qsMissing = true
          listening = false
        }
        break
    }
  }

  IpcHandler {
    target: "smo.omashare"
    function open(): string { return root.summonView("summon") }
    function close(): string { return root.summonView("hide") }
    function toggle(): string { return root.summonView("toggle") }
    function receiverOn(): string { if (!root.receiverEnabled) root.toggleReceiver(); return "ok" }
    function receiverOff(): string { if (root.receiverEnabled) root.toggleReceiver(); return "ok" }
    function receiverToggle(): string { root.toggleReceiver(); return "ok" }
    function rescanQs(): string { root.rescanQs(); return "ok" }
    function scanDevices(): string { root.scanDevices(); return "ok" }
    function status(): string {
      return JSON.stringify({
        enabled: root.receiverEnabled,
        listening: root.listening,
        transferring: root.transferring,
        receiver: root.receiverEnabled && !root.qsMissing && helperProcess.running,
        qsMissing: root.qsMissing,
        qsVersion: root.qsVersion,
        helperVersion: root.helperVersion,
        recent: root.recent.length,
        error: root.lastError
      })
    }
  }

  // Probe for the qs CLI. The shell process may not carry the user's login
  // PATH, so check the usual install locations as well as PATH.
  Process {
    id: qsProbe
    running: true
    // On this system `qs` on PATH is Quickshell, so user-local installs are
    // tried first and every candidate is verified by its version banner
    // ("qs 0.1.0" — Quickshell prints "Quickshell …") before being trusted.
    command: ["bash", "-c",
      "for p in \"$HOME/.cargo/bin/qs\" \"$HOME/.local/bin/qs\" \"$(command -v qs 2>/dev/null)\"; do"
      + " [ -x \"$p\" ] || continue;"
      + " case \"$($p --version 2>/dev/null | head -n1)\" in"
      + "  qs\\ [0-9]*) echo \"$p\"; exit 0 ;;"
      + " esac;"
      + " done; exit 1"]
    stdout: StdioCollector {
      id: qsProbeStdout
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value !== "") root.qsPath = value
      }
    }
    onExited: function(exitCode) {
      root.qsMissing = exitCode !== 0
    }
  }

  Timer {
    id: qsProbeKickTimer
    interval: 150
    repeat: false
    onTriggered: qsProbe.running = true
  }

  // Writing to Process.running replaces its declarative binding, so a restart
  // reinstalls the binding instead of assigning a plain true; that is what
  // lets receiver OFF -> ON still start the helper after a restart attempt.
  Process {
    id: helperProcess
    property bool startedOnce: false
    running: root.configured && root.receiverEnabled && !root.qsMissing
    command: root.helperCommand
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleEvent(Model.parseLine(line)) } }
    stderr: SplitParser { onRead: function(line) { console.warn("omashare helper:", line) } }
    onStarted: {
      helperProcessStarted = true
      root.listening = false
      root.lastError = ""
    }
    onRunningChanged: {
      if (running) return
      // A helper whose binary is missing never reaches onExited: Quickshell
      // flips running back to false without an exit code.
      if (helperProcessStarted) return
      if (root.receiverEnabled && !root.qsMissing && root.configured) {
        root.lastError = "Receiver helper did not start (is helpers/omashare-helper present and executable?)"
      }
    }
    onExited: function(code) {
      root.helperProcessStarted = false
      root.handleHelperExit(code)
    }
  }

  property bool helperProcessStarted: false

  function bindHelperRunning() {
    helperProcess.running = Qt.binding(function() {
      return root.configured && root.receiverEnabled && !root.qsMissing
    })
  }

  function handleHelperExit(code) {
    root.listening = false
    root.transferring = false
    if (!root.receiverEnabled || root.qsMissing || !root.configured) return
    if (root.restartAttempts < 4) {
      root.restartAttempts += 1
      root.lastError = "Receiver stopped, restarting…"
      helperRestartTimer.restart()
    } else {
      root.lastError = "Receiver keeps stopping; toggle Quick Share off and on to try again."
    }
  }

  Timer {
    id: helperRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (root.receiverEnabled && !root.qsMissing && root.configured && !helperProcess.running)
        root.bindHelperRunning()
    }
  }

  Process {
    id: devicesProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: devicesStdout
      waitForEnd: true
      onStreamFinished: root.devices = Model.parseDevices(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.devices = []
      root.scanning = false
    }
  }

  Process {
    id: sendProcess
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: sendStderr
      waitForEnd: true
      onStreamFinished: root.sendError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.sending = false
      if (exitCode === 0) {
        root.sendError = ""
        Quickshell.execDetached(["notify-send", "-a", "OmaShare", "Quick Share",
          "Sent to " + root.sendTarget])
      } else {
        root.sendError = root.sendError !== ""
          ? root.sendError
          : "Send failed (no matching device, or the phone declined)"
      }
    }
  }

  function destroy() {
    if (helperProcess.running) send({ command: "shutdown" })
  }
}
