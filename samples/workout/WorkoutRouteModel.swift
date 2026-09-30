// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTracker/Views/Workout/Route/WorkoutRouteModel.swift

import Foundation

// MARK: - Stops

/// One stop on today's route: an exercise the session will visit.
///
/// The model is pure and `Equatable` so it can be unit-tested without
/// SwiftData, and diffed cheaply while the route is on screen.
struct WorkoutRouteStop: Identifiable, Equatable {
    /// How far along the route a stop has got.
    enum Status: Equatable {
        /// Finished, with nothing to celebrate.
        case done
        /// Finished on a new best, carrying the caller's result line
        /// ("3 SETS · TOP 102.5 × 8"). An empty result falls back to `detail`.
        case doneNewBest(result: String)
        /// The exercise being logged now.
        case now
        /// Still ahead on the route.
        case upcoming

        var isDone: Bool {
            switch self {
            case .done, .doneNewBest: true
            case .now, .upcoming: false
            }
        }

        var isNow: Bool {
            if case .now = self { return true }
            return false
        }

        var isUpcoming: Bool {
            if case .upcoming = self { return true }
            return false
        }

        /// The result line a new best shows in place of its target detail.
        var resultLine: String? {
            if case .doneNewBest(let result) = self, !result.isEmpty { return result }
            return nil
        }
    }

    /// The exercise log this stop stands for.
    let id: UUID
    /// The stop's slot on the route, 1-based. Slots stay put; rows move.
    let number: Int
    let name: String
    /// The target line, e.g. "3 × 8 · 100 KG". Empty when nothing is known.
    let detail: String
    let status: Status
}

// MARK: - Inputs

/// Everything `WorkoutRouteModel.make` needs, as plain values, so the route can
/// be built without SwiftData.
struct WorkoutRouteInput: Equatable {
    let id: UUID
    let name: String
    var targetSets: Int = 0
    var minReps: Int = 0
    var maxReps: Int = 0
    /// The load the session is aiming at, in kilograms, when it knows one.
    /// Missing loads are left out of the detail line rather than invented.
    var targetLoadKg: Double?
    /// Working sets already logged on this exercise.
    var loggedSetCount: Int = 0
    /// What a just-finished stop shows instead of its target line.
    var result: String?
}

// MARK: - Model

/// Today's route: the session's exercises in the order they will be visited.
struct WorkoutRouteModel: Equatable {
    let stops: [WorkoutRouteStop]

    /// The slot being logged, when the session still has one.
    var nowIndex: Int? {
        stops.firstIndex { $0.status.isNow }
    }

    var doneCount: Int {
        stops.filter { $0.status.isDone }.count
    }

    // MARK: Building

    /// Builds the route from plain values.
    ///
    /// - Parameter currentIndex: the slot being logged. `stops.count` marks a
    ///   finished route (every stop done), and `-1` marks one that has not
    ///   started (every stop upcoming).
    static func make(
        inputs: [WorkoutRouteInput],
        currentIndex: Int,
        newBestIDs: Set<UUID> = [],
        unitSystem: UnitSystem
    ) -> WorkoutRouteModel {
        let stops = inputs.enumerated().map { index, input in
            WorkoutRouteStop(
                id: input.id,
                number: index + 1,
                name: input.name,
                detail: detail(
                    targetSets: input.targetSets,
                    minReps: input.minReps,
                    maxReps: input.maxReps,
                    targetLoadKg: input.targetLoadKg,
                    unitSystem: unitSystem
                ),
                status: status(
                    index: index,
                    currentIndex: currentIndex,
                    isNewBest: newBestIDs.contains(input.id),
                    result: input.result
                )
            )
        }

        return WorkoutRouteModel(stops: stops)
    }

    /// "3 × 8 · 100 KG": target sets × target reps · target load.
    ///
    /// Parts that are missing are left out, never invented.
    static func detail(
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        targetLoadKg: Double?,
        unitSystem: UnitSystem
    ) -> String {
        var parts: [String] = []

        switch (targetSets > 0, repText(minReps: minReps, maxReps: maxReps)) {
        case (true, let reps?):
            parts.append("\(targetSets) × \(reps)")
        case (true, nil):
            parts.append("\(targetSets) \(targetSets == 1 ? "SET" : "SETS")")
        case (false, let reps?):
            parts.append("\(reps) \(reps == "1" ? "REP" : "REPS")")
        case (false, nil):
            break
        }

        if let targetLoadKg {
            let value = SummitWeightFormatting.displayString(targetLoadKg, unitSystem: unitSystem)
            let unit = SummitWeightFormatting.unitSymbol(unitSystem).uppercased()
            parts.append("\(value) \(unit)")
        }

        return parts.joined(separator: PeaklineText.metadataSeparator)
    }

    // MARK: Going here instead

    /// Sends the chosen exercise to the slot being logged: it starts now, and
    /// the exercise that was running waits as next. Everything else keeps its
    /// relative order, and the slot numbers stay where they are.
    static func goingHereInstead(_ ids: [UUID], currentIndex: Int, chosenIndex: Int) -> [UUID] {
        guard
            ids.indices.contains(currentIndex),
            ids.indices.contains(chosenIndex),
            chosenIndex > currentIndex
        else { return ids }

        var reordered = ids
        let chosen = reordered.remove(at: chosenIndex)
        reordered.insert(chosen, at: currentIndex)
        return reordered
    }

    /// Puts `inputs` into the given id order. Ids the caller did not mention
    /// keep their original relative order at the end of the route.
    static func reorder(_ inputs: [WorkoutRouteInput], by ids: [UUID]) -> [WorkoutRouteInput] {
        let byID = Dictionary(inputs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reordered = ids.compactMap { byID[$0] }
        let placed = Set(reordered.map(\.id))
        reordered.append(contentsOf: inputs.filter { !placed.contains($0.id) })
        return reordered
    }

    // MARK: Helpers

    private static func status(
        index: Int,
        currentIndex: Int,
        isNewBest: Bool,
        result: String?
    ) -> WorkoutRouteStop.Status {
        if index < currentIndex {
            return isNewBest ? .doneNewBest(result: result ?? "") : .done
        }

        return index == currentIndex ? .now : .upcoming
    }

    private static func repText(minReps: Int, maxReps: Int) -> String? {
        if minReps > 0, maxReps > 0 {
            return minReps == maxReps ? "\(minReps)" : "\(minReps)–\(maxReps)"
        }

        if maxReps > 0 { return "\(maxReps)" }
        if minReps > 0 { return "\(minReps)" }
        return nil
    }
}

// MARK: - Resume position

/// What the resume choice needs to know about one exercise, as plain values.
struct WorkoutResumeCandidate: Equatable {
    let id: UUID
    /// Working sets the exercise plans (its target, or more when extra sets exist).
    let plannedSetCount: Int
    /// Working sets already recorded on it.
    let loggedSetCount: Int

    var hasRemainingSets: Bool { loggedSetCount < plannedSetCount }
}

extension WorkoutRouteModel {
    /// The slot a session opens on when the logger is reopened.
    ///
    /// 1. The exercise the user was on, when it still exists in the session.
    /// 2. Otherwise the first exercise in route order that still has planned sets
    ///    to log. A session with nothing logged yet starts at the first exercise.
    /// 3. Otherwise (everything logged) the last exercise.
    ///
    /// `candidates` are in route order. An empty route resolves to slot 0.
    static func resumeIndex(in candidates: [WorkoutResumeCandidate], remembered: UUID?) -> Int {
        guard !candidates.isEmpty else { return 0 }

        if let remembered, let index = candidates.firstIndex(where: { $0.id == remembered }) {
            return index
        }

        guard candidates.contains(where: { $0.loggedSetCount > 0 }) else { return 0 }

        return candidates.firstIndex(where: \.hasRemainingSets) ?? candidates.count - 1
    }
}

/// How far through an exercise's sets a session is, as plain values.
///
/// "Logged" is a stored fact: Log set writes `SetLog.completed` (and saves) at
/// the moment the set is recorded, so these rules give the same answer on a
/// fresh launch as they did on screen before the app was closed.
enum WorkoutSetProgress {
    /// The set the exercise view selects when it opens or moves on: the first
    /// working set not yet logged, else the next planned set that has no row yet,
    /// else (every planned set logged) the last one.
    ///
    /// - Parameters:
    ///   - logged: one flag per stored working set, in set order.
    ///   - targetCount: the exercise's planned working sets (at least the number
    ///     of stored rows, and at least 1).
    static func currentSetIndex(logged: [Bool], targetCount: Int) -> Int {
        if let firstUnlogged = logged.firstIndex(of: false) { return firstUnlogged }
        // Extra sets added beyond the plan are still part of the exercise, so the
        // plan can never be smaller than the stored rows.
        let plannedCount = max(targetCount, logged.count, 1)
        return min(logged.count, plannedCount - 1)
    }

    /// The resume candidate for one exercise: a set counts as logged only when it
    /// was recorded. A row that exists because its weight or reps were edited, or
    /// because Add set created it, is planned work, not progress.
    ///
    /// - Parameter workingSetsLogged: one flag per stored working set.
    static func resumeCandidate(
        id: UUID,
        targetSets: Int,
        workingSetsLogged: [Bool]
    ) -> WorkoutResumeCandidate {
        WorkoutResumeCandidate(
            id: id,
            plannedSetCount: max(targetSets, workingSetsLogged.count),
            loggedSetCount: workingSetsLogged.filter { $0 }.count
        )
    }
}

/// Remembers which exercise each in-progress session was on, so reopening the
/// logger returns to it.
///
/// This lives in a small Application Support file rather than on `WorkoutSession`
/// (a stored property would need a schema version, backup/restore handling and a
/// migration for a hint that is only useful on this device) and rather than
/// `UserDefaults` (`RootTabView` reacts to every `UserDefaults` change with
/// readiness and sleep refresh work). A missing or unreadable file only means the
/// logger falls back to `WorkoutRouteModel.resumeIndex`.
final class WorkoutResumePositionStore: @unchecked Sendable {
    static let shared = WorkoutResumePositionStore()

    private struct Entry: Codable {
        var exerciseLogID: UUID
        var updatedAt: Date
    }

    private let fileURL: URL
    private let maxEntries: Int
    private let lock = NSLock()
    /// Keyed by session id string. Loaded on first use, then kept in memory.
    private var entries: [String: Entry]?

    init(fileURL: URL? = nil, maxEntries: Int = 16) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.maxEntries = maxEntries
    }

    func exerciseLogID(for sessionID: UUID) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        return loadedEntries()[sessionID.uuidString]?.exerciseLogID
    }

    /// Writes only when the remembered exercise changes.
    func remember(exerciseLogID: UUID, for sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var current = loadedEntries()
        let key = sessionID.uuidString
        guard current[key]?.exerciseLogID != exerciseLogID else { return }

        current[key] = Entry(exerciseLogID: exerciseLogID, updatedAt: Date())
        // Sessions removed by a path that never reaches `forget` (a restore, a
        // reset) must not accumulate: keep only the most recently updated.
        if current.count > maxEntries {
            let stale = current
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .dropFirst(maxEntries)
                .map(\.key)
            for staleKey in stale { current.removeValue(forKey: staleKey) }
        }
        persist(current)
    }

    /// A finished or discarded session has no position to return to.
    func forget(sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var current = loadedEntries()
        guard current.removeValue(forKey: sessionID.uuidString) != nil else { return }
        persist(current)
    }

    // Callers hold `lock`.
    private func loadedEntries() -> [String: Entry] {
        if let entries { return entries }
        let loaded: [String: Entry]
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            loaded = decoded
        } else {
            loaded = [:]
        }
        entries = loaded
        return loaded
    }

    // Callers hold `lock`. Best effort: a failed write leaves the in-memory copy
    // in place and the next launch falls back to the derived position.
    private func persist(_ updated: [String: Entry]) {
        entries = updated
        do {
            try LocalFileProtection.write(try JSONEncoder().encode(updated), to: fileURL)
        } catch {
            // Nothing to surface: the hint is optional.
        }
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Peakline", isDirectory: true)
            .appendingPathComponent("WorkoutResumePosition.json")
    }
}
