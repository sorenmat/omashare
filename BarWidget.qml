import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Per-monitor view onto the single omaShare service. Owns no receiver state,
// no helper process, and no IPC target — all of that lives in Service.qml,
// which the shell loads exactly once via its `service` entry point. This
// file is a view plus this popup's own cursor (selected device, drafts).
Panel {
  id: root
  moduleName: "smo.omashare"
  // The `smo.omashare` IPC target belongs to the service, which exists once.
  manageIpc: false

  readonly property string manifestPluginId: "smo.omashare"
  readonly property var engine: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(manifestPluginId)
    : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The Quick Share mark is the Android glyph the bar font already carries
  // for device icons, so it is guaranteed to render.
  readonly property string barGlyph: "󰀲"

  readonly property bool receiverOn: engine ? engine.receiverEnabled && !engine.qsMissing : false
  readonly property bool busy: engine ? (engine.transferring || engine.sending || engine.scanning) : false

  // Popup-local state (per monitor): selected device, draft settings.
  property int deviceIndex: 0
  property string pathInput: ""
  property string nameInput: ""
  property string dirInput: ""
  property bool inputsSeeded: false

  readonly property string statusText: {
    if (!engine) return "Quick Share service is not loaded"
    if (engine.qsMissing) return "Install the qs CLI to receive files"
    if (engine.transferring)
      return engine.transferSender !== "" ? "Receiving from " + engine.transferSender : "Receiving…"
    if (engine.sending) return "Sending to " + engine.sendTarget + "…"
    if (engine.scanning) return "Scanning for devices…"
    if (!engine.receiverEnabled) return "Receiver off"
    if (engine.listening) return "Listening for Quick Share"
    if (engine.lastError !== "") return engine.lastError
    return "Starting receiver…"
  }

  readonly property string heroText: {
    if (!engine) return "Service not loaded"
    if (engine.qsMissing) return "qs not installed"
    if (engine.transferring) return "Receiving"
    if (engine.sending) return "Sending"
    if (engine.scanning) return "Scanning"
    if (!engine.receiverEnabled) return "Off"
    if (engine.listening) return "Ready"
    if (engine.lastError !== "") return "Error"
    return "Starting"
  }

  function seedInputs() {
    if (inputsSeeded || !engine) return
    nameInput = engine.deviceName
    dirInput = engine.destinationDir
    inputsSeeded = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      seedInputs()
      if (engine) {
        deviceIndex = 0
        engine.scanDevices()
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    // Off: dimmed mark. On: full bar foreground. Busy: accent.
    active: root.receiverOn || root.busy
    activeColor: root.busy ? root.Color.accent : root.barForeground
    foreground: Qt.darker(root.barForeground, 1.55)
    tooltipText: root.statusText

    onPressed: function(b) {
      if (b === Qt.RightButton && root.engine) root.engine.toggleReceiver()
      else root.toggle()
    }

    Rectangle {
      id: busyDot
      visible: root.busy
      width: Math.max(3, Math.round(Style.bar.iconCanvas * 0.22))
      height: width
      radius: width / 2
      color: root.Color.accent
      anchors.right: parent.right
      anchors.top: parent.top
      NumberAnimation on opacity {
        running: root.busy
        loops: Animation.Infinite
        from: 0.25
        to: 1.0
        duration: 700
        easing.type: Easing.InOutSine
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(body.implicitHeight)

    Column {
      id: body
      width: parent.width
      spacing: Style.space(12)

      // ------------------------------------------------------------- hero

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(44)
          height: Style.space(44)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

          Text {
            anchors.centerIn: parent
            text: root.barGlyph
            color: root.engine && root.engine.qsMissing ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.iconLarge
          }
        }

        Column {
          spacing: Style.space(2)
          width: parent.width - Style.space(54)

          Text {
            text: "Quick Share"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            text: root.heroText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        text: root.statusText
        color: root.engine && root.engine.lastError !== "" && !root.engine.qsMissing
          ? root.urgent
          : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        width: parent.width
        wrapMode: Text.WordWrap
        visible: text !== root.heroText
      }

      // ------------------------------------------------- qs missing panel

      Column {
        visible: root.engine !== null && root.engine.qsMissing
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "OmaShare needs the qs CLI, a small Quick Share client. Install it once:"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          wrapMode: Text.WordWrap
        }

        BorderSurface {
          width: parent.width
          implicitHeight: copyRow.implicitHeight + Style.space(10)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground)
          borderSpec: Border.none()

          Row {
            id: copyRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)
            width: parent.width

            Text {
              text: root.engine.installCommand
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width - Style.space(30)
            }

            PanelActionButton {
              iconText: "󰍝"
              foreground: root.foreground
              anchors.verticalCenter: parent.verticalCenter
              onHovered: function(isHovered) {
                if (root.bar) isHovered ? root.bar.showTooltip(root, "Copy install command") : root.bar.hideTooltip(root)
              }
              onClicked: Quickshell.execDetached(["wl-copy", root.engine.installCommand])
            }
          }
        }

        Button {
          text: "Check again"
          iconText: "󰔒"
          foreground: root.foreground
          onClicked: if (root.engine) root.engine.rescanQs()
        }
      }

      // ------------------------------------------------------ normal panel

      Column {
        visible: root.engine !== null && !root.engine.qsMissing
        width: parent.width
        spacing: Style.space(12)

        // firewall: phones connect straight to the advertised TCP port,
        // which a default-deny ufw drops. Offer the fix up front and show
        // the exact command the button runs (pkexec asks for the password).
        Column {
          visible: root.engine !== null && root.engine.firewallBlocked
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "The firewall is blocking incoming transfers"
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            width: parent.width
            wrapMode: Text.WordWrap
          }
          Text {
            text: "Phones connect directly to this machine on TCP port "
              + (root.engine ? root.engine.firewallPort : 0)
              + ". ufw's default-deny policy drops that connection, so transfers fall back to slow Bluetooth or fail. Clicking below asks for your password and runs exactly this:"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          BorderSurface {
            width: parent.width
            implicitHeight: fwCmdRow.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground)
            borderSpec: Border.none()

            Row {
              id: fwCmdRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)
              width: parent.width

              Text {
                text: root.engine ? root.engine.firewallFixCommand : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                width: parent.width - Style.space(16)
              }
            }
          }

          Button {
            text: root.engine && root.engine.firewallAction === "running"
              ? "Waiting for authorization…"
              : "Allow incoming TCP " + (root.engine ? root.engine.firewallPort : 0)
            iconText: "󰓇"
            background: Color.accent
            foreground: Color.background
            enabled: root.engine && root.engine.firewallAction !== "running"
            opacity: enabled ? 1.0 : 0.7
            onClicked: if (root.engine) root.engine.fixFirewall()
          }

          Text {
            visible: root.engine && root.engine.firewallAction === "running"
            text: "A password prompt should have opened — nothing changes until you approve it."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
          Text {
            visible: root.engine && root.engine.firewallAction !== "" && root.engine.firewallAction !== "running"
            text: root.engine && root.engine.firewallAction === "denied"
              ? "Cancelled — no changes were made."
              : "The command failed:" + (root.engine && root.engine.firewallActionDetail !== ""
                  ? "\n" + root.engine.firewallActionDetail : "")
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Check again"
            iconText: "󰔒"
            foreground: root.foreground
            onClicked: if (root.engine) root.engine.recheckFirewall()
          }
        }

        // receiver
        Row {
          width: parent.width
          spacing: Style.space(10)

          ToggleSwitch {
            checked: root.engine.receiverEnabled
            busy: root.engine.lastError !== "" && !root.engine.listening
            foreground: root.foreground
            onToggled: if (root.engine) root.engine.toggleReceiver()
          }

          Column {
            spacing: Style.space(1)
            width: parent.width - Style.space(70)

            Text {
              text: "Receive files from your phone"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: root.engine.receiverEnabled
                ? (root.engine.listening ? "Discoverable while the receiver runs" : "Starting…")
                : "Turned off — phones will not see this device"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Text {
          text: root.engine.effectiveDeviceName !== ""
            ? "Appears on phones as \u201C" + root.engine.effectiveDeviceName + "\u201D · saves to "
              + root.engine.effectiveOutDir
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          width: parent.width
          visible: text !== ""
        }

        Button {
          text: "Open save folder"
          iconText: "󰝰"
          foreground: root.foreground
          onClicked: if (root.engine) root.engine.openDestination()
        }

        PanelSeparator { foreground: root.foreground }

        // send
        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Row {
              spacing: Style.space(6)

              Text {
                text: "󰍂"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: "Send to phone"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            Item { width: scanButton.implicitWidth + Style.space(8) }
            Button {
              id: scanButton
              text: root.engine.scanning ? "Scanning…" : "Scan for devices"
              iconText: "󰍉"
              foreground: root.foreground
              enabled: !root.engine.scanning
              opacity: root.engine.scanning ? 0.6 : 1.0
              onClicked: if (root.engine) root.engine.scanDevices()
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.engine ? root.engine.devices : []

              BorderSurface {
                required property var modelData

                readonly property bool selected: root.deviceIndex === index
                width: parent.width
                implicitHeight: deviceRow.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: selected ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
                borderSpec: selected
                  ? Border.controlSpec("normal", root.foreground, Color.accent)
                  : Border.none()

                Row {
                  id: deviceRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)
                  width: parent.width

                  Text {
                    text: "󰀲"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Column {
                    spacing: Style.space(1)
                    width: parent.width - Style.space(26)

                    Text {
                      text: String(modelData.name || "Unknown device")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      text: [String(modelData.type || ""), String(modelData.ip || "")]
                        .filter(function(part) { return part !== "" }).join(" · ")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      visible: text !== ""
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.deviceIndex = index
                }
              }
            }

            Text {
              text: root.engine && root.engine.devices.length === 0 && !root.engine.scanning
                ? "No devices yet — open Quick Share on your phone (visible to everyone, over Wi-Fi) and scan."
                : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
              visible: text !== ""
            }
          }

          TextField {
            width: parent.width
            text: root.pathInput
            placeholderText: "File path to send…"
            foreground: root.foreground
            verticalPadding: Style.space(6)
            onTextChanged: root.pathInput = text
            Keys.onReturnPressed: root.sendSelected()
          }

          Text {
            text: root.engine ? root.engine.sendError : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
            visible: text !== ""
          }

          Row {
            width: parent.width
            Item { width: sendButton.implicitWidth + Style.space(8) }
            Button {
              id: sendButton
              text: root.engine && root.engine.sending ? "Sending…" : "Send"
              iconText: "󰅗"
              foreground: root.foreground
              enabled: !root.engine.sending
              opacity: root.engine.sending ? 0.6 : 1.0
              onClicked: root.sendSelected()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // recent
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: recentList.count > 0

          Row {
            spacing: Style.space(6)

            Text {
              text: "󰈠"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: "Recent files"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Repeater {
            id: recentList
            model: root.engine ? root.engine.recent : []

            BorderSurface {
              required property var modelData

              readonly property string name: Model.basename(String(modelData.path || ""))
              width: parent.width
              implicitHeight: recentRow.implicitHeight + Style.space(6)
              radius: Style.cornerRadius
              color: "transparent"
              borderSpec: Border.none()

              Row {
                id: recentRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)
                width: parent.width

                Text {
                  text: "󰈠"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: parent.width - Style.space(110)
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: Model.timeAgo(modelData.ts)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // Left opens the file itself, right its containing folder.
                onClicked: function(mouse) {
                  if (!root.engine) return
                  if (mouse.button === Qt.RightButton) root.engine.openFolderOf(modelData.path)
                  else root.engine.openFile(modelData.path)
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // settings
        Column {
          width: parent.width
          spacing: Style.space(8)

          Row {
            spacing: Style.space(6)

            Text {
              text: "󰒓"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              text: "Receiver settings"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "Device name shown on phones"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              width: parent.width
              text: root.nameInput
              placeholderText: "Default: this machine's hostname"
              foreground: root.foreground
              verticalPadding: Style.space(6)
              onTextChanged: root.nameInput = text
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: "Save received files to"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              width: parent.width
              text: root.dirInput
              placeholderText: "Default: ~/Downloads"
              foreground: root.foreground
              verticalPadding: Style.space(6)
              onTextChanged: root.dirInput = text
            }
          }

          Button {
            text: "Save settings"
            iconText: "󰒓"
            foreground: root.foreground
            onClicked: {
              if (!root.engine) return
              root.engine.setDeviceName(root.nameInput)
              root.engine.setDestinationDir(root.dirInput)
            }
          }
        }

        // footer
        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: "OmaShare 1.0.0"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.engine && root.engine.qsVersion !== "" ? "· qs " + root.engine.qsVersion : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Item { width: Style.space(8) }
          Text {
            text: "right-click the bar icon to toggle receiving"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // engine missing
      Column {
        visible: root.engine === null
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "The Quick Share service did not load."
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          wrapMode: Text.WordWrap
        }
        Text {
          text: "Restart the shell with: omarchy restart shell"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  function sendSelected() {
    if (!engine || engine.sending) return
    var target = ""
    if (engine.devices.length > 0) {
      var idx = Math.max(0, Math.min(deviceIndex, engine.devices.length - 1))
      target = String(engine.devices[idx].id || "")
    }
    if (target === "") {
      Quickshell.execDetached(["notify-send", "-a", "OmaShare", "Quick Share",
        "No device selected — open Quick Share on your phone and scan for devices."])
      return
    }
    engine.sendFile(pathInput, target)
  }
}
