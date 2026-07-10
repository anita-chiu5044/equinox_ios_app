import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

/// Reads last night's sleep (and steps) from HealthKit to suggest today's
/// energy level — the Energy-aware Scheduling signal from the proposal.
/// Read-only; data never leaves the device (privacy feature #5).
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    struct EnergySuggestion: Equatable {
        let energyKey: String   // great | ok | tired | drained
        let sleepHours: Double
    }

    struct HealthSnapshot: Equatable {
        let lastNightSleepHours: Double?
        let sevenDaySleepAverage: Double?
        let todaySteps: Int?
        let cyclePhase: String?
        let cycleImpact: String?
        let status: String
        let recommendation: String
    }

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Asks for read access to sleep + steps. Returns false when HealthKit
    /// is unavailable or the user declines.
    func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable else {
            return false
        }
        var types: Set<HKObjectType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.stepCount),
        ]
        if let menstrualFlow = HKObjectType.categoryType(forIdentifier: .menstrualFlow) {
            types.insert(menstrualFlow)
        }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Suggests an energy level from last night's sleep. Nil when there is
    /// no sleep data (e.g. fresh simulator) or HealthKit is unavailable.
    func suggestedEnergy() async -> EnergySuggestion? {
        guard let hours = await lastNightSleepHours(), hours > 0 else {
            return nil
        }

        let key: String = switch hours {
        case 7.5...: "great"
        case 6.5..<7.5: "ok"
        case 5.0..<6.5: "tired"
        default: "drained"
        }
        return EnergySuggestion(energyKey: key, sleepHours: (hours * 10).rounded() / 10)
    }

    func healthSnapshot() async -> HealthSnapshot {
        async let lastNight = lastNightSleepHours()
        async let average = recentSleepAverage()
        async let steps = todayStepCount()
        async let cycle = todayCycleSignal()
        let cycleSignal = await cycle
        return Self.analyze(
            lastNightSleepHours: await lastNight,
            sevenDaySleepAverage: await average,
            todaySteps: await steps,
            cyclePhase: cycleSignal.phase,
            cycleImpact: cycleSignal.impact
        )
    }

    static func analyze(
        lastNightSleepHours: Double?,
        sevenDaySleepAverage: Double?,
        todaySteps: Int?,
        cyclePhase: String? = nil,
        cycleImpact: String? = nil
    ) -> HealthSnapshot {
        let sleep = lastNightSleepHours ?? sevenDaySleepAverage
        var status: String
        var recommendation: String

        switch sleep {
        case .some(let hours) where hours < 6:
            status = "Recovery needed"
            recommendation = "Keep demanding work short today and leave room for recovery."
        case .some(let hours) where hours >= 7.5:
            status = "Well recovered"
            recommendation = "Your sleep supports a deeper focus block today."
        case .some:
            status = "Steady readiness"
            recommendation = "Use a balanced mix of focused work and lighter review."
        case .none:
            status = "Waiting for health data"
            recommendation = "Recent sleep and step data will make this analysis more personal."
        }

        if cycleImpact == "heavy" || cycleImpact == "medium" {
            status = "Recovery window"
            recommendation = "Cycle data suggests a gentler load today. Equinox will lower capacity slightly before scheduling."
        } else if cyclePhase == "period" {
            recommendation = "Cycle data is included today, so the plan can stay lighter if your body needs it."
        }

        return HealthSnapshot(
            lastNightSleepHours: lastNightSleepHours,
            sevenDaySleepAverage: sevenDaySleepAverage,
            todaySteps: todaySteps,
            cyclePhase: cyclePhase,
            cycleImpact: cycleImpact,
            status: status,
            recommendation: recommendation
        )
    }

    static func mergedDuration(of intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else {
            return 0
        }

        var total: TimeInterval = 0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                total += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }
        return total + current.end.timeIntervalSince(current.start)
    }

    #if DEBUG
    /// Simulator helper: writes sleep and steps so health analysis has real
    /// HealthKit data on a fresh simulator.
    /// Requests write access on demand. DEBUG builds only.
    func seedSampleSleepData() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable else {
            return false
        }
        let sleepType = HKCategoryType(.sleepAnalysis)
        let stepType = HKQuantityType(.stepCount)
        do {
            try await store.requestAuthorization(
                toShare: [sleepType, stepType],
                read: [sleepType, stepType]
            )
            let todayStart = Calendar.current.startOfDay(for: .now)
            let sleepSample = HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: todayStart.addingTimeInterval(-45 * 60),      // 23:15
                end: todayStart.addingTimeInterval(6.75 * 3600),     // 06:45
                metadata: ["EquinoxDebugSeed": true]
            )
            let stepSample = HKQuantitySample(
                type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: 4_200),
                start: todayStart.addingTimeInterval(8 * 3600),
                end: todayStart.addingTimeInterval(9 * 3600),
                metadata: ["EquinoxDebugSeed": true]
            )

            let cleanupStart = todayStart.addingTimeInterval(-2 * 3600)
            let cleanupEnd = todayStart.addingTimeInterval(12 * 3600)
            let cleanupPredicate = HKQuery.predicateForSamples(
                withStart: cleanupStart,
                end: cleanupEnd
            )
            async let oldSleep = samples(
                type: sleepType,
                predicate: cleanupPredicate
            )
            async let oldSteps = samples(
                type: stepType,
                predicate: cleanupPredicate
            )
            let (sleepSamples, stepSamples) = await (oldSleep, oldSteps)
            let bundleIdentifier = Bundle.main.bundleIdentifier
            let priorSeeds = (sleepSamples + stepSamples).filter {
                $0.sourceRevision.source.bundleIdentifier == bundleIdentifier
            }
            if !priorSeeds.isEmpty {
                try await store.delete(priorSeeds)
            }
            try await store.save([sleepSample, stepSample])
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
    #endif

    /// Total asleep time between yesterday 18:00 and now.
    func lastNightSleepHours() async -> Double? {
        #if canImport(HealthKit)
        guard isAvailable else {
            return nil
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(byAdding: .hour, value: -6, to: todayStart) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: []
        )

        guard let samples = try? await descriptor.result(for: store) else {
            return nil
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        let seconds = Self.mergedDuration(of: samples
            .filter { asleepValues.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) })

        return seconds > 0 ? seconds / 3600 : nil
        #else
        return nil
        #endif
    }

    func recentSleepAverage(days: Int = 7) async -> Double? {
        #if canImport(HealthKit)
        guard isAvailable else {
            return nil
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(byAdding: .day, value: -days, to: todayStart) else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else {
            return nil
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let grouped = Dictionary(grouping: samples.filter { asleepValues.contains($0.value) }) {
            calendar.startOfDay(for: $0.endDate)
        }
        let nightlyHours = grouped.values.map { night in
            Self.mergedDuration(of: night.map { (start: $0.startDate, end: $0.endDate) }) / 3600
        }.filter { $0 > 0 }

        guard !nightlyHours.isEmpty else {
            return nil
        }
        let average = nightlyHours.reduce(0, +) / Double(nightlyHours.count)
        return (average * 10).rounded() / 10
        #else
        return nil
        #endif
    }

    func todayStepCount() async -> Int? {
        #if canImport(HealthKit)
        guard isAvailable else {
            return nil
        }
        let type = HKQuantityType(.stepCount)
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        guard let statistics = try? await descriptor.result(for: store),
              let sum = statistics.sumQuantity() else {
            return nil
        }
        return Int(sum.doubleValue(for: .count()).rounded())
        #else
        return nil
        #endif
    }

    func todayCycleSignal() async -> (phase: String?, impact: String?) {
        #if canImport(HealthKit)
        guard isAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .menstrualFlow) else {
            return (nil, nil)
        }
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return (nil, nil)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store),
              !samples.isEmpty else {
            return (nil, nil)
        }
        return ("period", Self.menstrualImpact(from: samples.map(\.value)))
        #else
        return (nil, nil)
        #endif
    }


    #if canImport(HealthKit)
    private static func menstrualImpact(from values: [Int]) -> String {
        if values.contains(HKCategoryValueMenstrualFlow.heavy.rawValue) {
            return "heavy"
        }
        if values.contains(HKCategoryValueMenstrualFlow.medium.rawValue) {
            return "medium"
        }
        if values.contains(HKCategoryValueMenstrualFlow.light.rawValue) {
            return "light"
        }
        return "medium"
    }

    private func samples(
        type: HKSampleType,
        predicate: NSPredicate
    ) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }
    #endif
}
