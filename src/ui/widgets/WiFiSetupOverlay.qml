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
    property bool manuallyOpened: false
    property bool networkPickerOpen: false
    property string fallbackNetworkSsid: ""
    property string fallbackNetworkSignal: ""
    property string fallbackNetworkSecurity: "Secure"
    readonly property bool canProvision: !!wifi && wifi.onboardingEnabled
    readonly property bool modalMode: !!wifi && wifi.setupRequired
    readonly property bool hasSelection: String(selectedSsid || "").trim().length > 0
    readonly property bool canSubmit: canProvision && !!wifi && !wifi.busy && hasSelection && passInput.text.length >= 8
    readonly property bool keyboardVisible: activeField === passInput || passInput.text.length > 0
    readonly property string primaryNetworkSsid: primaryNetworkValue("ssid")
    readonly property string primaryNetworkSignal: primaryNetworkValue("signal")
    readonly property string primaryNetworkSecurity: primaryNetworkValue("security")
    readonly property var keyboardRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["SHIFT", "z", "x", "c", "v", "b", "n", "m", "BKSP"],
        ["SPACE", ".", "-", "_", "@", "!", "/", "ENTER"]
    ]

    anchors.fill: parent
    z: 9500
    visible: !!wifi && (manuallyOpened || (wifi.promptVisible && String(wifi.networkState || "") === "no_config"))

    function focusField(field) {
        if (!field) {
            return
        }
        activeField = field
        field.forceActiveFocus()
    }

    function applyKey(key) {
        if (key === "ENTER") {
            connectNow()
            return
        }

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

    function openNetworkPicker() {
        networkPickerOpen = true
        activeField = null
        if (wifi && !wifi.busy) {
            wifi.scanNetworks()
        }
    }

    function showNetworkPickerWithFallback(ssid, signal, security) {
        fallbackNetworkSsid = String(ssid || "")
        fallbackNetworkSignal = String(signal || "")
        fallbackNetworkSecurity = String(security || "Secure")
        openNetworkPicker()
    }

    function primaryNetworkValue(field) {
        var row = null
        if (wifi && wifi.networks && typeof wifi.networks.length === "number" && wifi.networks.length > 0) {
            row = wifi.networks[0]
        }

        if (field === "ssid") {
            if (fallbackNetworkSsid.length > 0) {
                return fallbackNetworkSsid
            }
            if (wifi && wifi.currentSsid) {
                return String(wifi.currentSsid)
            }
            if (row && row.ssid) {
                return String(row.ssid)
            }
            return ""
        }

        if (field === "signal") {
            if (fallbackNetworkSignal.length > 0) {
                return fallbackNetworkSignal
            }
            if (wifi && Number(wifi.signalDbm) > -998) {
                return Math.round(Number(wifi.signalDbm)) + " dBm"
            }
            if (row && Number(row.signalDbm) > -998) {
                return Math.round(Number(row.signalDbm)) + " dBm"
            }
            return ""
        }

        if (fallbackNetworkSecurity.length > 0) {
            return fallbackNetworkSecurity
        }
        if (row && row.secure === false) {
            return "Open"
        }
        return "Secure"
    }

    function selectNetwork(ssid) {
        selectedSsid = String(ssid || "").trim()
        if (selectedSsid.length === 0) {
            return
        }
        networkPickerOpen = false
        passInput.forceActiveFocus()
        activeField = passInput
    }

    function connectNow() {
        if (!wifi || !canSubmit) {
            return
        }
        wifi.connectToNetwork(String(selectedSsid || "").trim(), passInput.text, countryCode)
    }

    function openPrompt() {
        manuallyOpened = true
        if (wifi) {
            wifi.showPrompt()
        }
    }

    function skipWizard() {
        manuallyOpened = false
        if (wifi) {
            wifi.dismissPrompt()
        }
    }

    onVisibleChanged: {
        if (visible && wifi) {
            activeField = null
            networkPickerOpen = false
            selectedSsid = wifi.currentSsid ? String(wifi.currentSsid) : selectedSsid
            wifi.refreshStatus()
            wifi.scanNetworks()
        } else if (!visible) {
            manuallyOpened = false
            networkPickerOpen = false
            fallbackNetworkSsid = ""
            fallbackNetworkSignal = ""
            fallbackNetworkSecurity = "Secure"
        }
    }

    Connections {
        target: wifi

        function onNetworksChanged() {
            if (!wifi || !wifi.networks) {
                return
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
        color: root.modalMode ? "#C0020509" : "#94020509"
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 360, 760)
        height: Math.min(parent.height - 64, root.keyboardVisible ? 568 : (root.networkPickerOpen ? 500 : 408))
        radius: 14
        color: "#0B1118"
        border.width: 1
        border.color: "#31404A"

        Behavior on height {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
        }
    }

    Column {
        anchors.fill: panel
        anchors.margins: 28
        spacing: 18

        Row {
            width: parent.width
            height: 54
            spacing: 14

            Column {
                width: parent.width - closeButton.width - 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    text: "Wi-Fi"
                    color: "#F6FAFC"
                    font.pixelSize: 31
                    font.family: theme ? theme.fontDisplay : "Sans Serif"
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: root.networkPickerOpen ? "Select an available network." : "Choose a network and connect."
                    color: "#94AAB5"
                    font.pixelSize: 15
                    font.family: theme ? theme.fontDisplay : "Sans Serif"
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: closeButton
                width: 82
                height: 38
                anchors.verticalCenter: parent.verticalCenter
                radius: 8
                color: closeArea.pressed ? "#182530" : "#111A22"
                border.width: 1
                border.color: "#334855"

                Text {
                    anchors.centerIn: parent
                    text: "Close"
                    color: "#D8E6EC"
                    font.pixelSize: 14
                    font.family: theme ? theme.fontMono : "monospace"
                    font.bold: true
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    onClicked: root.skipWizard()
                }
            }
        }

        Column {
            width: parent.width
            spacing: 12

            Text {
                text: "Network"
                color: "#91A4AE"
                font.pixelSize: 13
                font.family: theme ? theme.fontMono : "monospace"
            }

            Rectangle {
                id: networkField
                width: parent.width
                height: 52
                radius: 9
                color: "#0F171F"
                border.width: 1
                border.color: root.networkPickerOpen ? "#80C7E8" : "#2A3C48"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: pickerChevron.width + 24
                    verticalAlignment: Text.AlignVCenter
                    text: root.hasSelection ? root.selectedSsid : "Select network"
                    color: root.hasSelection ? "#F6FAFC" : "#647984"
                    font.pixelSize: 20
                    font.family: theme ? theme.fontDisplay : "Sans Serif"
                    elide: Text.ElideRight
                }

                Text {
                    id: pickerChevron
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.networkPickerOpen ? "^" : "v"
                    color: "#8AA3B0"
                    font.pixelSize: 18
                    font.family: theme ? theme.fontMono : "monospace"
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.openNetworkPicker()
                }
            }

            Rectangle {
                width: parent.width
                height: root.networkPickerOpen ? 64 : 0
                visible: height > 1
                radius: 9
                color: "#0F171F"
                border.width: 1
                border.color: "#314655"

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    Item {
                        width: parent.width
                        height: 48
                        visible: root.primaryNetworkSsid.length > 0

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: networkSecurity.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.primaryNetworkSsid
                            color: "#F1F7FA"
                            font.pixelSize: 17
                            font.family: "Sans Serif"
                            elide: Text.ElideRight
                        }

                        Text {
                            id: networkSignal
                            width: 74
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: root.primaryNetworkSignal
                            color: "#78909C"
                            font.pixelSize: 12
                            font.family: theme ? theme.fontMono : "monospace"
                        }

                        Text {
                            id: networkSecurity
                            width: 62
                            anchors.right: networkSignal.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: root.primaryNetworkSecurity
                            color: root.primaryNetworkSecurity === "Open" ? "#82C99B" : "#A8BAC4"
                            font.pixelSize: 12
                            font.family: theme ? theme.fontMono : "monospace"
                        }

                        MouseArea {
                            id: networkRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.selectNetwork(root.primaryNetworkSsid)
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.primaryNetworkSsid.length === 0
                        text: wifi && wifi.busy ? "Scanning..." : "No networks found"
                        color: "#78909C"
                        font.pixelSize: 15
                        font.family: theme ? theme.fontDisplay : "Sans Serif"
                    }
                }
            }

            Text {
                text: "Password"
                color: "#91A4AE"
                font.pixelSize: 13
                font.family: theme ? theme.fontMono : "monospace"
            }

            Rectangle {
                width: parent.width
                height: 52
                radius: 9
                color: "#0F171F"
                border.width: 1
                border.color: passInput.activeFocus ? "#80C7E8" : "#2A3C48"

                TextInput {
                    id: passInput
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    color: "#F6FAFC"
                    selectedTextColor: "#081017"
                    selectionColor: "#80C7E8"
                    font.pixelSize: 20
                    font.family: theme ? theme.fontDisplay : "Sans Serif"
                    echoMode: TextInput.Password
                    onActiveFocusChanged: if (activeFocus) root.activeField = passInput
                    Keys.onReturnPressed: root.connectNow()
                    Keys.onEnterPressed: root.connectNow()
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    text: "Password"
                    visible: passInput.text.length === 0 && !passInput.activeFocus
                    color: "#647984"
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
                height: 46
                spacing: 10

                Rectangle {
                    width: Math.floor((parent.width - 20) * 0.54)
                    height: parent.height
                    radius: 9
                    color: root.canSubmit ? (connectArea.pressed ? "#227BA4" : "#1A688C") : "#17232C"
                    border.width: 1
                    border.color: root.canSubmit ? "#79C9E8" : "#2F414C"

                    Text {
                        anchors.centerIn: parent
                        text: wifi && wifi.busy ? "Working..." : "Connect"
                        color: root.canSubmit ? "#F8FCFD" : "#667A84"
                        font.pixelSize: 15
                        font.family: theme ? theme.fontMono : "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        id: connectArea
                        anchors.fill: parent
                        enabled: root.canSubmit
                        onClicked: root.connectNow()
                    }
                }

                Rectangle {
                    width: Math.floor((parent.width - 20) * 0.23)
                    height: parent.height
                    radius: 9
                    color: scanArea.pressed ? "#182936" : "#101B24"
                    border.width: 1
                    border.color: "#365365"

                    Text {
                        anchors.centerIn: parent
                        text: wifi && wifi.busy ? "..." : "Scan"
                        color: "#D8E8EF"
                        font.pixelSize: 15
                        font.family: theme ? theme.fontMono : "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        id: scanArea
                        anchors.fill: parent
                        enabled: wifi && !wifi.busy
                        onClicked: root.refreshNetworks()
                    }
                }

                Rectangle {
                    width: parent.width - Math.floor((parent.width - 20) * 0.54)
                        - Math.floor((parent.width - 20) * 0.23)
                        - 20
                    height: parent.height
                    radius: 9
                    color: skipArea.pressed ? "#182530" : "#111A22"
                    border.width: 1
                    border.color: "#334855"

                    Text {
                        anchors.centerIn: parent
                        text: "Skip"
                        color: "#D8E6EC"
                        font.pixelSize: 15
                        font.family: theme ? theme.fontMono : "monospace"
                        font.bold: true
                    }

                    MouseArea {
                        id: skipArea
                        anchors.fill: parent
                        onClicked: root.skipWizard()
                    }
                }
            }

            Text {
                width: parent.width
                text: {
                    if (!wifi) {
                        return ""
                    }
                    if (wifi.currentSsid && wifi.ipv4Address) {
                        return "Current: " + wifi.currentSsid + "  " + String(wifi.ipv4Address).split("/")[0]
                    }
                    if (wifi.currentSsid) {
                        return "Current: " + wifi.currentSsid
                    }
                    return ""
                }
                visible: text.length > 0
                color: "#78909C"
                font.pixelSize: 13
                font.family: theme ? theme.fontMono : "monospace"
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: parent.width
            height: root.keyboardVisible ? 174 : 0
            visible: height > 1
            radius: 12
            color: "#0D151D"
            border.width: 1
            border.color: "#263844"

            Column {
                anchors.centerIn: parent
                spacing: 7

                Repeater {
                    model: root.keyboardRows

                    delegate: Row {
                        spacing: 7
                        anchors.horizontalCenter: parent.horizontalCenter
                        property var rowData: modelData

                        Repeater {
                            model: rowData

                            delegate: Rectangle {
                                readonly property string keyName: modelData
                                readonly property bool submitKey: keyName === "ENTER"
                                width: keyName === "SPACE" ? 250
                                     : (keyName === "SHIFT" || keyName === "BKSP" || keyName === "ENTER" ? 84 : 48)
                                height: 25
                                radius: 7
                                color: submitKey && root.canSubmit ? "#1A688C"
                                     : (keyName === "SHIFT" && root.upperCase ? "#216486" : "#111F2A")
                                border.width: 1
                                border.color: submitKey && root.canSubmit ? "#79C9E8" : "#355365"

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
                                    color: parent.submitKey && !root.canSubmit ? "#7C8F98" : "#E9F3F7"
                                    font.pixelSize: 13
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
