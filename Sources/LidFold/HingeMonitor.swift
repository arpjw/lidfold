import Foundation

/// Samples the hinge sensor away from the main actor and delivers filtered readings to UI code.
actor HingeMonitor {
    struct Configuration: Sendable, Equatable {
        var interval: Duration = .milliseconds(100)
        var smoothingFactor: Double = 0.35

        init(
            interval: Duration = .milliseconds(100),
            smoothingFactor: Double = 0.35
        ) {
            self.interval = interval
            self.smoothingFactor = smoothingFactor
        }
    }

    typealias ReadingHandler = @MainActor @Sendable (Double?) -> Void

    private let configuration: Configuration
    private let readAngle: @Sendable () -> Double?
    private var filter: HingeReadingFilter
    private var samplingTask: Task<Void, Never>?

    init(
        configuration: Configuration = Configuration(),
        readAngle: (@Sendable () -> Double?)? = nil
    ) {
        self.configuration = configuration
        self.filter = HingeReadingFilter(smoothingFactor: configuration.smoothingFactor)
        self.readAngle = readAngle ?? Self.makeHardwareReader()
    }

    /// Starts sampling. Calling this while already running replaces the existing callback.
    func start(onReading: @escaping ReadingHandler) {
        stop()
        samplingTask = Task { [weak self] in
            guard let self else { return }
            await self.run(onReading: onReading)
        }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        filter.reset()
    }

    /// Takes one filtered reading, primarily for diagnostics and deterministic tests.
    func sampleOnce() -> Double? {
        filter.process(readAngle())
    }

    private func run(onReading: @escaping ReadingHandler) async {
        while !Task.isCancelled {
            let angle = sampleOnce()
            await onReading(angle)

            do {
                try await Task.sleep(for: configuration.interval)
            } catch {
                break
            }
        }
    }

    private static func makeHardwareReader() -> @Sendable () -> Double? {
        let reader = HingeSensorReader()
        return { reader.readAngle() }
    }
}

/// `HingeMonitor` serializes all access to this box on its actor executor.
private final class HingeSensorReader: @unchecked Sendable {
    private let sensor = HingeAngleSensor()

    func readAngle() -> Double? {
        sensor.readAngle()
    }
}

struct HingeReadingFilter: Sendable {
    private let smoothingFactor: Double
    private var smoothedAngle: Double?

    init(smoothingFactor: Double = 0.35) {
        self.smoothingFactor = min(max(smoothingFactor, 0), 1)
    }

    mutating func process(_ rawAngle: Double?) -> Double? {
        guard let rawAngle, rawAngle.isFinite, (0...180).contains(rawAngle) else {
            reset()
            return nil
        }

        guard let previous = smoothedAngle else {
            smoothedAngle = rawAngle
            return rawAngle
        }

        let next = previous + smoothingFactor * (rawAngle - previous)
        smoothedAngle = next
        return next
    }

    mutating func reset() {
        smoothedAngle = nil
    }
}
