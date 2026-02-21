import AppKit
import Foundation

final class MenuBarController: NSObject, NSMenuDelegate {
    struct SettingsValues {
        let workDurationMinutes: Double
        let breakDurationSeconds: Double
        let overlayOpacity: Double
        let overlayScreenMode: OverlayScreenMode
        let autoStartOnLogin: Bool
        let showBoxBreathing: Bool
        let overlayBackgroundHex: String
        let overlayForegroundHex: String
        let showHydrationReminder: Bool
    }

    private let timerManager: TimerManager
    private let statsStore: StatsStore

    private let statusItem = NSStatusBar.system.statusItem(withLength: 126)
    private let menu = NSMenu()
    private var refreshTimer: Timer?

    private var configProvider: (() -> AppConfig)?
    private var launchAtLoginSupportedProvider: (() -> Bool)?

    private var onPause: (() -> Void)?
    private var onResume: (() -> Void)?
    private var onSkipBreak: (() -> Void)?
    private var onApplySettings: ((SettingsValues) -> Void)?
    private var onQuit: (() -> Void)?

    init(timerManager: TimerManager, statsStore: StatsStore) {
        self.timerManager = timerManager
        self.statsStore = statsStore
        super.init()
    }

    func start() {
        menu.delegate = self
        statusItem.menu = menu
        updateStatusDisplay()

        rebuildMenu()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateStatusDisplay()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func setConfigProvider(_ provider: @escaping () -> AppConfig) {
        configProvider = provider
    }

    func setLaunchAtLoginSupportedProvider(_ provider: @escaping () -> Bool) {
        launchAtLoginSupportedProvider = provider
    }

    func setOnPause(_ callback: @escaping () -> Void) {
        onPause = callback
    }

    func setOnResume(_ callback: @escaping () -> Void) {
        onResume = callback
    }

    func setOnSkipBreak(_ callback: @escaping () -> Void) {
        onSkipBreak = callback
    }

    func setOnApplySettings(_ callback: @escaping (SettingsValues) -> Void) {
        onApplySettings = callback
    }

    func setOnQuit(_ callback: @escaping () -> Void) {
        onQuit = callback
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func handlePauseResume(_ sender: NSMenuItem) {
        if sender.representedObject as? String == "pause" {
            onPause?()
        } else {
            onResume?()
        }
    }

    @objc private func handleSkipBreak(_ sender: NSMenuItem) {
        onSkipBreak?()
    }

    @objc private func handleOpenSettings(_ sender: NSMenuItem) {
        guard let config = currentConfig() else { return }
        let launchSupported = launchAtLoginSupportedProvider?() ?? false

        let dialog = SettingsDialogController(config: config, launchAtLoginSupported: launchSupported)
        if let values = dialog.runModal() {
            onApplySettings?(values)
        }
    }

    @objc private func handleQuit(_ sender: NSMenuItem) {
        onQuit?()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let infoItem = NSMenuItem(title: statusInfo(), action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        let state = timerManager.getState()
        switch state {
        case .running:
            let item = NSMenuItem(title: "Pausieren", action: #selector(handlePauseResume(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = "pause"
            menu.addItem(item)
        case .pausedManual, .pausedInactive:
            let item = NSMenuItem(title: "Fortsetzen", action: #selector(handlePauseResume(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = "resume"
            menu.addItem(item)
        case .breakRequired:
            let item = NSMenuItem(title: "Pause sofort beenden (Esc x15)", action: #selector(handleSkipBreak(_:)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Einstellungen…", action: #selector(handleOpenSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let statsItem = NSMenuItem(title: "Statistiken", action: nil, keyEquivalent: "")
        statsItem.submenu = statisticsSubmenu()
        menu.addItem(statsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Beenden", action: #selector(handleQuit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func statusTitle() -> String {
        let state = timerManager.getState()
        switch state {
        case .running:
            let remainingMinutes = Int(ceil(timerManager.getTimeUntilBreak() / 60.0))
            return String(format: "⏱ %03dm", max(remainingMinutes, 0))
        case .breakRequired:
            return "👁 Pause"
        case .pausedManual:
            return "⏸ Pause"
        case .pausedInactive:
            return "💤 Idle"
        }
    }

    private func statusInfo() -> String {
        let state = timerManager.getState()
        switch state {
        case .running:
            let remainingMinutes = max(Int(ceil(timerManager.getTimeUntilBreak() / 60.0)), 0)
            return "Nächste Pause in: \(remainingMinutes) min"
        case .breakRequired:
            return "Zeit für eine Augenpause!"
        case .pausedManual:
            return "Timer ist pausiert"
        case .pausedInactive:
            return "Timer pausiert (inaktiv)"
        }
    }

    private func updateStatusDisplay() {
        guard let button = statusItem.button else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        let title = statusTitle()
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func statisticsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let today = reportText(period: "today", label: "Heute")
        submenu.addItem(NSMenuItem(title: today, action: nil, keyEquivalent: ""))

        let week = reportText(period: "week", label: "Woche")
        submenu.addItem(NSMenuItem(title: week, action: nil, keyEquivalent: ""))

        let month = reportText(period: "month", label: "Monat")
        submenu.addItem(NSMenuItem(title: month, action: nil, keyEquivalent: ""))

        return submenu
    }

    private func reportText(period: String, label: String) -> String {
        do {
            let report = try statsStore.getComplianceReport(period: period)
            return String(format: "%@: %d/%d (%.0f%%)", label, report.completedBreaks, report.totalBreaks, report.complianceRate)
        } catch {
            return "\(label): Keine Daten"
        }
    }

    private func currentConfig() -> AppConfig? {
        configProvider?()
    }
}

private final class SettingsDialogController: NSObject, NSWindowDelegate {
    private let config: AppConfig
    private let launchAtLoginSupported: Bool

    private(set) var result: MenuBarController.SettingsValues?

    private let window: NSWindow
    private let workField = NSTextField()
    private let breakField = NSTextField()
    private let opacitySlider = NSSlider(value: 95, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "95%")
    private let overlayScreenModePopup = NSPopUpButton()
    private let backgroundColorWell = NSColorWell()
    private let foregroundColorWell = NSColorWell()
    private let autoStartCheck = NSButton(checkboxWithTitle: "Beim Login starten", target: nil, action: nil)
    private let breathingCheck = NSButton(checkboxWithTitle: "Box Breathing anzeigen", target: nil, action: nil)
    private let hydrationCheck = NSButton(checkboxWithTitle: "Trink-Hinweis mit Wassertropfen anzeigen", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")

    init(config: AppConfig, launchAtLoginSupported: Bool) {
        self.config = config
        self.launchAtLoginSupported = launchAtLoginSupported

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        super.init()
        buildUI()
    }

    func runModal() -> MenuBarController.SettingsValues? {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        return result
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        opacityValueLabel.stringValue = "\(Int(sender.doubleValue.rounded()))%"
    }

    @objc private func cancelTapped(_ sender: NSButton) {
        result = nil
        NSApp.stopModal(withCode: .cancel)
        window.orderOut(nil)
        window.close()
    }

    @objc private func saveTapped(_ sender: NSButton) {
        guard let workMinutes = parseNumber(workField.stringValue), workMinutes >= 1 else {
            showValidation("Arbeitsintervall muss mindestens 1 Minute sein.")
            return
        }

        guard let breakSeconds = parseNumber(breakField.stringValue), breakSeconds >= 1 else {
            showValidation("Pausendauer muss mindestens 1 Sekunde sein.")
            return
        }

        let opacityPercent = opacitySlider.doubleValue
        guard opacityPercent >= 0, opacityPercent <= 100 else {
            showValidation("Overlay-Deckkraft muss zwischen 0 und 100 liegen.")
            return
        }

        result = MenuBarController.SettingsValues(
            workDurationMinutes: workMinutes,
            breakDurationSeconds: breakSeconds,
            overlayOpacity: opacityPercent / 100.0,
            overlayScreenMode: selectedOverlayScreenMode(),
            autoStartOnLogin: autoStartCheck.state == .on,
            showBoxBreathing: breathingCheck.state == .on,
            overlayBackgroundHex: backgroundColorWell.color.hexRGB,
            overlayForegroundHex: foregroundColorWell.color.hexRGB,
            showHydrationReminder: hydrationCheck.state == .on
        )

        NSApp.stopModal(withCode: .OK)
        window.orderOut(nil)
        window.close()
    }

    private func buildUI() {
        window.title = "Einstellungen"
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.isReleasedWhenClosed = false

        let root = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        root.material = .sidebar
        root.state = .active
        root.blendingMode = .behindWindow
        window.contentView = root

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(container)

        let titleLabel = NSTextField(labelWithString: "20-20-20 Einstellungen")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: "Alles an einem Ort: Timer, Anzeige und Verhalten")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        workField.stringValue = String(format: "%.0f", config.workDurationMinutes)
        breakField.stringValue = String(format: "%.0f", config.breakDurationSeconds)

        opacitySlider.doubleValue = config.overlayOpacity * 100
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacityValueLabel.stringValue = "\(Int((config.overlayOpacity * 100).rounded()))%"
        opacityValueLabel.alignment = .right
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)

        autoStartCheck.state = config.autoStartOnLogin ? .on : .off
        autoStartCheck.isEnabled = launchAtLoginSupported
        breathingCheck.state = config.showBoxBreathing ? .on : .off
        hydrationCheck.state = config.showHydrationReminder ? .on : .off
        backgroundColorWell.color = NSColor.fromHex(config.overlayBackgroundHex, fallback: .black)
        foregroundColorWell.color = NSColor.fromHex(config.overlayForegroundHex, fallback: .white)
        configureOverlayScreenModePopup()

        let launchHintLabel = NSTextField(labelWithString: launchAtLoginSupported ? "" : "Autostart beim Login ist ab macOS 13 verfügbar")
        launchHintLabel.font = .systemFont(ofSize: 12)
        launchHintLabel.textColor = .secondaryLabelColor
        launchHintLabel.isHidden = launchAtLoginSupported

        let escHintLabel = NSTextField(labelWithString: "Pause entsperren: Esc 15x")
        escHintLabel.font = .systemFont(ofSize: 12)
        escHintLabel.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [labelCell("Arbeitsintervall"), fieldCell(workField, suffix: "Min")],
            [labelCell("Pausendauer"), fieldCell(breakField, suffix: "Sek")],
            [labelCell("Overlay-Deckkraft"), sliderCell(opacitySlider, trailingLabel: opacityValueLabel)],
            [labelCell("Overlay-Monitor"), popupCell(overlayScreenModePopup)],
            [labelCell("Sperrbildschirm-Farbe"), colorCell(backgroundColorWell)],
            [labelCell("Textfarbe"), colorCell(foregroundColorWell)]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 16
        grid.xPlacement = .leading
        grid.yPlacement = .center

        errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        let cancelButton = NSButton(title: "Abbrechen", target: self, action: #selector(cancelTapped(_:)))
        cancelButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Speichern", target: self, action: #selector(saveTapped(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .gravityAreas

        let checks = NSStackView(views: [autoStartCheck, launchHintLabel, breathingCheck, hydrationCheck, escHintLabel])
        checks.orientation = .vertical
        checks.spacing = 6
        checks.alignment = .leading

        let mainStack = NSStackView(views: [titleLabel, subtitleLabel, grid, checks, errorLabel, buttonRow])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(mainStack)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            container.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),

            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: container.topAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),

            workField.widthAnchor.constraint(equalToConstant: 90),
            breakField.widthAnchor.constraint(equalToConstant: 90),
            opacityValueLabel.widthAnchor.constraint(equalToConstant: 56),
            overlayScreenModePopup.widthAnchor.constraint(equalToConstant: 220),

            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    private func showValidation(_ text: String) {
        errorLabel.stringValue = text
        errorLabel.isHidden = false
    }

    private func parseNumber(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private func labelCell(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        return label
    }

    private func fieldCell(_ field: NSTextField, suffix: String) -> NSView {
        let suffixLabel = NSTextField(labelWithString: suffix)
        suffixLabel.font = .systemFont(ofSize: 12)
        suffixLabel.textColor = .secondaryLabelColor

        let row = NSStackView(views: [field, suffixLabel])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    private func sliderCell(_ slider: NSSlider, trailingLabel: NSTextField) -> NSView {
        let row = NSStackView(views: [slider, trailingLabel])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    private func popupCell(_ popup: NSPopUpButton) -> NSView {
        let row = NSStackView(views: [popup])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        return row
    }

    private func colorCell(_ colorWell: NSColorWell) -> NSView {
        colorWell.isBordered = true
        colorWell.alphaValue = 1.0
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 86).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let row = NSStackView(views: [colorWell])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        return row
    }

    private func configureOverlayScreenModePopup() {
        overlayScreenModePopup.removeAllItems()

        for mode in OverlayScreenMode.allCases {
            overlayScreenModePopup.addItem(withTitle: mode.settingsLabel)
            overlayScreenModePopup.lastItem?.representedObject = mode.rawValue
        }

        let selectedRaw = config.overlayScreenMode.rawValue
        if let item = overlayScreenModePopup.itemArray.first(where: { ($0.representedObject as? String) == selectedRaw }) {
            overlayScreenModePopup.select(item)
        } else {
            overlayScreenModePopup.selectItem(at: 0)
        }
    }

    private func selectedOverlayScreenMode() -> OverlayScreenMode {
        guard
            let raw = overlayScreenModePopup.selectedItem?.representedObject as? String,
            let mode = OverlayScreenMode(rawValue: raw)
        else {
            return config.overlayScreenMode
        }

        return mode
    }
}

private extension OverlayScreenMode {
    var settingsLabel: String {
        switch self {
        case .both:
            return "Beide Monitore"
        case .left:
            return "Nur linker Monitor"
        case .right:
            return "Nur rechter Monitor"
        }
    }
}
