import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "orviwan.vibesWorldTime"
  ipcTarget: "orviwan.vibesWorldTime"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ── Today & Calendar Navigation ───────────────────────────────────────────
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string currentMonthYearTitle: labelLocale.monthName(root.viewMonth, Locale.LongFormat) + " " + root.viewYear

  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accentColor: Color.accent
  readonly property color mutedColor: Color.muted

  function stepMonth(delta) {
    var target = Model.stepMonth(root.viewYear, root.viewMonth, delta)
    root.viewYear = target.year
    root.viewMonth = target.month
  }

  function goToToday() {
    root.today = new Date()
    root.viewYear = root.today.getFullYear()
    root.viewMonth = root.today.getMonth()
  }

  // ── World Clocks State ───────────────────────────────────────────────────
  property var worldClocks: []
  property bool timeFormat24h: true
  property bool showWeekNumbers: false
  property bool editMode: false
  property bool searchMode: false
  property var searchResults: []

  readonly property string helperScriptPath: Qt.resolvedUrl("worldtime.py").toString().replace("file://", "")

  function refresh() {
    goToToday()
    refreshClocks()
  }

  function refreshClocks() {
    clockProc.command = ["python3", root.helperScriptPath, "get"]
    clockProc.running = true
  }

  function toggleTimeFormat() {
    actionProc.command = ["python3", root.helperScriptPath, "toggle_format"]
    actionProc.running = true
  }

  function toggleWeekNumbers() {
    actionProc.command = ["python3", root.helperScriptPath, "toggle_weeks"]
    actionProc.running = true
  }

  function deleteCity(name) {
    actionProc.command = ["python3", root.helperScriptPath, "delete", name]
    actionProc.running = true
  }

  function addCity(name, tz) {
    actionProc.command = ["python3", root.helperScriptPath, "add", name, tz]
    actionProc.running = true
    root.searchMode = false
    root.searchResults = []
  }

  function searchCity(query) {
    if (!query || query.trim() === "") {
      root.searchResults = []
      return
    }
    searchProc.command = ["python3", root.helperScriptPath, "search", query.trim()]
    searchProc.running = true
  }

  // ── Processes ─────────────────────────────────────────────────────────────
  Process {
    id: clockProc
    command: ["python3", root.helperScriptPath, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text.trim())
          if (data) {
            root.worldClocks = data.clocks || []
            root.timeFormat24h = data.timeFormat24h !== false
            root.showWeekNumbers = data.showWeekNumbers === true
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text.trim())
          if (data) {
            root.worldClocks = data.clocks || []
            root.timeFormat24h = data.timeFormat24h !== false
            root.showWeekNumbers = data.showWeekNumbers === true
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.searchResults = JSON.parse(text.trim()) || []
        } catch (e) {
          root.searchResults = []
        }
      }
    }
  }

  Timer {
    id: searchDebounce
    interval: 200
    repeat: false
    onTriggered: root.searchCity(searchField.text)
  }

  Timer {
    id: updateTimer
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.refreshClocks()
  }

  SystemClock {
    id: sysClock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.today = sysClock.date
      root.refreshClocks()
    }
  }

  // ── Panel Open / Close ────────────────────────────────────────────────────
  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.editMode = false
    root.searchMode = false
    root.searchResults = []
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ── Popup UI ──────────────────────────────────────────────────────────────
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(mainContent.implicitHeight + Style.space(24))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: mainContent.width
        contentHeight: mainContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: mainContent
          width: scrollArea.width
          spacing: Style.space(12)
          padding: Style.space(14)

          // ── 1. Calendar Header (e.g. "September 2026 <>") ─────────────────
          RowLayout {
            width: parent.width

            Text {
              text: root.currentMonthYearTitle
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body * 1.25
              font.bold: true
              color: root.contentForeground
              Layout.fillWidth: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToToday()
              }
            }

            Row {
              spacing: Style.space(4)
              Layout.alignment: Qt.AlignRight

              Button {
                text: "‹"
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(2)
                onClicked: root.stepMonth(-1)
              }

              Button {
                text: "›"
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(2)
                onClicked: root.stepMonth(1)
              }
            }
          }

          // ── 2. Month Calendar Grid ────────────────────────────────────────
          Column {
            width: parent.width
            spacing: Style.space(4)

            // Weekday headings
            Row {
              width: parent.width
              spacing: Style.space(2)

              // Optional week number column header
              Item {
                visible: root.showWeekNumbers
                width: Style.space(28)
                height: Style.space(20)
                Text {
                  anchors.centerIn: parent
                  text: "W"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption || 11
                  font.bold: true
                  color: root.mutedColor
                }
              }

              Repeater {
                model: root.weekdays
                Item {
                  required property int modelData
                  width: (parent.width - (root.showWeekNumbers ? Style.space(28) : 0) - Style.space(12)) / 7
                  height: Style.space(20)

                  Text {
                    anchors.centerIn: parent
                    text: root.labelLocale.dayName(modelData, Locale.ShortFormat).substring(0, 2).toUpperCase()
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption || 11
                    font.bold: true
                    color: root.mutedColor
                  }
                }
              }
            }

            // 6 Week rows
            Repeater {
              model: root.weeks

              Row {
                id: weekRow
                required property var modelData
                width: parent.width
                spacing: Style.space(2)

                // Optional week number column
                Item {
                  visible: root.showWeekNumbers
                  width: Style.space(28)
                  height: Style.space(28)
                  Text {
                    anchors.centerIn: parent
                    text: weekRow.modelData.week
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption || 10
                    color: root.mutedColor
                    opacity: 0.7
                  }
                }

                // 7 Day cells
                Repeater {
                  model: weekRow.modelData.days

                  Rectangle {
                    id: dayCell
                    required property var modelData
                    width: (weekRow.width - (root.showWeekNumbers ? Style.space(28) : 0) - Style.space(12)) / 7
                    height: Style.space(28)
                    radius: Style.cornerRadius
                    color: modelData.today ? root.accentColor : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: modelData.day
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body || 13
                      font.bold: modelData.today
                      color: modelData.today 
                        ? Color.background 
                        : (modelData.inMonth ? root.contentForeground : root.mutedColor)
                      opacity: modelData.inMonth || modelData.today ? 1.0 : 0.4
                    }
                  }
                }
              }
            }
          }

          // ── Separator ─────────────────────────────────────────────────────
          PanelSeparator {
            width: parent.width
          }

          // ── 3. World Clocks Section ───────────────────────────────────────
          RowLayout {
            width: parent.width

            Text {
              text: "WORLD CLOCKS"
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption || 11
              font.bold: true
              color: root.mutedColor
              Layout.fillWidth: true
            }

            Text {
              text: root.worldClocks.length + (root.worldClocks.length === 1 ? " location" : " locations")
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption || 11
              color: root.mutedColor
              opacity: 0.8
            }
          }

          // World Clocks List
          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.worldClocks

              Rectangle {
                id: clockRow
                required property var modelData
                width: parent.width
                implicitHeight: Style.space(52)
                radius: Style.cornerRadius
                color: clockHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                border.width: 1
                border.color: clockHover.containsMouse ? root.accentColor : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)

                MouseArea {
                  id: clockHover
                  anchors.fill: parent
                  hoverEnabled: true
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)

                  // Delete button (when edit mode active)
                  Button {
                    visible: root.editMode
                    text: "✕"
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(2)
                    onClicked: root.deleteCity(clockRow.modelData.name)
                  }

                  // Left Column: Location name + Today
                  ColumnLayout {
                    spacing: Style.space(2)
                    Layout.fillWidth: true

                    Text {
                      text: clockRow.modelData.name
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body || 13
                      font.bold: true
                      color: root.contentForeground
                    }

                    Text {
                      text: clockRow.modelData.day
                      font.family: root.contentFontFamily
                      font.pixelSize: (Style.font.body || 13) * 0.85
                      color: root.mutedColor
                    }
                  }

                  // Right Column: Big Time + relative offset
                  ColumnLayout {
                    spacing: Style.space(2)
                    Layout.alignment: Qt.AlignRight

                    Text {
                      text: clockRow.modelData.time
                      font.family: root.contentFontFamily
                      font.pixelSize: (Style.font.title || 16) * 1.3
                      font.bold: true
                      color: root.contentForeground
                      horizontalAlignment: Text.AlignRight
                      Layout.alignment: Qt.AlignRight
                    }

                    Text {
                      text: clockRow.modelData.offset
                      font.family: root.contentFontFamily
                      font.pixelSize: (Style.font.body || 13) * 0.85
                      color: clockRow.modelData.offset === "Same time" ? root.mutedColor : root.accentColor
                      horizontalAlignment: Text.AlignRight
                      Layout.alignment: Qt.AlignRight
                    }
                  }
                }
              }
            }
          }

          // ── Search / Add Location Box (collapsible) ────────────────────────
          Column {
            visible: root.searchMode
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search city (e.g. Sydney, Paris, Cairo)..."
              onTextChanged: searchDebounce.restart()
            }

            // Search Results list
            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.searchResults

                Rectangle {
                  id: resultItem
                  required property var modelData
                  width: parent.width
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: resultHover.containsMouse ? root.accentColor : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)

                  MouseArea {
                    id: resultHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addCity(resultItem.modelData.name, resultItem.modelData.tz)
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: resultItem.modelData.display
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body || 13
                    color: resultHover.containsMouse ? Color.background : root.contentForeground
                  }
                }
              }
            }
          }

          // ── Management / Settings Toolbar ─────────────────────────────────
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: root.searchMode ? "Cancel" : "+ Add City"
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: {
                root.searchMode = !root.searchMode
                if (root.searchMode) {
                  searchField.text = ""
                  searchField.forceActiveFocus()
                } else {
                  root.searchResults = []
                }
              }
            }

            Button {
              text: root.editMode ? "Done" : "Manage"
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.editMode = !root.editMode
            }

            Item { Layout.fillWidth: true }

            Button {
              text: root.timeFormat24h ? "12h" : "24h"
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.toggleTimeFormat()
            }

            Button {
              text: root.showWeekNumbers ? "Wk On" : "Wk Off"
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.toggleWeekNumbers()
            }
          }
        }
      }
    }
  }
}
