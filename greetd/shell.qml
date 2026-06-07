import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

Window {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property bool   showSidebar:  true
    property var    now:          new Date()
    property string session:      ""
    property string feedbackText: ""
    property bool   isError:      false

    visibility: Window.FullScreen
    flags:      Qt.FramelessWindowHint
    visible:    true
    color:      "#1e1e2e"

    // ── Helpers ───────────────────────────────────────────────────────────────
    function decodeMessage(rawMsg) {
        console.log("greetd message:", rawMsg);
        const msg = rawMsg.toLowerCase();

        if (msg.includes("incorrect") || msg.includes("failure") ||
            msg.includes("denied")    || msg.endsWith("auth_err"))
            return "Unrecognized credentials. The threshold remains closed.";

        if (msg.includes("timeout"))
            return "The invocation timed out.";

        if (msg.includes("finger") || msg.includes("fprint"))
            return "Awaiting biometric signature...";

        return `Raw: ${rawMsg}`;
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: manifestReader
        command: ["cat", "/etc/greetd/manifest.json"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const manifest = JSON.parse(this.text);
                    if (!manifest || !manifest.users) return;

                    userModel.clear();
                    manifest.users.forEach(user => {
                        userModel.append({ 
                            name: user.name, 
                            session: user.desktop || "hyprland" 
                        });
                    });
                } catch (e) {
                    console.error("Failed to parse manifest.json:", e);
                    root.feedbackText = "Manifest error: " + e.message;
                    root.isError = true;
                }
            }
        }
    }

    Process { id: shutdownProcess; command: ["systemctl", "poweroff"] }
    Process { id: rebootProcess;   command: ["systemctl", "reboot"]   }

    // ── Greetd connections ────────────────────────────────────────────────────
    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            console.log("onAuthMessage:", message, error, responseRequired, echoResponse);
            if (responseRequired) {
                Greetd.respond(passwordInput.text);
            } else {
                root.feedbackText = decodeMessage(message);
                root.isError      = error;
            }
            feedbackTimer.restart();
        }

        function onAuthFailure(message) {
            console.log("onAuthFailure:", message);
            root.feedbackText = decodeMessage(message);
            root.isError      = true;
            feedbackTimer.restart();
        }

        function onReadyToLaunch() {
            console.log("onReadyToLaunch");
            root.feedbackText = "";
            feedbackTimer.restart();
            Greetd.launch(["uwsm", "start", root.session]);
        }
    }

    // ── Timers ────────────────────────────────────────────────────────────────
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        id: feedbackTimer
        interval: 6000
        onTriggered: root.feedbackText = ""
    }

    Component.onCompleted: {
        manifestReader.running = true;
        passwordInput.forceActiveFocus();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────────────────────────────────

    // ── Wallpaper ─────────────────────────────────────────────────────────────
    Image {
        anchors.fill: parent
        source: "./assets/background.jpg"
        fillMode: Image.PreserveAspectCrop
    }

    // ── Clock (bottom-right) ──────────────────────────────────────────────────
    Column {
        anchors {
            bottom:  parent.bottom
            right:   parent.right
            margins: 50
        }
        spacing: 0

        Text {
            text:            Qt.formatTime(root.now, "hh:mm AP")
            color:           "#cdd6f4"
            font.pixelSize:  84
            font.bold:       true
            anchors.right:   parent.right
            style:           Text.Outline
            styleColor:      "#11111b"
        }

        Text {
            text:            Qt.formatDate(root.now, "dddd, MMMM d")
            color:           "#a6adc8"
            font.pixelSize:  28
            anchors.right:   parent.right
            style:           Text.Outline
            styleColor:      "#11111b"
        }
    }

    // ── Background click → toggle sidebar ─────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: root.showSidebar = !root.showSidebar
    }

    // ── Left sidebar ──────────────────────────────────────────────────────────
    Item {
        id: sidebar
        width:  400
        height: parent.height
        x:      root.showSidebar ? 0 : -width
        clip:   true

        Behavior on x {
            NumberAnimation { duration: 400; easing.type: Easing.OutExpo }
        }

        // Blurred wallpaper backdrop
        Item {
            width: root.width
            height: root.height
            x: -sidebar.x

            Image {
                id: blurSource
                anchors.fill: parent
                source: "./assets/background.jpg"
                fillMode: Image.PreserveAspectCrop
                visible: false
            }

            MultiEffect {
                source:      blurSource
                anchors.fill: blurSource
                blurEnabled: true
                blurMax:     64
                blur:        1.0
            }
        }

        // Frosted-glass tint
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.12, 0.12, 0.17, 0.65)
        }

        // Prevent clicks from falling through to the background MouseArea
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        // ── Login form ────────────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: 20

            Text {
                text:                     "The Threshold"
                color:                    "#cdd6f4"
                font.pixelSize:           32
                font.letterSpacing:       2
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // User selector
            Rectangle {
                width:                    300
                height:                   50
                color:                    "#313244"
                radius:                   5
                anchors.horizontalCenter: parent.horizontalCenter

                ListModel { id: userModel }

                ComboBox {
                    id: userSelector
                    anchors.fill: parent
                    model:        userModel
                    textRole:     "name"

                    onCountChanged: {
                        if (count > 0 && currentIndex === -1)
                            currentIndex = 0;
                    }

                    onActivated: {
                        passwordInput.forceActiveFocus();
                        root.feedbackText = "";
                    }

                    background: null

                    contentItem: Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; margins: 10 }
                        text:                userSelector.currentText
                        color:               "#cdd6f4"
                        font.pixelSize:      20
                        verticalAlignment:   Text.AlignVCenter
                    }

                    indicator: Button {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 15 }
                        width: 20; height: 20
                        icon.source: userSelector.popup.visible
                            ? "./assets/icons/chevron-up.svg"
                            : "./assets/icons/chevron-down.svg"
                        icon.color:  userSelector.popup.visible ? "#cdd6f4" : "#6c7086"
                        icon.width:  width
                        icon.height: height
                        background:  null
                        padding:     0
                        enabled:     false
                    }

                    popup: Popup {
                        y:       userSelector.height + 5
                        width:   userSelector.width
                        padding: 5

                        background: Rectangle {
                            color:        "#1e1e2e"
                            radius:       5
                            border.color: "#313244"
                        }

                        contentItem: ListView {
                            clip:           true
                            implicitHeight: contentHeight
                            model:          userSelector.popup.visible ? userSelector.delegateModel : null
                        }
                    }

                    delegate: ItemDelegate {
                        id: delegateItem
                        width:        userSelector.width - 10
                        height:       40
                        hoverEnabled: true
                        highlighted:  userSelector.highlightedIndex === index

                        contentItem: Text {
                            text:              model.name
                            color:             (delegateItem.hovered || delegateItem.highlighted) ? "#11111b" : "#cdd6f4"
                            font.pixelSize:    20
                            verticalAlignment: Text.AlignVCenter
                            leftPadding:       10
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        background: Rectangle {
                            radius: 3
                            color:  (delegateItem.hovered || delegateItem.highlighted) ? "#89b4fa" : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }
            }

            // Password field
            Rectangle {
                width:                    300
                height:                   50
                color:                    "#313244"
                radius:                   5
                anchors.horizontalCenter: parent.horizontalCenter

                TextInput {
                    id: passwordInput
                    anchors {
                        left: parent.left; top: parent.top
                        bottom: parent.bottom; right: showPasswordBtn.left
                        margins: 10
                    }
                    echoMode:          TextInput.Password
                    color:             "#cdd6f4"
                    font.pixelSize:    20
                    verticalAlignment: TextInput.AlignVCenter
                    clip:              true

                    onAccepted: {
                        root.feedbackText = "";
                        const user    = userModel.get(userSelector.currentIndex);
                        root.session  = user.session;
                        Greetd.createSession(user.name);
                    }

                    onTextChanged: root.feedbackText = ""
                }

                Button {
                    id: showPasswordBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 15 }
                    width: 20; height: 24
                    icon.source: pressed
                        ? "./assets/icons/eye.svg"
                        : "./assets/icons/eye-closed.svg"
                    icon.color:  pressed ? "#cdd6f4" : "#6c7086"
                    icon.width:  width
                    icon.height: height
                    background:  null
                    padding:     0

                    onPressed:  passwordInput.echoMode = TextInput.Normal
                    onReleased: passwordInput.echoMode = TextInput.Password
                    onCanceled: passwordInput.echoMode = TextInput.Password

                    MouseArea {
                        anchors.fill:    parent
                        cursorShape:     Qt.PointingHandCursor
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            // Awaken button
            Rectangle {
                id: awakenButton
                width:                    300
                height:                   50
                radius:                   5
                anchors.horizontalCenter: parent.horizontalCenter
                color: awakenMouseArea.containsMouse ? Qt.lighter("#89b4fa", 1.05) : "#89b4fa"
                Behavior on color { ColorAnimation { duration: 150 } }

                Canvas {
                    id: rippleCanvas
                    anchors.fill: parent

                    property real rippleX:       0
                    property real rippleY:       0
                    property real rippleRadius:  0
                    property real rippleOpacity: 0

                    onRippleRadiusChanged:  requestPaint()
                    onRippleOpacityChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.beginPath();
                        ctx.roundedRect(0, 0, width, height, awakenButton.radius, awakenButton.radius);
                        ctx.clip();
                        ctx.beginPath();
                        ctx.fillStyle = Qt.rgba(180/255, 190/255, 254/255, rippleOpacity);
                        ctx.arc(rippleX, rippleY, rippleRadius, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text:             "AWAKEN"
                    color:            "#11111b"
                    font.pixelSize:   18
                    font.bold:        true
                    font.letterSpacing: 4
                }

                MouseArea {
                    id: awakenMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor

                    onPressed: (mouse) => {
                        rippleCanvas.rippleX = mouse.x;
                        rippleCanvas.rippleY = mouse.y;
                        rippleAnim.restart();
                    }

                    onClicked: {
                        root.feedbackText = "";
                        const user = userModel.get(userSelector.currentIndex);
                        Greetd.createSession(user.name);
                        Greetd.respond(passwordInput.text);
                        Greetd.launch(["uwsm", "start", user.session]);
                    }
                }

                ParallelAnimation {
                    id: rippleAnim
                    NumberAnimation {
                        target: rippleCanvas; property: "rippleRadius"
                        from: 0; to: 350; duration: 500; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: rippleCanvas; property: "rippleOpacity"
                        from: 0.8; to: 0.0; duration: 500; easing.type: Easing.OutQuad
                    }
                }
            }

            // Feedback card
            Rectangle {
                id: feedbackCard
                width:                    300
                height:                   Math.max(40, feedbackLabel.implicitHeight + 20)
                radius:                   5
                anchors.horizontalCenter: parent.horizontalCenter
                color:                    "#181825"
                border.color: root.isError
                    ? Qt.rgba(0.95, 0.54, 0.65, 0.5)
                    : Qt.rgba(0.53, 0.70, 0.98, 0.5)
                border.width: 1
                opacity:      root.feedbackText !== "" ? 1.0 : 0.0

                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

                Text {
                    id: feedbackLabel
                    anchors.centerIn:   parent
                    width:              parent.width - 30
                    text:               root.feedbackText
                    color:              root.isError ? "#f38ba8" : "#89b4fa"
                    font.pixelSize:     14
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode:           Text.WordWrap
                }

                onOpacityChanged: {
                    if (opacity === 1.0 && root.isError)
                        shakeAnim.start();
                }

                SequentialAnimation on x {
                    id: shakeAnim
                    running: false
                    NumberAnimation { from: feedbackCard.width/2 - 150; to: feedbackCard.width/2 - 140; duration: 40; easing.type: Easing.OutQuad   }
                    NumberAnimation { from: feedbackCard.width/2 - 140; to: feedbackCard.width/2 - 160; duration: 40; easing.type: Easing.InOutQuad  }
                    NumberAnimation { from: feedbackCard.width/2 - 160; to: feedbackCard.width/2 - 150; duration: 40; easing.type: Easing.InQuad     }
                }
            }
        }

        // ── System buttons (bottom of sidebar) ───────────────────────────────
        Row {
            anchors {
                bottom:           parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin:     30
            }
            spacing: 30

            Button {
                id: rebootBtn
                text:             "Reboot"
                icon.source:      "./assets/icons/rotate-ccw.svg"
                icon.color:       "#a6adc8"
                icon.width:       18
                icon.height:      18
                background:       null
                padding:          0
                spacing:          8
                palette.buttonText: icon.color
                font.pixelSize:   16
                onClicked:        rebootProcess.running = true

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.NoButton
                }

                Rectangle {
                    anchors { bottom: parent.bottom; bottomMargin: -4 }
                    width:  parent.hovered ? parent.width : 0
                    height: 2; radius: 2
                    color:  parent.icon.color
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            Button {
                id: powerOffBtn
                text:             "Power Off"
                hoverEnabled:     true
                icon.source:      "./assets/icons/power.svg"
                icon.color:       "#f38ba8"
                icon.width:       18
                icon.height:      18
                background:       null
                padding:          0
                spacing:          8
                palette.buttonText: icon.color
                font.pixelSize:   16
                onClicked:        shutdownProcess.running = true

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.NoButton
                }

                Rectangle {
                    anchors { bottom: parent.bottom; bottomMargin: -4 }
                    width:  parent.hovered ? parent.width : 0
                    height: 2; radius: 2
                    color:  parent.icon.color
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
