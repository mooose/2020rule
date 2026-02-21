import Foundation

enum TimerState: String {
    case running = "Running"
    case breakRequired = "Break Required"
    case pausedManual = "Paused"
    case pausedInactive = "Paused (Idle)"
}

final class TimerManager {
    private let queue = DispatchQueue(label: "com.siegfried.2020rule.timer")
    private var state: TimerState = .pausedManual
    private var config: AppConfig
    private let statsStore: StatsStore?

    private var workTimer: DispatchSourceTimer?
    private var breakTimer: DispatchSourceTimer?

    private var workStartTime: Date = Date()
    private var breakStartTime: Date = Date()
    private var currentBreakID: Int64 = 0
    private var elapsed: TimeInterval = 0

    private var onBreakRequired: (() -> Void)?
    private var onBreakComplete: (() -> Void)?
    private var onStateChange: ((TimerState) -> Void)?

    init(config: AppConfig, statsStore: StatsStore?) {
        self.config = config
        self.statsStore = statsStore
    }

    func start() {
        queue.async {
            if self.state == .running || self.state == .breakRequired { return }
            self.state = .running
            self.workStartTime = Date()
            self.elapsed = 0
            self.scheduleWorkTimerLocked()
            self.notifyStateChangeLocked()
        }
    }

    func pause() {
        queue.async {
            guard self.state == .running else { return }
            self.stopWorkTimerLocked()
            self.elapsed += Date().timeIntervalSince(self.workStartTime)
            self.state = .pausedManual
            self.notifyStateChangeLocked()
        }
    }

    func resume() {
        queue.async {
            guard self.state == .pausedManual || self.state == .pausedInactive else { return }
            self.state = .running
            self.workStartTime = Date()
            self.scheduleWorkTimerLocked()
            self.notifyStateChangeLocked()
        }
    }

    func pauseInactive() {
        queue.async {
            guard self.state == .running else { return }
            self.stopWorkTimerLocked()
            self.elapsed += Date().timeIntervalSince(self.workStartTime)
            self.state = .pausedInactive
            self.notifyStateChangeLocked()
        }
    }

    func resumeFromInactive() {
        queue.async {
            guard self.state == .pausedInactive else { return }
            self.state = .running
            self.workStartTime = Date()
            self.scheduleWorkTimerLocked()
            self.notifyStateChangeLocked()
        }
    }

    func completeBreak() {
        queue.async {
            guard self.state == .breakRequired else { return }

            self.stopBreakTimerLocked()

            if let store = self.statsStore, self.currentBreakID > 0 {
                let duration = Date().timeIntervalSince(self.breakStartTime)
                try? store.recordBreakComplete(breakID: self.currentBreakID, duration: duration)
            }

            self.transitionToRunningLocked()
            self.dispatchMain(self.onBreakComplete)
        }
    }

    func skipBreak() {
        queue.async {
            guard self.state == .breakRequired else { return }

            self.stopBreakTimerLocked()

            if let store = self.statsStore, self.currentBreakID > 0 {
                try? store.recordBreakSkipped(breakID: self.currentBreakID)
            }

            self.transitionToRunningLocked()
            self.dispatchMain(self.onBreakComplete)
        }
    }

    func stop() {
        queue.async {
            self.stopWorkTimerLocked()
            self.stopBreakTimerLocked()
            self.state = .pausedManual
            self.elapsed = 0
            self.notifyStateChangeLocked()
        }
    }

    func getState() -> TimerState {
        queue.sync { state }
    }

    func getTimeUntilBreak() -> TimeInterval {
        queue.sync {
            guard state == .running else { return 0 }
            let totalElapsed = elapsed + Date().timeIntervalSince(workStartTime)
            return max(config.workDuration - totalElapsed, 0)
        }
    }

    func getBreakTimeRemaining() -> TimeInterval {
        queue.sync {
            guard state == .breakRequired else { return 0 }
            return max(config.breakDuration - Date().timeIntervalSince(breakStartTime), 0)
        }
    }

    func setOnBreakRequired(_ callback: @escaping () -> Void) {
        queue.async { self.onBreakRequired = callback }
    }

    func setOnBreakComplete(_ callback: @escaping () -> Void) {
        queue.async { self.onBreakComplete = callback }
    }

    func setOnStateChange(_ callback: @escaping (TimerState) -> Void) {
        queue.async { self.onStateChange = callback }
    }

    func updateConfig(_ newConfig: AppConfig) {
        queue.async {
            self.config = newConfig
            switch self.state {
            case .running:
                self.scheduleWorkTimerLocked()
            case .breakRequired:
                self.rescheduleBreakTimerLocked()
            case .pausedManual, .pausedInactive:
                break
            }
        }
    }

    private func scheduleWorkTimerLocked() {
        stopWorkTimerLocked()

        let remaining = config.workDuration - elapsed
        if remaining <= 0 {
            triggerBreakLocked()
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + remaining)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.state == .running {
                self.triggerBreakLocked()
            }
        }
        timer.resume()
        workTimer = timer
    }

    private func triggerBreakLocked() {
        stopWorkTimerLocked()

        if let store = statsStore {
            currentBreakID = (try? store.recordBreakStart()) ?? 0
        }

        state = .breakRequired
        breakStartTime = Date()

        stopBreakTimerLocked()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.breakDuration)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.state == .breakRequired else { return }

            if let store = self.statsStore, self.currentBreakID > 0 {
                let duration = Date().timeIntervalSince(self.breakStartTime)
                try? store.recordBreakComplete(breakID: self.currentBreakID, duration: duration)
            }

            self.transitionToRunningLocked()
            self.dispatchMain(self.onBreakComplete)
        }
        timer.resume()
        breakTimer = timer

        notifyStateChangeLocked()
        dispatchMain(onBreakRequired)
    }

    private func stopWorkTimerLocked() {
        workTimer?.cancel()
        workTimer = nil
    }

    private func stopBreakTimerLocked() {
        breakTimer?.cancel()
        breakTimer = nil
    }

    private func rescheduleBreakTimerLocked() {
        stopBreakTimerLocked()
        let remaining = max(config.breakDuration - Date().timeIntervalSince(breakStartTime), 0)
        if remaining <= 0 {
            transitionToRunningLocked()
            dispatchMain(onBreakComplete)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + remaining)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.state == .breakRequired else { return }

            if let store = self.statsStore, self.currentBreakID > 0 {
                let duration = Date().timeIntervalSince(self.breakStartTime)
                try? store.recordBreakComplete(breakID: self.currentBreakID, duration: duration)
            }

            self.transitionToRunningLocked()
            self.dispatchMain(self.onBreakComplete)
        }
        timer.resume()
        breakTimer = timer
    }

    private func notifyStateChangeLocked() {
        let current = state
        dispatchMain {
            self.onStateChange?(current)
        }
    }

    private func transitionToRunningLocked() {
        state = .running
        workStartTime = Date()
        elapsed = 0
        currentBreakID = 0
        scheduleWorkTimerLocked()
        notifyStateChangeLocked()
    }

    private func dispatchMain(_ callback: (() -> Void)?) {
        guard let callback else { return }
        DispatchQueue.main.async(execute: callback)
    }
}
