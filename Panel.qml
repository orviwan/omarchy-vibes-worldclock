import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "orviwan.vibesworldtime"
  ipcTarget: "orviwan.vibesworldtime"
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

  // First day of week based on user setting
  readonly property int weekStart: root.firstDayOfWeek === "sunday" ? 0 : 1
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
  property string firstDayOfWeek: "monday"
  property bool showSunriseSunset: true

  property bool settingsMode: false
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

  function setSetting(key, val) {
    actionProc.command = ["python3", root.helperScriptPath, "set_setting", key, String(val)]
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

  function resetDefaults() {
    actionProc.command = ["python3", root.helperScriptPath, "reset_defaults"]
    actionProc.running = true
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
            root.firstDayOfWeek = data.firstDayOfWeek || "monday"
            root.showSunriseSunset = data.showSunriseSunset !== false
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
            root.firstDayOfWeek = data.firstDayOfWeek || "monday"
            root.showSunriseSunset = data.showSunriseSunset !== false
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
    interval: 150
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
    root.settingsMode = false
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(mainContent.implicitHeight + Style.space(16))

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
          spacing: Style.space(8)

          // ═══════════════════════════════════════════════════════════════════
          // VIEW A: SETTINGS PAGE
          // ═══════════════════════════════════════════════════════════════════
          Column {
            visible: root.settingsMode
            width: parent.width
            spacing: Style.space(10)

            // Settings Header with Back button
            RowLayout {
              width: parent.width

              Button {
                text: "← Back"
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                onClicked: {
                  root.settingsMode = false
                  root.searchMode = false
                }
              }

              Text {
                text: "Settings"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body * 1.15
                font.bold: true
                color: root.contentForeground
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
              }

              Item { width: Style.space(50) }
            }

            PanelSeparator { width: parent.width }

            // ── Section 1: Manage Locations ──────────────────────────────────
            RowLayout {
              width: parent.width

              Text {
                text: "LOCATIONS (" + root.worldClocks.length + ")"
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption || 11
                font.bold: true
                color: root.mutedColor
                Layout.fillWidth: true
              }

              Button {
                text: root.searchMode ? "Cancel" : "+ Add City"
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(2)
                onClicked: {
                  root.searchMode = !root.searchMode
                  if (root.searchMode) {
                    searchField.text = ""
                    searchField.forceActiveFocus()
                  }
                }
              }
            }

            // Search box inside settings
            Column {
              visible: root.searchMode
              width: parent.width
              spacing: Style.space(4)

              TextField {
                id: searchField
                width: parent.width
                placeholderText: "Type city (e.g. Sydney, Berlin, Cairo)..."
                onTextChanged: searchDebounce.restart()
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: root.searchResults

                  Rectangle {
                    id: resultItem
                    required property var modelData
                    width: parent.width
                    height: Style.space(28)
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
                      anchors.leftMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: resultItem.modelData.display
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body * 0.9
                      color: resultHover.containsMouse ? Color.background : root.contentForeground
                    }
                  }
                }
              }
            }

            // List of configured cities with Delete buttons
            Column {
              width: parent.width
              spacing: Style.space(3)

              Repeater {
                model: root.worldClocks

                Rectangle {
                  id: manageRow
                  required property var modelData
                  width: parent.width
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)

                    Text {
                      text: manageRow.modelData.name
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body * 0.95
                      font.bold: true
                      color: root.contentForeground
                    }

                    Text {
                      text: manageRow.modelData.offset
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption || 11
                      color: root.mutedColor
                      Layout.fillWidth: true
                      horizontalAlignment: Text.AlignRight
                      anchors.rightMargin: Style.space(8)
                    }

                    Button {
                      text: "✕"
                      horizontalPadding: Style.space(6)
                      verticalPadding: Style.space(1)
                      onClicked: root.deleteCity(manageRow.modelData.name)
                    }
                  }
                }
              }
            }

            PanelSeparator { width: parent.width }

            // ── Section 2: Display Settings ──────────────────────────────────
            // Setting: Time Format
            RowLayout {
              width: parent.width

              ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Text {
                  text: "Time Display Format"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body * 0.95
                  font.bold: true
                  color: root.contentForeground
                }
                Text {
                  text: root.timeFormat24h ? "24-Hour (18:05)" : "12-Hour (6:05 PM)"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption || 11
                  color: root.mutedColor
                }
              }

              Button {
                text: root.timeFormat24h ? "Use 12h" : "Use 24h"
                Layout.preferredWidth: Style.space(92)
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(3)
                onClicked: root.setSetting("timeFormat24h", !root.timeFormat24h)
              }
            }

            // Setting: First Day of Week
            RowLayout {
              width: parent.width

              ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Text {
                  text: "First Day of Week"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body * 0.95
                  font.bold: true
                  color: root.contentForeground
                }
                Text {
                  text: root.firstDayOfWeek === "monday" ? "Starts on Monday" : "Starts on Sunday"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption || 11
                  color: root.mutedColor
                }
              }

              Button {
                text: root.firstDayOfWeek === "monday" ? "Set Sunday" : "Set Monday"
                Layout.preferredWidth: Style.space(92)
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(3)
                onClicked: root.setSetting("firstDayOfWeek", root.firstDayOfWeek === "monday" ? "sunday" : "monday")
              }
            }

            // Setting: Week Numbers
            RowLayout {
              width: parent.width

              ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Text {
                  text: "Show Week Numbers"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body * 0.95
                  font.bold: true
                  color: root.contentForeground
                }
                Text {
                  text: "Display ISO week number column"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption || 11
                  color: root.mutedColor
                }
              }

              Button {
                text: root.showWeekNumbers ? "Hide" : "Show"
                Layout.preferredWidth: Style.space(92)
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(3)
                onClicked: root.setSetting("showWeekNumbers", !root.showWeekNumbers)
              }
            }

            // Setting: Sunrise & Sunset
            RowLayout {
              width: parent.width

              ColumnLayout {
                spacing: 1
                Layout.fillWidth: true
                Text {
                  text: "Show Sunrise & Sunset"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body * 0.95
                  font.bold: true
                  color: root.contentForeground
                }
                Text {
                  text: "Show sunrise/sunset times under clocks"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption || 11
                  color: root.mutedColor
                }
              }

              Button {
                text: root.showSunriseSunset ? "Hide" : "Show"
                Layout.preferredWidth: Style.space(92)
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Style.space(4)
                verticalPadding: Style.space(3)
                onClicked: root.setSetting("showSunriseSunset", !root.showSunriseSunset)
              }
            }

            PanelSeparator { width: parent.width }

            // Restore defaults
            Button {
              text: "Restore Default Locations (SF, NY, London, Tokyo)"
              width: parent.width
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.resetDefaults()
            }

            Item {
              width: parent.width
              height: Style.space(6)
            }
          }

          // ═══════════════════════════════════════════════════════════════════
          // VIEW B: MAIN POPUP (CALENDAR + WORLD CLOCKS)
          // ═══════════════════════════════════════════════════════════════════
          Column {
            visible: !root.settingsMode
            width: parent.width
            spacing: Style.space(6)

            // ── 1. Calendar Header (Month Year <> + Settings) ───────────────
            RowLayout {
              width: parent.width

              Text {
                text: root.currentMonthYearTitle
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body * 1.15
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
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(2)
                  onClicked: root.stepMonth(-1)
                }

                Button {
                  text: "›"
                  horizontalPadding: Style.space(8)
                  verticalPadding: Style.space(2)
                  onClicked: root.stepMonth(1)
                }

                Button {
                  text: "⚙"
                  horizontalPadding: Style.space(7)
                  verticalPadding: Style.space(2)
                  onClicked: root.settingsMode = true
                }
              }
            }

            // ── 2. Month Calendar Grid ──────────────────────────────────────
            Column {
              width: parent.width
              spacing: Style.space(1)

              // Weekday headings
              Row {
                id: headingRow
                width: parent.width

                Item {
                  visible: root.showWeekNumbers
                  width: Style.space(22)
                  height: Style.space(18)
                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    font.family: root.contentFontFamily
                    font.pixelSize: 10
                    font.bold: true
                    color: root.mutedColor
                  }
                }

                Repeater {
                  model: root.weekdays
                  Item {
                    required property int modelData
                    readonly property real colW: (headingRow.width - (root.showWeekNumbers ? Style.space(22) : 0)) / 7
                    width: colW
                    height: Style.space(18)

                    Text {
                      anchors.centerIn: parent
                      text: root.labelLocale.dayName(modelData, Locale.ShortFormat).substring(0, 2).toUpperCase()
                      font.family: root.contentFontFamily
                      font.pixelSize: 10
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

                  Item {
                    visible: root.showWeekNumbers
                    width: Style.space(22)
                    height: Style.space(22)
                    Text {
                      anchors.centerIn: parent
                      text: weekRow.modelData.week
                      font.family: root.contentFontFamily
                      font.pixelSize: 9
                      color: root.mutedColor
                      opacity: 0.7
                    }
                  }

                  Repeater {
                    model: weekRow.modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData
                      readonly property real colW: (weekRow.width - (root.showWeekNumbers ? Style.space(22) : 0)) / 7
                      width: colW
                      height: Style.space(22)
                      radius: Style.cornerRadius
                      color: modelData.today ? root.accentColor : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body * 0.9
                        font.bold: modelData.today
                        // Clearly visible grey for days outside the month:
                        color: modelData.today 
                          ? Color.background 
                          : (modelData.inMonth ? root.contentForeground : root.mutedColor)
                        opacity: modelData.inMonth || modelData.today ? 1.0 : 0.75
                      }
                    }
                  }
                }
              }
            }

            // Tight separator below calendar
            PanelSeparator {
              width: parent.width
            }

            // ── 3. World Clocks List ─────────────────────────────────────────
            Column {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.worldClocks

                Rectangle {
                  id: clockRow
                  required property var modelData
                  width: parent.width
                  implicitHeight: root.showSunriseSunset && modelData.sunrise ? Style.space(52) : Style.space(44)
                  radius: Style.cornerRadius
                  color: clockHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                  border.width: 1
                  border.color: clockHover.containsMouse ? root.accentColor : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

                  MouseArea {
                    id: clockHover
                    anchors.fill: parent
                    hoverEnabled: true
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(12)
                    spacing: Style.space(8)

                    // Business Hours Status Dot (Green: 9am-6pm, Yellow: up to 8pm, Red: out of hours)
                    Rectangle {
                      width: Style.space(9)
                      height: Style.space(9)
                      radius: width / 2
                      color: {
                        if (clockRow.modelData.status_color === "green") return "#4ade80"
                        if (clockRow.modelData.status_color === "yellow") return "#facc15"
                        return "#f87171"
                      }
                      Layout.alignment: Qt.AlignVCenter
                    }

                    // Left Column: Location Name + Today + Sunrise/Sunset
                    ColumnLayout {
                      spacing: 0
                      Layout.fillWidth: true

                      Text {
                        text: clockRow.modelData.name
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        color: root.contentForeground
                      }

                      RowLayout {
                        spacing: Style.space(6)

                        Text {
                          text: clockRow.modelData.day
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption || 11
                          color: root.mutedColor
                        }

                        Text {
                          visible: root.showSunriseSunset && clockRow.modelData.sunrise !== ""
                          text: "↑ " + clockRow.modelData.sunrise + "  ↓ " + clockRow.modelData.sunset
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption || 10
                          color: root.mutedColor
                          opacity: 0.85
                        }
                      }
                    }

                    // Right Column: Big Time + Relative Offset
                    ColumnLayout {
                      spacing: 0
                      Layout.alignment: Qt.AlignRight

                      Text {
                        text: clockRow.modelData.time
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.title ? Style.font.title * 1.15 : 18
                        font.bold: true
                        color: root.contentForeground
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignRight
                      }

                      Text {
                        text: clockRow.modelData.offset
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption || 11
                        color: clockRow.modelData.offset === "Same time" ? root.mutedColor : root.accentColor
                        horizontalAlignment: Text.AlignRight
                        Layout.alignment: Qt.AlignRight
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
