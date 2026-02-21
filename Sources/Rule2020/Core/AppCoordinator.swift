import AppKit
import Foundation

final class AppCoordinator {
    private let configManager: ConfigManager
    private let statsStore: StatsStore
    private let timerManager: TimerManager
    private let activityMonitor: ActivityMonitor
    private let overlayWindow: OverlayWindowController
    private let menuBar: MenuBarController
    private let launchAtLoginManager = LaunchAtLoginManager()

    private var sessionID: Int64?
    private var isShutDown = false

    init() throws {
        configManager = try ConfigManager()
        statsStore = try StatsStore()

        let cfg = configManager.config
        timerManager = TimerManager(config: cfg, statsStore: statsStore)
        activityMonitor = ActivityMonitor(config: cfg)
        overlayWindow = OverlayWindowController(config: cfg)
        menuBar = MenuBarController(timerManager: timerManager, statsStore: statsStore)

        setupCallbacks()
    }

    func run() {
        do {
            sessionID = try statsStore.startSession()
        } catch {
            print("Warning: failed to start session: \(error.localizedDescription)")
        }

        if isLaunchAtLoginSupported() {
            syncLaunchAtLoginConfig()
        }

        if configManager.config.firstRun {
            print("First run detected. Welcome to 20-20-20 Rule!")
            applyConfigChanges(context: "first run update") { cfg in
                cfg.firstRun = false
            }
        }

        activityMonitor.start()
        timerManager.start()
        menuBar.start()

        print("Application started successfully")
    }

    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true

        print("Shutting down application...")

        menuBar.stop()
        activityMonitor.stop()
        timerManager.stop()

        if let sessionID {
            do {
                try statsStore.endSession(sessionID: sessionID, pausedDuration: 0)
            } catch {
                print("Warning: failed to end session: \(error.localizedDescription)")
            }
        }

        do {
            try statsStore.close()
        } catch {
            print("Warning: failed to close stats store: \(error.localizedDescription)")
        }

        print("Shutdown complete")
    }

    private func setupCallbacks() {
        menuBar.setConfigProvider { [weak self] in
            self?.configManager.config ?? AppConfig.defaults()
        }

        menuBar.setLaunchAtLoginSupportedProvider { [weak self] in
            self?.isLaunchAtLoginSupported() ?? false
        }

        timerManager.setOnBreakRequired { [weak self] in
            guard let self else { return }
            print("Break required - showing overlay")
            self.overlayWindow.show(duration: self.configManager.config.breakDuration)
        }

        timerManager.setOnBreakComplete { [weak self] in
            guard let self else { return }
            print("Break completed")
            self.overlayWindow.hide()
        }

        timerManager.setOnStateChange { state in
            print("Timer state changed to: \(state.rawValue)")
        }

        activityMonitor.setOnBecameIdle { [weak self] in
            print("User became idle - pausing timer")
            self?.timerManager.pauseInactive()
        }

        activityMonitor.setOnBecameActive { [weak self] in
            print("User became active - resuming timer")
            self?.timerManager.resumeFromInactive()
        }

        overlayWindow.setOnComplete { [weak self] in
            print("Overlay countdown complete")
            self?.timerManager.completeBreak()
        }

        overlayWindow.setOnForceDismiss { [weak self] in
            print("Overlay was manually dismissed")
            self?.timerManager.skipBreak()
        }

        menuBar.setOnPause { [weak self] in
            print("User paused timer")
            self?.timerManager.pause()
        }

        menuBar.setOnResume { [weak self] in
            print("User resumed timer")
            self?.timerManager.resume()
        }

        menuBar.setOnSkipBreak { [weak self] in
            print("User skipped break")
            self?.timerManager.skipBreak()
        }

        menuBar.setOnApplySettings { [weak self] values in
            self?.applySettings(values)
        }

        menuBar.setOnQuit { [weak self] in
            guard let self else { return }
            print("User requested quit")
            self.shutdown()
            NSApplication.shared.terminate(nil)
        }
    }

    private func applyConfigChanges(context: String, _ mutate: (inout AppConfig) -> Void) {
        var cfg = configManager.config
        mutate(&cfg)

        do {
            try configManager.update(cfg)
            timerManager.updateConfig(cfg)
            activityMonitor.updateConfig(cfg)
            overlayWindow.updateConfig(cfg)
        } catch {
            print("Warning: failed while \(context): \(error.localizedDescription)")
            showErrorAlert(title: "Einstellung konnte nicht gespeichert werden", message: error.localizedDescription)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard isLaunchAtLoginSupported() else {
            showErrorAlert(title: "Nicht unterstützt", message: "Autostart beim Login ist erst ab macOS 13 verfügbar.")
            return
        }

        do {
            try launchAtLoginManager.setEnabled(enabled)
            applyConfigChanges(context: "updating launch at login") { cfg in
                cfg.autoStartOnLogin = enabled
            }
        } catch {
            print("Warning: failed to update launch at login: \(error.localizedDescription)")
            showErrorAlert(title: "Autostart konnte nicht geändert werden", message: error.localizedDescription)
        }
    }

    private func applySettings(_ values: MenuBarController.SettingsValues) {
        var launchSettingForConfig = configManager.config.autoStartOnLogin

        if isLaunchAtLoginSupported() {
            do {
                try launchAtLoginManager.setEnabled(values.autoStartOnLogin)
                launchSettingForConfig = values.autoStartOnLogin
            } catch {
                print("Warning: failed to update launch at login: \(error.localizedDescription)")
                showErrorAlert(title: "Autostart konnte nicht geändert werden", message: error.localizedDescription)
                launchSettingForConfig = launchAtLoginManager.isEnabled()
            }
        } else if values.autoStartOnLogin != configManager.config.autoStartOnLogin {
            showErrorAlert(title: "Nicht unterstützt", message: "Autostart beim Login ist erst ab macOS 13 verfügbar.")
        }

        applyConfigChanges(context: "applying settings form") { cfg in
            cfg.workDurationMinutes = values.workDurationMinutes
            cfg.breakDurationSeconds = values.breakDurationSeconds
            cfg.overlayOpacity = values.overlayOpacity
            cfg.overlayScreenMode = values.overlayScreenMode
            cfg.showBoxBreathing = values.showBoxBreathing
            cfg.overlayBackgroundHex = values.overlayBackgroundHex
            cfg.overlayForegroundHex = values.overlayForegroundHex
            cfg.showHydrationReminder = values.showHydrationReminder
            cfg.autoStartOnLogin = launchSettingForConfig
        }
    }

    private func syncLaunchAtLoginConfig() {
        let actual = launchAtLoginManager.isEnabled()
        if configManager.config.autoStartOnLogin != actual {
            applyConfigChanges(context: "sync launch at login") { cfg in
                cfg.autoStartOnLogin = actual
            }
        }
    }

    private func isLaunchAtLoginSupported() -> Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    private func showErrorAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
