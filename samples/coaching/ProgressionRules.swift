// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTracker/Services/ProgressionRules.swift

import Foundation

struct ExerciseLoadContext: Hashable, Sendable {
    let equipment: EquipmentType
    let primaryMuscle: MuscleGroup
    let isCompound: Bool
}

struct ProgressionFeedbackSignal: Hashable, Sendable {
    let date: Date
    let tags: [CoachRecommendationFeedbackTag]
}

struct ProgressionTrend: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case rising, flat, falling, insufficient }
    let direction: Direction
    let slopePerSession: Double
    let percentChange: Double
}

enum StallStep: Int, CaseIterable, Sendable {
    case repeatLoad = 1, backOffSet, shiftRepRange, swapVariation, deload
}

enum ProgressionRules {
    /// Smallest load jump the equipment can realistically make.
    static func loadIncrement(for context: ExerciseLoadContext?) -> Double {
        guard let context else { return 2.5 }

        switch context.equipment {
        case .bodyweight:
            return 0
        case .dumbbell:
            return 2.0
        case .kettlebell:
            return 4.0
        case .machine, .cable, .other:
            return 2.5
        case .barbell, .smithMachine:
            guard context.isCompound else { return 2.5 }
            switch context.primaryMuscle {
            case .quads, .hamstrings, .glutes, .fullBody:
                return 5.0
            default:
                return 2.5
            }
        }
    }

    /// The group a lift belongs to for load jumps, matching the branches of `loadIncrement`.
    /// Nil for bodyweight work, which has no load jump.
    static func incrementGroupName(for context: ExerciseLoadContext) -> String? {
        switch context.equipment {
        case .bodyweight:
            return nil
        case .dumbbell:
            return "dumbbells"
        case .kettlebell:
            return "kettlebells"
        case .machine, .cable, .other:
            return "machine and cable lifts"
        case .barbell, .smithMachine:
            guard context.isCompound else { return "other barbell lifts" }
            switch context.primaryMuscle {
            case .quads, .hamstrings, .glutes, .fullBody:
                return "lower-body barbell compounds"
            default:
                return "other barbell lifts"
            }
        }
    }

    /// The real load jumps for the lifts on screen, generated from `loadIncrement` so the
    /// copy cannot drift from the rule. One clause per group, in the order the lifts appear.
    static func incrementSummary(for contexts: [ExerciseLoadContext]) -> String {
        var clauses: [String] = []
        var seenGroups = Set<String>()
        var hasBodyweight = false

        for context in contexts {
            guard let group = incrementGroupName(for: context) else {
                hasBodyweight = true
                continue
            }
            guard seenGroups.insert(group).inserted else { continue }
            let increment = loadIncrement(for: context)
            clauses.append("\(group) go up \(incrementText(increment)) kg")
        }

        if clauses.isEmpty {
            return hasBodyweight
                ? "Bodyweight work adds reps, not load."
                : "Loads go up \(incrementText(loadIncrement(for: nil))) kg at a time."
        }

        var sentence = clauses.joined(separator: "; ")
        sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
        sentence += "."
        if hasBodyweight {
            sentence += " Bodyweight work adds reps, not load."
        }
        return sentence
    }

    static func incrementText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }

    /// Light, isolation-style movements get more value from another rep than another plate.
    static func prefersRepsFirst(_ context: ExerciseLoadContext?) -> Bool {
        guard let context, !context.isCompound else { return false }
        switch context.equipment {
        case .dumbbell, .cable, .machine:
            return true
        default:
            return false
        }
    }

    /// Epley estimate. Only meaningful inside a sane rep range.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= 12 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    static func trend(_ values: [Double]) -> ProgressionTrend {
        guard values.count >= 4 else {
            return ProgressionTrend(direction: .insufficient, slopePerSession: 0, percentChange: 0)
        }

        let count = values.count
        let meanIndex = Double(count - 1) / 2
        let meanValue = values.reduce(0, +) / Double(count)

        var covariance = 0.0
        var variance = 0.0
        for (index, value) in values.enumerated() {
            let indexDelta = Double(index) - meanIndex
            covariance += indexDelta * (value - meanValue)
            variance += indexDelta * indexDelta
        }

        let slope = variance == 0 ? 0 : covariance / variance
        let percentChange = meanValue == 0 ? 0 : slope * Double(count - 1) / meanValue * 100

        let direction: ProgressionTrend.Direction
        if percentChange > 1.5 {
            direction = .rising
        } else if percentChange < -1.5 {
            direction = .falling
        } else {
            direction = .flat
        }

        return ProgressionTrend(direction: direction, slopePerSession: slope, percentChange: percentChange)
    }

    /// Escalating response to consecutive appearances that failed to progress.
    static func stallStep(flatExposures: Int) -> StallStep? {
        switch flatExposures {
        case ..<3:
            return nil
        case 3...4:
            return .repeatLoad
        case 5...6:
            return .backOffSet
        case 7...8:
            return .shiftRepRange
        case 9...10:
            return .swapVariation
        default:
            return .deload
        }
    }

    /// 90% of the working weight, rounded down to the smallest available jump.
    static func deloadWeight(_ weight: Double, increment: Double) -> Double {
        guard increment > 0 else { return weight }
        let target = weight * 0.9
        return (target / increment).rounded(.down) * increment
    }

    /// A planned step down: `fraction` of the weight, rounded to the nearest jump the
    /// equipment makes, and always at least one jump lighter. 80 kg at 0.9 on 2.5 kg
    /// jumps is 72.5. Unchanged for bodyweight work or a load that is already one jump.
    static func reducedLoad(_ weight: Double, fraction: Double, increment: Double) -> Double {
        guard increment > 0, weight > increment else { return weight }
        var rounded = (weight * fraction / increment).rounded() * increment
        if rounded >= weight { rounded = weight - increment }
        return max(increment, rounded)
    }

    static func progressionBias(signals: [ProgressionFeedbackSignal], now: Date) -> Double {
        let window: TimeInterval = 60 * 86_400

        var aggressive = 0
        var conservative = 0
        for signal in signals {
            let age = now.timeIntervalSince(signal.date)
            guard age >= 0, age <= window else { continue }

            if signal.tags.contains(.tooAggressive) || signal.tags.contains(.preferredRecovery) {
                aggressive += 1
            }
            if signal.tags.contains(.tooConservative) {
                conservative += 1
            }
        }

        return min(1.0, max(-1.0, Double(conservative - aggressive) * 0.5))
    }

    /// Push calls that must have been judged before the trip log moves the gate.
    static let tripLogMinimumJudgedPushCalls = 4
    static let tripLogTightenBias = -0.5
    static let tripLogLoosenBias = 0.25

    /// How the Coach's own record of push calls moves the RPE gate. With at
    /// least four judged, under half holding up tightens the gate by 0.5 and
    /// four in five or better loosens it by 0.25. Otherwise no change.
    static func tripLogBias(judgedPushCalls: Int, heldUp: Int) -> Double {
        guard judgedPushCalls >= tripLogMinimumJudgedPushCalls else { return 0 }
        let rate = Double(heldUp) / Double(judgedPushCalls)
        if rate < 0.5 { return tripLogTightenBias }
        if rate >= 0.8 { return tripLogLoosenBias }
        return 0
    }

    /// Feedback tags and the trip log together, capped at one either way.
    static func combinedBias(feedback: Double, tripLog: Double) -> Double {
        min(1.0, max(-1.0, feedback + tripLog))
    }

    static func increaseLoadMaxRPE(bias: Double) -> Double {
        min(9.5, max(7.5, 8.5 + bias))
    }
}

/// Plain-value view of the exercise metadata the progression rules need, so a
/// value snapshot and a live SwiftData model produce the same load context.
protocol ExerciseSnapshotLike {
    var exerciseId: UUID { get }
    var loadEquipment: EquipmentType? { get }
    var primaryMuscle: MuscleGroup? { get }
    var isCompound: Bool { get }
    var exerciseName: String { get }
    var movementPatternValue: MovementPattern? { get }
    var isArchivedExercise: Bool { get }
}

extension ExerciseSnapshotLike {
    var exerciseName: String { "" }
    var movementPatternValue: MovementPattern? { nil }
    var isArchivedExercise: Bool { false }
}

extension Exercise: ExerciseSnapshotLike {
    var exerciseId: UUID { id }
    var loadEquipment: EquipmentType? { equipment }
    var primaryMuscle: MuscleGroup? { primaryMuscleGroup }
    var exerciseName: String { name }
    var movementPatternValue: MovementPattern? { movementPattern }
    var isArchivedExercise: Bool { isArchived }
}

extension WorkoutPreviewExerciseOption: ExerciseSnapshotLike {
    var exerciseId: UUID { id }
    var loadEquipment: EquipmentType? { equipment }
    var primaryMuscle: MuscleGroup? { primaryMuscleGroup }
    var exerciseName: String { name }
    var movementPatternValue: MovementPattern? { movementPattern }
}

extension ProgressionFeedbackSignal {
    /// Lifts a stored Coach feedback record into the pure signal the rules read.
    /// Only call this on the actor that owns the model.
    init(_ feedback: CoachRecommendationFeedback) {
        self.init(date: feedback.createdAt, tags: feedback.tags)
    }
}

/// One shared progression input set for every target suggestion path: the
/// per-exercise load context plus the feedback bias. Prepared/warm-start paths
/// and live paths build this from the same data so targets agree.
struct ProgressionInputs: Hashable, Sendable {
    let contexts: [UUID: ExerciseLoadContext]
    let bias: Double
    /// The deload block running today, when one is. Every target applies it.
    var deload: DeloadTargetContext? = nil
    /// Every unarchived lift's pattern, muscle and equipment, so a stalled lift can be
    /// offered a same-pattern swap. Read only when a lift reaches that rung.
    var swapPool: [ProgressionSwapEntry] = []

    static let neutral = ProgressionInputs(contexts: [:], bias: 0)

    /// The trip-log part of the gate bias every caller passes, so Coach, Today,
    /// startup, the Workout tab and the weekly review agree on the same targets.
    static func currentTripLogBias(now: Date = .now) -> Double {
        CoachTripLogStore.shared.calibrationBias(now: now)
    }

    static func make(
        exercises: [ExerciseSnapshotLike],
        feedback: [ProgressionFeedbackSignal],
        tripLogBias: Double = 0,
        deloadBlocks: [SavedCoachDeloadBlock] = [],
        now: Date
    ) -> ProgressionInputs {
        var contexts: [UUID: ExerciseLoadContext] = [:]
        var swapPool: [ProgressionSwapEntry] = []
        contexts.reserveCapacity(exercises.count)
        swapPool.reserveCapacity(exercises.count)
        for exercise in exercises {
            guard let equipment = exercise.loadEquipment,
                  let primaryMuscle = exercise.primaryMuscle else { continue }
            contexts[exercise.exerciseId] = ExerciseLoadContext(
                equipment: equipment,
                primaryMuscle: primaryMuscle,
                isCompound: exercise.isCompound
            )
            if let pattern = exercise.movementPatternValue, !exercise.exerciseName.isEmpty {
                swapPool.append(ProgressionSwapEntry(
                    id: exercise.exerciseId,
                    name: exercise.exerciseName,
                    pattern: pattern,
                    primaryMuscle: primaryMuscle,
                    equipment: equipment,
                    isArchived: exercise.isArchivedExercise
                ))
            }
        }
        return ProgressionInputs(
            contexts: contexts,
            bias: ProgressionRules.combinedBias(
                feedback: ProgressionRules.progressionBias(signals: feedback, now: now),
                tripLog: tripLogBias
            ),
            deload: DeloadTargetContext(blocks: deloadBlocks, now: now),
            swapPool: swapPool
        )
    }

    func loadContext(for exerciseId: UUID) -> ExerciseLoadContext? {
        contexts[exerciseId]
    }
}
