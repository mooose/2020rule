import Foundation
import ApplicationServices

final class ActivityMonitor {
    private var config: AppConfig
    private let pollInterval: TimeInterval = 10
    private var timer: Timer?
    private var isIdle = false
    private let anyInputEventType = CGEventType(rawValue: UInt32.max)

    private var onBecameIdle: (() -> Void)?
    private var onBecameActive: (() -> Void)?

    init(config: AppConfig) {
        self.config = config
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkIdleStatus()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setOnBecameIdle(_ callback: @escaping () -> Void) {
        onBecameIdle = callback
    }

    func setOnBecameActive(_ callback: @escaping () -> Void) {
        onBecameActive = callback
    }

    func updateConfig(_ config: AppConfig) {
        self.config = config
    }

    private func checkIdleStatus() {
        guard let anyInputEventType else { return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEventType
        )
        let currentlyIdle = idleSeconds >= config.idleThreshold

        if currentlyIdle && !isIdle {
            isIdle = true
            onBecameIdle?()
        } else if !currentlyIdle && isIdle {
            isIdle = false
            onBecameActive?()
        }
    }
}
