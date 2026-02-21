import AppKit
import Foundation
import CoreGraphics

private enum BreathingPhase {
    case inhale
    case holdAfterInhale
    case exhale
    case holdAfterExhale

    var title: String {
        switch self {
        case .inhale:
            return "Einatmen"
        case .holdAfterInhale, .holdAfterExhale:
            return "Halten"
        case .exhale:
            return "Ausatmen"
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class BreathBallView: NSView {
    private let circle = CALayer()
    private let countLabel = NSTextField(labelWithString: "1")
    private let phaseLabel = NSTextField(labelWithString: "Halten")
    private let foregroundColor: NSColor
    private var baseDiameter: CGFloat = 220

    init(frame frameRect: NSRect, foregroundColor: NSColor) {
        self.foregroundColor = foregroundColor
        super.init(frame: frameRect)
        wantsLayer = true

        circle.backgroundColor = foregroundColor.withAlphaComponent(0.55).cgColor
        circle.shadowColor = foregroundColor.withAlphaComponent(0.32).cgColor
        circle.shadowOpacity = 1
        circle.shadowRadius = 28
        circle.shadowOffset = .zero
        layer?.addSublayer(circle)

        countLabel.alignment = .center
        countLabel.textColor = foregroundColor
        countLabel.font = .systemFont(ofSize: 128, weight: .bold)
        countLabel.backgroundColor = .clear
        addSubview(countLabel)

        phaseLabel.alignment = .center
        phaseLabel.textColor = foregroundColor.withAlphaComponent(0.95)
        phaseLabel.font = .systemFont(ofSize: 52, weight: .semibold)
        phaseLabel.backgroundColor = .clear
        addSubview(phaseLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        baseDiameter = min(bounds.width, bounds.height) * 0.88
        setScaleImmediate(0.72)
    }

    func update(phase: BreathingPhase, secondInPhase: Int, phaseProgress: Double) {
        countLabel.stringValue = "\(secondInPhase)"
        phaseLabel.stringValue = phase.title

        let smooth = 0.5 - 0.5 * cos(phaseProgress * .pi)
        let targetScale: CGFloat

        switch phase {
        case .inhale:
            targetScale = CGFloat(0.72 + (0.46 * smooth))
        case .holdAfterInhale:
            targetScale = 1.18
        case .exhale:
            targetScale = CGFloat(1.18 - (0.46 * smooth))
        case .holdAfterExhale:
            targetScale = 0.72
        }

        setScaleImmediate(targetScale)
    }

    private func setScaleImmediate(_ scale: CGFloat) {
        let diameter = baseDiameter * scale
        let circleFrame = NSRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.frame = circleFrame
        circle.cornerRadius = diameter / 2
        CATransaction.commit()

        let countWidth = max(diameter * 0.44, 170)
        let countHeight = max(diameter * 0.30, 96)
        let phaseWidth = max(diameter * 0.74, 260)
        let phaseHeight = max(diameter * 0.20, 58)

        let countFont = max(diameter * 0.28, 84)
        let phaseFont = max(diameter * 0.11, 34)
        countLabel.font = .systemFont(ofSize: countFont, weight: .bold)
        phaseLabel.font = .systemFont(ofSize: phaseFont, weight: .semibold)

        countLabel.frame = NSRect(
            x: (bounds.width - countWidth) / 2,
            y: circleFrame.midY - (countHeight * 0.40),
            width: countWidth,
            height: countHeight
        )
        phaseLabel.frame = NSRect(
            x: (bounds.width - phaseWidth) / 2,
            y: circleFrame.midY - (countHeight * 0.40) - phaseHeight - 8,
            width: phaseWidth,
            height: phaseHeight
        )
    }
}

private final class WaterDropsView: NSView {
    private let dropColor: NSColor
    private var dropLayers: [CAShapeLayer] = []

    init(frame frameRect: NSRect, dropColor: NSColor) {
        self.dropColor = dropColor
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        rebuildDrops()
    }

    private func rebuildDrops() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        dropLayers.removeAll()

        guard bounds.width > 10, bounds.height > 10 else { return }

        let count = 28
        for idx in 0..<count {
            let size = CGFloat.random(in: 10...24)
            let x = CGFloat.random(in: 0...(max(bounds.width - size, 1)))
            let y = CGFloat.random(in: 0...(max(bounds.height - size, 1)))

            let layer = CAShapeLayer()
            layer.path = dropPath(size: size).cgPathCompat
            layer.fillColor = dropColor.withAlphaComponent(CGFloat.random(in: 0.20...0.45)).cgColor
            layer.frame = NSRect(x: x, y: y, width: size, height: size)

            let drift = CABasicAnimation(keyPath: "transform.translation.y")
            drift.fromValue = 0
            drift.toValue = CGFloat.random(in: 5...16)
            drift.duration = Double.random(in: 2.2...4.4)
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.beginTime = CACurrentMediaTime() + (Double(idx) * 0.03)
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(drift, forKey: "drift")

            self.layer?.addSublayer(layer)
            dropLayers.append(layer)
        }
    }

    private func dropPath(size: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let h = size
        let w = size * 0.72
        let ox = (size - w) / 2

        path.move(to: NSPoint(x: ox + w / 2, y: h))
        path.curve(
            to: NSPoint(x: ox + w, y: h * 0.45),
            controlPoint1: NSPoint(x: ox + w * 0.90, y: h * 0.88),
            controlPoint2: NSPoint(x: ox + w, y: h * 0.63)
        )
        path.curve(
            to: NSPoint(x: ox + w / 2, y: 0),
            controlPoint1: NSPoint(x: ox + w, y: h * 0.18),
            controlPoint2: NSPoint(x: ox + w * 0.70, y: 0)
        )
        path.curve(
            to: NSPoint(x: ox, y: h * 0.45),
            controlPoint1: NSPoint(x: ox + w * 0.30, y: 0),
            controlPoint2: NSPoint(x: ox, y: h * 0.18)
        )
        path.curve(
            to: NSPoint(x: ox + w / 2, y: h),
            controlPoint1: NSPoint(x: ox, y: h * 0.63),
            controlPoint2: NSPoint(x: ox + w * 0.10, y: h * 0.88)
        )
        path.close()
        return path
    }
}

private extension NSBezierPath {
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

final class OverlayWindowController {
    private var config: AppConfig
    private var isShowing = false
    private var windows: [OverlayWindow] = []

    private var countdownLabels: [NSTextField] = []
    private var countdownSubtitles: [NSTextField] = []

    private var breathBallViews: [BreathBallView] = []
    private var hydrationLabels: [NSTextField] = []
    private var hydrationDropViews: [WaterDropsView] = []

    private var tickTimer: Timer?
    private var breakStartAt: Date?
    private var breakEndAt: Date?
    private var totalDuration: TimeInterval = 0
    private var remainingSeconds: Int = 0

    private var onComplete: (() -> Void)?
    private var onForceDismiss: (() -> Void)?
    private var screenObserver: NSObjectProtocol?

    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var recentEscapePresses: [Date] = []

    init(config: AppConfig) {
        self.config = config
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isShowing else { return }
            self.createOverlayWindows()
            self.refreshDynamicLabels()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        removeKeyMonitors()
        tickTimer?.invalidate()
    }

    func show(duration: TimeInterval) {
        DispatchQueue.main.async {
            guard !self.isShowing else { return }
            self.isShowing = true
            self.remainingSeconds = max(Int(duration.rounded()), 1)
            self.totalDuration = duration
            self.breakStartAt = Date()
            self.breakEndAt = Date().addingTimeInterval(duration)
            self.recentEscapePresses.removeAll()

            NSApp.activate(ignoringOtherApps: true)
            self.createOverlayWindows()
            self.installKeyMonitors()
            self.startTickLoop()
            self.refreshDynamicLabels()
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.hideInternal()
        }
    }

    func setOnComplete(_ callback: @escaping () -> Void) {
        onComplete = callback
    }

    func setOnForceDismiss(_ callback: @escaping () -> Void) {
        onForceDismiss = callback
    }

    func updateConfig(_ config: AppConfig) {
        let needsRebuild = isShowing && (
            self.config.overlayOpacity != config.overlayOpacity ||
            self.config.showBoxBreathing != config.showBoxBreathing ||
            self.config.overlayBackgroundHex != config.overlayBackgroundHex ||
            self.config.overlayForegroundHex != config.overlayForegroundHex ||
            self.config.showHydrationReminder != config.showHydrationReminder ||
            self.config.overlayScreenMode != config.overlayScreenMode
        )

        self.config = config

        if isShowing {
            if needsRebuild {
                createOverlayWindows()
            }
            refreshDynamicLabels()
        }
    }

    private func createOverlayWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()

        countdownLabels.removeAll()
        countdownSubtitles.removeAll()
        breathBallViews.removeAll()
        hydrationLabels.removeAll()
        hydrationDropViews.removeAll()

        let frames = activeDisplayFrames(for: config.overlayScreenMode)
        print("Overlay: rendering on \(frames.count) display(s), mode=\(config.overlayScreenMode.rawValue)")
        let foregroundColor = overlayForegroundColor()

        for (idx, frame) in frames.enumerated() {
            print("Overlay display #\(idx + 1): \(frame)")

            let window = OverlayWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )

            window.setFrame(frame, display: true)
            window.isOpaque = false
            window.hasShadow = false
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.backgroundColor = overlayBackgroundColor()
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.ignoresMouseEvents = false

            let contentBounds = NSRect(origin: .zero, size: frame.size)
            let content = NSView(frame: contentBounds)

            let messageLabel = NSTextField(labelWithString: "👀 Schau in die Ferne!")
            messageLabel.alignment = .center
            messageLabel.textColor = foregroundColor
            messageLabel.font = .systemFont(ofSize: 54, weight: .bold)
            messageLabel.backgroundColor = .clear
            messageLabel.frame = NSRect(
                x: (contentBounds.width - 900) / 2,
                y: contentBounds.height * 0.80,
                width: 900,
                height: 66
            )
            content.addSubview(messageLabel)

            if config.showBoxBreathing {
                let ballSize = min(contentBounds.width * 0.62, contentBounds.height * 0.58)
                let ball = BreathBallView(frame: NSRect(
                    x: (contentBounds.width - ballSize) / 2,
                    y: (contentBounds.height - ballSize) / 2 - 12,
                    width: ballSize,
                    height: ballSize
                ), foregroundColor: foregroundColor)

                content.addSubview(ball)
                breathBallViews.append(ball)
            } else {
                let countdownLabel = NSTextField(labelWithString: "\(remainingSeconds)")
                countdownLabel.alignment = .center
                countdownLabel.textColor = foregroundColor
                countdownLabel.font = .systemFont(ofSize: 132, weight: .light)
                countdownLabel.backgroundColor = .clear
                countdownLabel.frame = NSRect(
                    x: (contentBounds.width - 320) / 2,
                    y: (contentBounds.height - 140) / 2,
                    width: 320,
                    height: 140
                )

                let subtitleLabel = NSTextField(labelWithString: "Sekunden verbleibend")
                subtitleLabel.alignment = .center
                subtitleLabel.textColor = foregroundColor.withAlphaComponent(0.82)
                subtitleLabel.font = .systemFont(ofSize: 28, weight: .regular)
                subtitleLabel.backgroundColor = .clear
                subtitleLabel.frame = NSRect(
                    x: (contentBounds.width - 540) / 2,
                    y: ((contentBounds.height - 140) / 2) - 56,
                    width: 540,
                    height: 34
                )

                content.addSubview(countdownLabel)
                content.addSubview(subtitleLabel)

                countdownLabels.append(countdownLabel)
                countdownSubtitles.append(subtitleLabel)
            }

            if config.showHydrationReminder {
                let waterText = NSTextField(labelWithString: "Hast schon getrunken?")
                waterText.alignment = .center
                waterText.textColor = foregroundColor.withAlphaComponent(0.95)
                waterText.font = .systemFont(ofSize: 34, weight: .semibold)
                waterText.backgroundColor = .clear
                waterText.frame = NSRect(
                    x: (contentBounds.width - 640) / 2,
                    y: contentBounds.height * 0.23,
                    width: 640,
                    height: 44
                )

                let drops = WaterDropsView(frame: NSRect(
                    x: (contentBounds.width - 520) / 2,
                    y: contentBounds.height * 0.04,
                    width: 520,
                    height: 150
                ), dropColor: foregroundColor)

                content.addSubview(drops)
                content.addSubview(waterText)
                hydrationDropViews.append(drops)
                hydrationLabels.append(waterText)
            }

            let hintLabel = NSTextField(labelWithString: "Esc 15x = Pause beenden")
            hintLabel.alignment = .center
            hintLabel.textColor = foregroundColor.withAlphaComponent(0.66)
            hintLabel.font = .systemFont(ofSize: 20, weight: .regular)
            hintLabel.backgroundColor = .clear
            hintLabel.frame = NSRect(
                x: (contentBounds.width - 420) / 2,
                y: contentBounds.height * 0.12,
                width: 420,
                height: 28
            )
            content.addSubview(hintLabel)

            window.contentView = content
            window.makeKeyAndOrderFront(nil)

            windows.append(window)
        }
    }

    private func activeDisplayFrames(for mode: OverlayScreenMode) -> [NSRect] {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 32
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))

        let result = CGGetActiveDisplayList(maxDisplays, &displayIDs, &displayCount)
        var frames: [NSRect] = []

        if result == .success && displayCount > 0 {
            for id in displayIDs.prefix(Int(displayCount)) {
                let bounds = CGDisplayBounds(id)
                frames.append(NSRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height))
            }
        }

        if frames.isEmpty {
            frames = NSScreen.screens.map { $0.frame }
        }

        var seen = Set<String>()
        var unique: [NSRect] = []
        for frame in frames {
            let key = "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.size.width)):\(Int(frame.size.height))"
            if seen.insert(key).inserted {
                unique.append(frame)
            }
        }

        guard !unique.isEmpty else {
            return []
        }

        switch mode {
        case .both:
            return unique
        case .left:
            if let leftMost = unique.min(by: { lhs, rhs in
                if lhs.minX == rhs.minX {
                    return lhs.minY < rhs.minY
                }
                return lhs.minX < rhs.minX
            }) {
                return [leftMost]
            }
        case .right:
            if let rightMost = unique.max(by: { lhs, rhs in
                if lhs.maxX == rhs.maxX {
                    return lhs.minY > rhs.minY
                }
                return lhs.maxX < rhs.maxX
            }) {
                return [rightMost]
            }
        }

        return unique
    }

    private func startTickLoop() {
        tickTimer?.invalidate()

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.isShowing else { return }
            guard let breakEndAt = self.breakEndAt else { return }

            let remaining = max(breakEndAt.timeIntervalSinceNow, 0)
            self.remainingSeconds = Int(ceil(remaining))

            if remaining <= 0 {
                self.completeCountdown()
                return
            }

            self.refreshDynamicLabels()
        }

        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshDynamicLabels() {
        if config.showBoxBreathing {
            let state = breathingState()

            for ball in breathBallViews {
                ball.update(
                    phase: state.phase,
                    secondInPhase: state.secondInPhase,
                    phaseProgress: state.phaseProgress
                )
            }
        } else {
            for label in countdownLabels {
                label.stringValue = "\(remainingSeconds)"
            }
            for label in countdownSubtitles {
                label.stringValue = "Sekunden verbleibend"
            }
        }
    }

    private func breathingState() -> (phase: BreathingPhase, secondInPhase: Int, phaseProgress: Double) {
        guard let breakStartAt else {
            return (.inhale, 1, 0)
        }
        let elapsedTime = max(Date().timeIntervalSince(breakStartAt), 0)
        let boundedElapsed = min(elapsedTime, totalDuration)
        let cyclePosition = boundedElapsed.truncatingRemainder(dividingBy: 16)
        let phaseIndex = Int(cyclePosition / 4)
        let phaseTime = cyclePosition.truncatingRemainder(dividingBy: 4)
        let phaseProgress = max(0, min(phaseTime / 4, 1))
        let secondInPhase = min(max(Int(floor(phaseTime)) + 1, 1), 4)

        switch phaseIndex {
        case 0:
            return (.inhale, secondInPhase, phaseProgress)
        case 1:
            return (.holdAfterInhale, secondInPhase, phaseProgress)
        case 2:
            return (.exhale, secondInPhase, phaseProgress)
        default:
            return (.holdAfterExhale, secondInPhase, phaseProgress)
        }
    }

    private func installKeyMonitors() {
        removeKeyMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    private func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isShowing else { return }
        guard event.keyCode == 53 else { return }

        let now = Date()
        recentEscapePresses = recentEscapePresses.filter { now.timeIntervalSince($0) <= 1.8 }
        recentEscapePresses.append(now)

        if recentEscapePresses.count >= 15 {
            print("Overlay manually dismissed via Esc x15")
            forceDismiss()
        }
    }

    private func completeCountdown() {
        hideInternal()
        onComplete?()
    }

    private func forceDismiss() {
        hideInternal()
        onForceDismiss?()
    }

    private func hideInternal() {
        guard isShowing else { return }

        isShowing = false
        recentEscapePresses.removeAll()
        breakStartAt = nil
        breakEndAt = nil

        removeKeyMonitors()

        tickTimer?.invalidate()
        tickTimer = nil

        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        countdownLabels.removeAll()
        countdownSubtitles.removeAll()
        breathBallViews.removeAll()
        hydrationLabels.removeAll()
        hydrationDropViews.removeAll()
    }

    private func overlayBackgroundColor() -> NSColor {
        let base = NSColor.fromHex(config.overlayBackgroundHex, fallback: .black)
        return base.withAlphaComponent(CGFloat(config.overlayOpacity))
    }

    private func overlayForegroundColor() -> NSColor {
        NSColor.fromHex(config.overlayForegroundHex, fallback: .white)
    }
}
