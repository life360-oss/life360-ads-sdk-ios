
import Foundation

/// A one-shot countdown that can be paused and resumed without losing its progress.
/// This is necessary for scroll-driven viewability tracking, where an ad's exposure toggles on and
/// off many times before it accumulates its required continuously-visible duration — a plain `Timer`
/// has no way to "bank" the time it already ran before being invalidated.
final class PausableCountdownTimer {

    private let duration: TimeInterval
    private let onFire: () -> Void

    private var timer: Timer?
    private var remainingDuration: TimeInterval

    private(set) var isRunning = false
    private(set) var hasFired = false

    init(duration: TimeInterval, onFire: @escaping () -> Void) {
        self.duration = duration
        self.remainingDuration = duration
        self.onFire = onFire
    }

    deinit {
        timer?.invalidate()
    }

    /// Resumes counting down from wherever it was left off. No-op if already running or already fired.
    func resume() {
        guard !isRunning, !hasFired else { return }
        isRunning = true

        let newTimer = Timer(timeInterval: remainingDuration, target: self, selector: #selector(fire), userInfo: nil, repeats: false)
        // Scroll gestures put the run loop into `.tracking` mode, which a `.default`-mode timer would
        // never fire in, so this timer has to run in `.common` to keep counting down mid-scroll.
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Pauses the countdown, preserving whatever time remains for a later `resume()`.
    func pause() {
        guard isRunning, let timer else { return }
        remainingDuration = max(0, timer.fireDate.timeIntervalSinceNow)
        timer.invalidate()
        self.timer = nil
        isRunning = false
    }

    @objc private func fire() {
        isRunning = false
        hasFired = true
        timer = nil
        onFire()
    }
}
