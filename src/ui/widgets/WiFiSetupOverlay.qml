import QtQuick 2.15

Item {
    id: root

    property var wifi
    property var theme
    property string selectedSsid: ""
    property string countryCode: "AU"
    property Item activeField: null
    property bool upperCase: false
    property bool showDetails: false
    readonly property bool canProvision: !!wifi && wifi.onboardingEnabled
    readonly property bool modalMode: !!wifi && wifi.setupRequired
    readonly property var keyboardRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["SHIFT", "z", "x", "c", "v", "b", "n", "m", "BKSP"],
        ["SPACE", ".", "-", "_", "@", "!", "/", "CLEAR"]
    ]

    anchors.fill: parent
    z: 9500
    visible: !!wifi && wifi.promptVisible

    function focusField(field) {
        if (!field) {
            return
        }
        activeField = field
        field.forceActiveFocus()
    }

    function applyKey(key) {
        if (!activeField) {
            return
        }

        if (key === "SHIFT") {
            upperCase = !upperCase
            return
        }

        if (key === "BKSP") {
            if (activeField.selectionStart !== activeField.selectionEnd) {
                activeField.remove(activeField.selectionStart, activeField.selectionEnd)
            } else if (activeField.cursorPosition > 0) {
                activeField.remove(activeField.cursorPosition - 1, activeField.cursorPosition)
            }
            return
        }

        if (key === "CLEAR") {
            activeField.text = ""
            return
        }

        var value = key
        if (key === "SPACE") {
            value = " "
        } else if (key.length === 1 && key >= "a" && key <= "z" && upperCase) {
            value = key.toUpperCase()
        }

        activeField.insert(activeField.cursorPosition, value)
        activeField.forceActiveFocus()
    }

    function refreshNetworks() {
        if (!wifi || wifi.busy) {
            return
        }
        wifi.scanNetworks()
    }

    function selectNetwork(ssid) {
        selectedSsid = String(ssid || "")
    }

    function connectNow() {
        if (!wifi || !canProvision || wifi.busy) {
            return
        }
        wifi.connectToNetwork(selectedSsid.trim(), passInput.text, countryCode)
    }

    function skipWizard() {
        if (wifi) {
            wifi.dismissPrompt()
        }
    }

    onVisibleChanged: {
        if (visible && wifi) {
            showDetails = false
            activeField = null
            wifi.refreshStatus()
            wifi.scanNetworks()
        }
    }

    Connections {
        target: wifi

        function onNetworksChanged() {
            if (!wifi || wifi.networks.length === 0) {
                return
            }

            var keepCurrent = false
            for (var i = 0; i < wifi.networks.length; ++i) {
                if (wifi.networks[i].ssid === root.selectedSsid) {
                    keepCurrent = true
                    break
                }
            }
            if (!keepCurrent) {
                root.selectedSsid = wifi.networks[0].ssid
            }
        }

        function onConnectionChanged() {
            if (wifi && wifi.connected) {
                passInput.text = ""
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.modalMode ? "#B0000000" : "#00000000"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 44, 1240)
        height: Math.min(parent.height - 40, 680)
        radius: 22
        color: "#09131CEE"
        border.width: 1
        border.color: "#3A7A9F"
    }

    Column {
        anchors.fill: panel
        anchors.margins: 16
        spacing: 10

        Row {
            width: parent.width
            spacing: 10

            Text {
                text: "Set Up Wi-Fi"
                color: "#F4FBFF"
                font.pixelSize: 32
                font.family: theme ? theme.fontDisplay : "Sans Serif"
                font.weight: Font.DemiBold
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: 10
                height: 30
                width: Math.min(360, statusLabel.implicitWidth + 20)
                color: "#0E1E2B"
                border.width: 1
                border.color: wifi && wifi.networkState === "online" ? "#3D8E65" : "#456A7D"

                Text {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: {
                        if (!wifi) {
                            return "Wi-Fi unavailable"
                        }
                        if (wifi.setupMessageShort && wifi.setupMessageShort.length > 0) {
                            return wifi.setupMessageShort
                        }
                        return wifi.status
                    }
                    color: wifi && wifi.networkState === "online" ? "#83F3A8" : "#F2BE6C"
                    font.pixelSize: 14
                    font.family: theme ? theme.fontMono : "monospace"
                    font.bold: true
                }
            }
        }

        Text {
            width: parent.width
            text: {
                if (!wifi) {
                    return ""
                }
                if (!canProvision) {
                    return "Wi-Fi setup is disabled on this device image."
                }
                if (wifi.setupMessageDetail && wifi.setupMessageDetail.length > 0) {
                    return wifi.setupMessageDetail
                }
                return "Pick your hotspot, enter the password, then tap Connect."
            }
            color: "#A9C6D8"
            font.pixelSize: 16
            font.family: theme ? theme.fontMono : "monospace"
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            height: 244
            spacing: 12

            Rectangle {
                width: Math.floor((parent.width - 12) * 0.54)
                height: parent.height
                radius: 14
                color: "#071019"
                border.width: 1
                border.color: "#2E556E"

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Networks"
                            color: "#EAF5FB"
                            font.pixelSize: 20
                            font.family: theme ? theme.fontDisplay : "Sans Serif"
                        }

                        Item {
                            width: Math.max(0, parent.width - 250)
                            height: 1
                        }

                        Rectangle {
                            width: 110
                            height: 36
                            radius: 10
                            color: "#102230"
                            border.width: 1
                            border.color: "#3C6B85"

                            Text {
                                anchors.centerIn: parent
                                text: wifi && wifi.busy ? "..." : "REFRESH"
                                color: "#E9F6FF"
                                font.pixelSize: 14
                                font.family: theme ? theme.fontMono : "monospace"
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: wifi && !wifi.busy
                                onClicked: root.refreshNetworks()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: parent.height - 44
                        radius: 12
                        color: "#0A1823"
                        border.width: 1
                        border.color: "#27465B"
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: !wifi || wifi.networks.length === 0
                            text: wifi && wifi.busy ? "Scanning..." : "No networks yet. Tap Refresh."
                            color: "#9AB9CC"
                            font.pixelSize: 18
                            font.family: theme ? theme.fontDisplay : "Sans Serif"
                        }

                        ListView {
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            spacing: 6
                            model: wifi ? wifi.networks : []

                            delegate: Rectangle {
                                readonly property var rowData: modelData
                                readonly property bool selected: rowData.ssid === root.selectedSsid
                                width: ListView.view ? ListView.view.width : 0
                                height: 48
                                radius: 10
                                color: selected ? "#13384D" : "#0C202D"
                                border.width: 1
                                border.color: selected ? "#83D9FF" : "#2C5268"

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    Text {
                                        width: parent.width - 200
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rowData.ssid
                                        color: "#F3FAFF"
                                        font.pixelSize: 17
                                        font.family: theme ? theme.fontDisplay : "Sans Serif"
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: rowData.secure ? "LOCK" : "OPEN"
                                        color: rowData.secure ? "#F0C977" : "#8EE6AE"
                                        font.pixelSize: 12
                                        font.family: theme ? theme.fontMono : "monospace"
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Math.round(rowData.signalDbm) + " dBm"
                                        color: "#8AB3CA"
                                        font.pixelSize: 12
                                        font.family: theme ? theme.fontMono : "monospace"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.selectNetwork(rowData.ssid)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - (Math.floor((parent.width - 12) * 0.54))
                height: parent.height
                radius: 14
                color: "#071019"
                border.width: 1
                border.color: "#2E556E"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Text {
                        text: "Selected Network"
                        color: "#9AB9CC"
                        font.pixelSize: 13
                        font.family: theme ? theme.fontMono : "monospace"
                    }

                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: 10
                        color: "#0A1823"
                        border.width: 1
                        border.color: "#2C5268"

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: root.selectedSsid.length > 0 ? root.selectedSsid : "Tap a network on the left"
                            color: "#F5FBFF"
                            font.pixelSize: 17
                            font.family: theme ? theme.fontDisplay : "Sans Serif"
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: "Password"
                        color: "#9AB9CC"
                        font.pixelSize: 13
                        font.family: theme ? theme.fontMono : "monospace"
                    }

                    Rectangle {
                        width: parent.width
                        height: 50
                        radius: 12
                        color: "#0A1823"
                        border.width: 1
                        border.color: passInput.activeFocus ? "#7DD9FF" : "#2C5268"

                        TextInput {
                            id: passInput
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            color: "#F5FBFF"
                            font.pixelSize: 20
                            font.family: theme ? theme.fontDisplay : "Sans Serif"
                            echoMode: TextInput.Password
                            onActiveFocusChanged: if (activeFocus) root.activeField = passInput
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: "Enter Wi-Fi password"
                            visible: passInput.text.length === 0 && !passInput.activeFocus
                            color: "#7290A6"
                            font.pixelSize: 17
                            font.family: theme ? theme.fontDisplay : "Sans Serif"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.focusField(passInput)
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 42
                            radius: 12
                            color: wifi && !wifi.busy && root.selectedSsid.trim().length > 0 ? "#1A658F" : "#1A2A37"
                            border.width: 1
                            border.color: wifi && !wifi.busy && root.selectedSsid.trim().length > 0 ? "#8CE3FF" : "#405A6A"

                            Text {
                                anchors.centerIn: parent
                                text: wifi && wifi.busy ? "WORKING..." : "CONNECT"
                                color: "#F5FBFF"
                                font.pixelSize: 14
                                font.family: theme ? theme.fontMono : "monospace"
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.canProvision
                                    && wifi
                                    && !wifi.busy
                                    && root.selectedSsid.trim().length > 0
                                onClicked: root.connectNow()
                            }
                        }

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 42
                            radius: 12
                            color: "#0D1D28"
                            border.width: 1
                            border.color: "#3F6278"

                            Text {
                                anchors.centerIn: parent
                                text: "REFRESH"
                                color: "#ECF7FF"
                                font.pixelSize: 14
                                font.family: theme ? theme.fontMono : "monospace"
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: wifi && !wifi.busy
                                onClicked: root.refreshNetworks()
                            }
                        }

                        Rectangle {
                            width: (parent.width - 16) / 3
                            height: 42
                            radius: 12
                            color: "#0D1D28"
                            border.width: 1
                            border.color: "#3F6278"

                            Text {
                                anchors.centerIn: parent
                                text: "SKIP"
                                color: "#ECF7FF"
                                font.pixelSize: 14
                                font.family: theme ? theme.fontMono : "monospace"
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.skipWizard()
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 36
            radius: 10
            color: "#0A1823"
            border.width: 1
            border.color: "#30556D"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                text: showDetails ? "Hide Details" : "Details"
                color: "#D5E9F5"
                font.pixelSize: 14
                font.family: theme ? theme.fontMono : "monospace"
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.showDetails = !root.showDetails
            }
        }

        Rectangle {
            width: parent.width
            height: 64
            radius: 10
            color: "#071019"
            border.width: 1
            border.color: "#2E556E"
            visible: root.showDetails

            Text {
                anchors.fill: parent
                anchors.margins: 8
                text: {
                    if (!wifi) {
                        return ""
                    }
                    if (wifi.statusDetail && wifi.statusDetail.length > 0 && wifi.statusDetail !== wifi.status) {
                        return wifi.status + "\n" + wifi.statusDetail
                    }
                    return wifi.status
                }
                color: "#A6C9DC"
                font.pixelSize: 13
                font.family: theme ? theme.fontMono : "monospace"
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: parent.width
            height: 250
            radius: 14
            color: "#071019"
            border.width: 1
            border.color: "#2E556E"

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                Text {
                    text: "Keyboard"
                    color: "#EAF5FB"
                    font.pixelSize: 16
                    font.family: theme ? theme.fontDisplay : "Sans Serif"
                }

                Repeater {
                    model: root.keyboardRows

                    delegate: Row {
                        spacing: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        property var rowData: modelData

                        Repeater {
                            model: rowData

                            delegate: Rectangle {
                                readonly property string keyName: modelData
                                width: keyName === "SPACE" ? 300
                                     : (keyName === "SHIFT" || keyName === "BKSP" || keyName === "CLEAR" ? 104 : 56)
                                height: 34
                                radius: 10
                                color: keyName === "SHIFT" && root.upperCase ? "#2D7FA8" : "#102332"
                                border.width: 1
                                border.color: "#376683"

                                Text {
                                    anchors.centerIn: parent
                                    text: {
                                        if (parent.keyName === "BKSP") {
                                            return "BKSP"
                                        }
                                        if (parent.keyName.length === 1 &&
                                                parent.keyName >= "a" && parent.keyName <= "z" &&
                                                root.upperCase) {
                                            return parent.keyName.toUpperCase()
                                        }
                                        return parent.keyName
                                    }
                                    color: "#F6FBFF"
                                    font.pixelSize: 14
                                    font.family: theme ? theme.fontMono : "monospace"
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.applyKey(parent.keyName)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
