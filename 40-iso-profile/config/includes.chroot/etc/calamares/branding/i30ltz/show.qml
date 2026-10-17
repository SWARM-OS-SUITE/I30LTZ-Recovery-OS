// I30LTZ Recovery OS installer slideshow | v0.3.0-alpha | 2026-10-05
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation
    Timer { interval: 5000; running: true; repeat: true; onTriggered: presentation.goToNextSlide() }

    Slide {
        Rectangle { anchors.fill: parent; color: "#0a0a0f" }
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: "#ba0c2f"; font.pixelSize: 32
            text: "I30LTZ RECOVERY OS\nInstalling - Mad Dr. Boltz is standing by"
        }
    }
    Slide {
        Rectangle { anchors.fill: parent; color: "#0a0a0f" }
        Text {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            color: "#ffffff"; font.pixelSize: 24
            text: "Local AI. No cloud.\nEvery destructive action needs your approval."
        }
    }
}
