// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root
    Plasmoid.icon: "battery"
    Plasmoid.title: "Arche Battery Modes"
    toolTipMainText: "Arche Battery Modes"
    toolTipSubText: modeLabel()

    property string activeMode: "unknown"
    property bool switching: false
    property string info: ""

    function modeLabel() {
        switch (activeMode) {
        case "cockpit": return "Cockpit · 60–80 %";
        case "nomade": return "Nomade · 0–100 %";
        case "custom": return "Autres seuils";
        default: return "Mode inconnu";
        }
    }

    function refresh() {
        if (!switching) {
            reader.connectSource("/usr/local/sbin/arche-battery-mode mode")
        }
    }

    function changeMode(nextMode) {
        if (switching || (nextMode !== "cockpit" && nextMode !== "nomade")) return;
        switching = true;
        info = "Authentification en cours…";
        // Fixed command names and constant arguments: never interpolates user input.
        changer.connectSource("/usr/local/bin/arche-battery-switch " + nextMode)
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            let value = String(data["stdout"] || "").trim();
            if (value === "cockpit" || value === "nomade" || value === "custom") {
                root.activeMode = value;
            } else {
                root.activeMode = "unknown";
            }
            disconnectSource(source);
        }
    }

    P5Support.DataSource {
        id: changer
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            let code = Number(data["exit code"]);
            root.switching = false;
            root.info = code === 0 ? "Commande terminée" : "Changement non effectué";
            disconnectSource(source);
            root.refresh();
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()

    compactRepresentation: Kirigami.Icon {
        source: root.activeMode === "cockpit" ? "battery-080" : (root.activeMode === "nomade" ? "battery-100" : "battery")
        active: pointer.containsMouse
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 17
        Layout.preferredHeight: Kirigami.Units.gridUnit * 12
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            text: "Mode actuel : " + root.modeLabel()
            font.bold: true
            Layout.fillWidth: true
        }
        PC3.Button {
            text: "Cockpit · 60–80 %"
            icon.name: "battery-080"
            enabled: !root.switching
            Layout.fillWidth: true
            onClicked: root.changeMode("cockpit")
        }
        PC3.Button {
            text: "Nomade · 0–100 %"
            icon.name: "battery-100"
            enabled: !root.switching
            Layout.fillWidth: true
            onClicked: root.changeMode("nomade")
        }
        PC3.Label {
            text: root.info
            visible: text.length > 0
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        PC3.Button {
            text: "Actualiser"
            icon.name: "view-refresh"
            enabled: !root.switching
            onClicked: root.refresh()
        }
    }
}
