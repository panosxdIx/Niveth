import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide()
    }

    Timer {
        id: advanceTimer
        interval: 3500
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        centeredText: qsTr("Welcome to Niveth Linux 0.1")
    }

    Slide {
        centeredText: qsTr("A calm and simple Linux experience")
    }

    Slide {
        centeredText: qsTr("Niveth Linux — Powered by free and open-source software")
    }

    function onActivate() {
        presentation.currentSlide = 0
    }

    function onLeave() {
    }
}
