import Foundation

enum ConfigError: LocalizedError {
    case invalidWorkDuration
    case invalidBreakDuration
    case invalidIdleThreshold
    case invalidOpacity

    var errorDescription: String? {
        switch self {
        case .invalidWorkDuration:
            return "work duration must be at least 1 minute"
        case .invalidBreakDuration:
            return "break duration must be at least 1 second"
        case .invalidIdleThreshold:
            return "idle threshold must be at least 1 minute"
        case .invalidOpacity:
            return "overlay opacity must be between 0.0 and 1.0"
        }
    }
}

enum OverlayScreenMode: String, Codable, CaseIterable {
    case both
    case left
    case right
}

struct AppConfig: Codable {
    var workDurationMinutes: Double
    var breakDurationSeconds: Double
    var idleThresholdMinutes: Double
    var autoStartOnLogin: Bool
    var pauseOnFullscreenApp: Bool
    var notificationSound: Bool
    var overlayOpacity: Double
    var firstRun: Bool
    var showBoxBreathing: Bool
    var overlayBackgroundHex: String
    var overlayForegroundHex: String
    var showHydrationReminder: Bool
    var overlayScreenMode: OverlayScreenMode

    init(
        workDurationMinutes: Double,
        breakDurationSeconds: Double,
        idleThresholdMinutes: Double,
        autoStartOnLogin: Bool,
        pauseOnFullscreenApp: Bool,
        notificationSound: Bool,
        overlayOpacity: Double,
        firstRun: Bool,
        showBoxBreathing: Bool,
        overlayBackgroundHex: String,
        overlayForegroundHex: String,
        showHydrationReminder: Bool,
        overlayScreenMode: OverlayScreenMode
    ) {
        self.workDurationMinutes = workDurationMinutes
        self.breakDurationSeconds = breakDurationSeconds
        self.idleThresholdMinutes = idleThresholdMinutes
        self.autoStartOnLogin = autoStartOnLogin
        self.pauseOnFullscreenApp = pauseOnFullscreenApp
        self.notificationSound = notificationSound
        self.overlayOpacity = overlayOpacity
        self.firstRun = firstRun
        self.showBoxBreathing = showBoxBreathing
        self.overlayBackgroundHex = overlayBackgroundHex
        self.overlayForegroundHex = overlayForegroundHex
        self.showHydrationReminder = showHydrationReminder
        self.overlayScreenMode = overlayScreenMode
    }

    static func defaults() -> AppConfig {
        AppConfig(
            workDurationMinutes: 20,
            breakDurationSeconds: 20,
            idleThresholdMinutes: 5,
            autoStartOnLogin: true,
            pauseOnFullscreenApp: false,
            notificationSound: true,
            overlayOpacity: 0.95,
            firstRun: true,
            showBoxBreathing: false,
            overlayBackgroundHex: "#000000",
            overlayForegroundHex: "#FFFFFF",
            showHydrationReminder: false,
            overlayScreenMode: .both
        )
    }

    func validated() throws -> AppConfig {
        if workDurationMinutes < 1 {
            throw ConfigError.invalidWorkDuration
        }
        if breakDurationSeconds < 1 {
            throw ConfigError.invalidBreakDuration
        }
        if idleThresholdMinutes < 1 {
            throw ConfigError.invalidIdleThreshold
        }
        if overlayOpacity < 0 || overlayOpacity > 1 {
            throw ConfigError.invalidOpacity
        }
        return self
    }

    var workDuration: TimeInterval { workDurationMinutes * 60 }
    var breakDuration: TimeInterval { breakDurationSeconds }
    var idleThreshold: TimeInterval { idleThresholdMinutes * 60 }

    enum CodingKeys: String, CodingKey {
        case workDurationMinutes = "work_duration_minutes"
        case breakDurationSeconds = "break_duration_seconds"
        case idleThresholdMinutes = "idle_threshold_minutes"
        case autoStartOnLogin = "auto_start_on_login"
        case pauseOnFullscreenApp = "pause_on_fullscreen_app"
        case notificationSound = "notification_sound"
        case overlayOpacity = "overlay_opacity"
        case firstRun = "first_run"
        case showBoxBreathing = "show_box_breathing"
        case overlayBackgroundHex = "overlay_background_hex"
        case overlayForegroundHex = "overlay_foreground_hex"
        case showHydrationReminder = "show_hydration_reminder"
        case overlayScreenMode = "overlay_screen_mode"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults()

        workDurationMinutes = try container.decodeIfPresent(Double.self, forKey: .workDurationMinutes) ?? defaults.workDurationMinutes
        breakDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .breakDurationSeconds) ?? defaults.breakDurationSeconds
        idleThresholdMinutes = try container.decodeIfPresent(Double.self, forKey: .idleThresholdMinutes) ?? defaults.idleThresholdMinutes
        autoStartOnLogin = try container.decodeIfPresent(Bool.self, forKey: .autoStartOnLogin) ?? defaults.autoStartOnLogin
        pauseOnFullscreenApp = try container.decodeIfPresent(Bool.self, forKey: .pauseOnFullscreenApp) ?? defaults.pauseOnFullscreenApp
        notificationSound = try container.decodeIfPresent(Bool.self, forKey: .notificationSound) ?? defaults.notificationSound
        overlayOpacity = try container.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? defaults.overlayOpacity
        firstRun = try container.decodeIfPresent(Bool.self, forKey: .firstRun) ?? defaults.firstRun
        showBoxBreathing = try container.decodeIfPresent(Bool.self, forKey: .showBoxBreathing) ?? defaults.showBoxBreathing
        overlayBackgroundHex = try container.decodeIfPresent(String.self, forKey: .overlayBackgroundHex) ?? defaults.overlayBackgroundHex
        overlayForegroundHex = try container.decodeIfPresent(String.self, forKey: .overlayForegroundHex) ?? defaults.overlayForegroundHex
        showHydrationReminder = try container.decodeIfPresent(Bool.self, forKey: .showHydrationReminder) ?? defaults.showHydrationReminder
        let screenModeRaw = try container.decodeIfPresent(String.self, forKey: .overlayScreenMode)
        overlayScreenMode = screenModeRaw.flatMap(OverlayScreenMode.init(rawValue:)) ?? defaults.overlayScreenMode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workDurationMinutes, forKey: .workDurationMinutes)
        try container.encode(breakDurationSeconds, forKey: .breakDurationSeconds)
        try container.encode(idleThresholdMinutes, forKey: .idleThresholdMinutes)
        try container.encode(autoStartOnLogin, forKey: .autoStartOnLogin)
        try container.encode(pauseOnFullscreenApp, forKey: .pauseOnFullscreenApp)
        try container.encode(notificationSound, forKey: .notificationSound)
        try container.encode(overlayOpacity, forKey: .overlayOpacity)
        try container.encode(firstRun, forKey: .firstRun)
        try container.encode(showBoxBreathing, forKey: .showBoxBreathing)
        try container.encode(overlayBackgroundHex, forKey: .overlayBackgroundHex)
        try container.encode(overlayForegroundHex, forKey: .overlayForegroundHex)
        try container.encode(showHydrationReminder, forKey: .showHydrationReminder)
        try container.encode(overlayScreenMode.rawValue, forKey: .overlayScreenMode)
    }
}
