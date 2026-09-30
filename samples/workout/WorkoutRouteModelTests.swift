// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTrackerTests/WorkoutRouteModelTests.swift

import XCTest
@testable import GymTracker

final class WorkoutRouteModelTests: XCTestCase {

    // MARK: - Detail line

    func testDetailShowsTargetSetsRepsAndLoad() {
        XCTAssertEqual(
            detail(targetSets: 3, minReps: 8, maxReps: 8, loadKg: 100, unitSystem: .metric),
            "3 × 8 · 100 KG"
        )
    }

    func testDetailShowsPoundsWhenTheProfileIsImperial() {
        // 100 lb, stored the way the app stores loads.
        let loadKg = SummitWeightFormatting.kilograms(100, unitSystem: .imperial)

        XCTAssertEqual(
            detail(targetSets: 2, minReps: 10, maxReps: 10, loadKg: loadKg, unitSystem: .imperial),
            "2 × 10 · 100 LB"
        )
    }

    func testDetailKeepsPartialLoads() {
        XCTAssertTrue(
            detail(targetSets: 3, minReps: 5, maxReps: 5, loadKg: 102.5, unitSystem: .metric)
                .hasPrefix("3 × 5 · 102")
        )
    }

    func testDetailOmitsAMissingLoad() {
        XCTAssertEqual(
            detail(targetSets: 3, minReps: 8, maxReps: 8, loadKg: nil, unitSystem: .metric),
            "3 × 8"
        )

        XCTAssertEqual(
            detail(targetSets: 0, minReps: 0, maxReps: 0, loadKg: 60, unitSystem: .metric),
            "60 KG"
        )
    }

    func testDetailKeepsARepRangeAndNeverInventsParts() {
        XCTAssertEqual(
            detail(targetSets: 4, minReps: 8, maxReps: 12, loadKg: nil, unitSystem: .metric),
            "4 × 8–12"
        )

        XCTAssertEqual(
            detail(targetSets: 3, minReps: 0, maxReps: 0, loadKg: nil, unitSystem: .metric),
            "3 SETS"
        )

        XCTAssertEqual(
            detail(targetSets: 0, minReps: 0, maxReps: 0, loadKg: nil, unitSystem: .metric),
            ""
        )
    }

    // MARK: - Statuses

    func testMakeMarksDoneNowAndUpcomingStops() {
        let ids = makeIDs(count: 4)
        let model = WorkoutRouteModel.make(
            inputs: makeInputs(ids: ids),
            currentIndex: 2,
            newBestIDs: [ids[1]],
            unitSystem: .metric
        )

        XCTAssertEqual(model.stops.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(
            model.stops.map(\.status),
            [.done, .doneNewBest(result: ""), .now, .upcoming]
        )
        XCTAssertEqual(model.stops.map(\.name), ["Exercise 1", "Exercise 2", "Exercise 3", "Exercise 4"])
        XCTAssertEqual(model.nowIndex, 2)
        XCTAssertEqual(model.doneCount, 2)
    }

    func testDoneNewBestCarriesTheCallersResultLine() {
        let ids = makeIDs(count: 3)
        var inputs = makeInputs(ids: ids, names: ["Hamstring curl", "Romanian deadlift", "Leg press"])
        inputs[1].result = "3 SETS · TOP 102.5 × 8"

        let model = WorkoutRouteModel.make(
            inputs: inputs,
            currentIndex: 2,
            newBestIDs: [ids[1]],
            unitSystem: .metric
        )

        XCTAssertEqual(model.stops[1].status, .doneNewBest(result: "3 SETS · TOP 102.5 × 8"))
        XCTAssertEqual(model.stops[1].status.resultLine, "3 SETS · TOP 102.5 × 8")
        // The target line is still there for anything that does not want the result.
        XCTAssertEqual(model.stops[1].detail, "3 × 8 · 100 KG")
        // A plain done stop carries no result line.
        XCTAssertNil(model.stops[0].status.resultLine)
    }

    func testMakeMarksEveryStopUpcomingBeforeTheRouteStartsAndDoneWhenItEnds() {
        let ids = makeIDs(count: 3)
        let inputs = makeInputs(ids: ids)

        let notStarted = WorkoutRouteModel.make(inputs: inputs, currentIndex: -1, unitSystem: .metric)
        XCTAssertEqual(notStarted.stops.map(\.status), [.upcoming, .upcoming, .upcoming])
        XCTAssertNil(notStarted.nowIndex)
        XCTAssertEqual(notStarted.doneCount, 0)

        let finished = WorkoutRouteModel.make(inputs: inputs, currentIndex: 3, unitSystem: .metric)
        XCTAssertEqual(finished.stops.map(\.status), [.done, .done, .done])
        XCTAssertEqual(finished.doneCount, 3)
    }

    // MARK: - goingHereInstead

    func testGoingHereInsteadPutsTheChosenStopInTheCurrentSlot() {
        let ids = makeIDs(count: 7)

        XCTAssertEqual(
            WorkoutRouteModel.goingHereInstead(ids, currentIndex: 2, chosenIndex: 5),
            [ids[0], ids[1], ids[5], ids[2], ids[3], ids[4], ids[6]]
        )
    }

    func testGoingHereInsteadFromSeveralSlotsAheadKeepsTheRelativeOrder() {
        let ids = makeIDs(count: 6)

        // Two slots ahead: the running stop simply waits as next.
        XCTAssertEqual(
            WorkoutRouteModel.goingHereInstead(ids, currentIndex: 1, chosenIndex: 3),
            [ids[0], ids[3], ids[1], ids[2], ids[4], ids[5]]
        )

        // The last stop of the route.
        XCTAssertEqual(
            WorkoutRouteModel.goingHereInstead(ids, currentIndex: 0, chosenIndex: 5),
            [ids[5], ids[0], ids[1], ids[2], ids[3], ids[4]]
        )
    }

    func testGoingHereInsteadIgnoresStopsThatAreNotAhead() {
        let ids = makeIDs(count: 4)

        XCTAssertEqual(WorkoutRouteModel.goingHereInstead(ids, currentIndex: 2, chosenIndex: 2), ids)
        XCTAssertEqual(WorkoutRouteModel.goingHereInstead(ids, currentIndex: 2, chosenIndex: 0), ids)
        XCTAssertEqual(WorkoutRouteModel.goingHereInstead(ids, currentIndex: 0, chosenIndex: 9), ids)
    }

    // MARK: - Rows move, slots stay

    func testGoingHereInsteadMovesTheRowsButKeepsTheSlotNumbers() {
        let names = [
            "Hamstring curl",
            "Hip adduction",
            "Romanian deadlift",
            "Leg press",
            "Quad extension",
            "Hip thrust",
            "Calf raise"
        ]
        let inputs = makeInputs(ids: makeIDs(count: names.count), names: names)
        let ids = inputs.map(\.id)

        let moved = WorkoutRouteModel.goingHereInstead(ids, currentIndex: 2, chosenIndex: 5)
        let model = WorkoutRouteModel.make(
            inputs: WorkoutRouteModel.reorder(inputs, by: moved),
            currentIndex: 2,
            unitSystem: .metric
        )

        XCTAssertEqual(model.stops.map(\.number), Array(1...7))
        XCTAssertEqual(
            model.stops.map(\.name),
            [
                "Hamstring curl",
                "Hip adduction",
                "Hip thrust",
                "Romanian deadlift",
                "Leg press",
                "Quad extension",
                "Calf raise"
            ]
        )
        XCTAssertEqual(
            model.stops.map(\.status),
            [.done, .done, .now, .upcoming, .upcoming, .upcoming, .upcoming]
        )
        // The chosen stop brings its own target line with it.
        XCTAssertEqual(model.stops[2].detail, "3 × 8 · 100 KG")
    }

    func testReorderingIgnoresIDsThatAreNotOnTheRoute() {
        let ids = makeIDs(count: 3)
        let inputs = makeInputs(ids: ids)

        let reordered = WorkoutRouteModel.reorder(inputs, by: [ids[2], UUID(), ids[0]])

        XCTAssertEqual(reordered.map(\.id), [ids[2], ids[0], ids[1]])
    }

    // MARK: - Resume position

    func testResumeIndexReturnsTheRememberedExerciseWhenItStillExists() {
        let ids = makeIDs(count: 4)
        let candidates = makeResumeCandidates(ids: ids, logged: [3, 0, 0, 0])

        // The remembered exercise wins over an earlier one with sets left.
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: ids[2]), 2)
        // Even when it is finished.
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: ids[0]), 0)
    }

    func testResumeIndexFallsToTheFirstExerciseWithSetsLeftWhenNothingIsRemembered() {
        let ids = makeIDs(count: 4)
        let candidates = makeResumeCandidates(ids: ids, logged: [3, 3, 1, 0])

        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: nil), 2)
    }

    func testResumeIndexFallsBackWhenTheRememberedExerciseIsGone() {
        let ids = makeIDs(count: 3)
        let candidates = makeResumeCandidates(ids: ids, logged: [3, 2, 0])

        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: UUID()), 1)
    }

    func testResumeIndexFallsToTheLastExerciseWhenEverythingIsLogged() {
        let ids = makeIDs(count: 3)
        let candidates = makeResumeCandidates(ids: ids, logged: [3, 3, 3])

        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: nil), 2)
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: UUID()), 2)
    }

    func testResumeIndexStartsAtTheFirstExerciseForANewWorkout() {
        let ids = makeIDs(count: 3)
        var candidates = makeResumeCandidates(ids: ids, logged: [0, 0, 0])

        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: nil), 0)

        // An exercise that plans no sets must not push a fresh workout past it.
        candidates[0] = WorkoutResumeCandidate(id: ids[0], plannedSetCount: 0, loggedSetCount: 0)
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: candidates, remembered: nil), 0)

        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: [], remembered: nil), 0)
    }

    // MARK: - Logged-set progress

    func testCurrentSetIsTheFirstUnloggedSet() {
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [], targetCount: 3), 0)
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [false, false, false], targetCount: 3), 0)
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true, false, false], targetCount: 3), 1)
        // A hole (an earlier set with no record) is where the user resumes.
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true, false, true], targetCount: 3), 1)
    }

    func testCurrentSetIsTheNextPlannedSetWhenEveryStoredRowIsLogged() {
        // Two rows stored and logged, three planned: the third has no row yet.
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true, true], targetCount: 3), 2)
    }

    func testCurrentSetIsTheLastSetWhenEverythingPlannedIsLogged() {
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true, true, true], targetCount: 3), 2)
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true], targetCount: 1), 0)
        // More rows than the target still points at the last stored row.
        XCTAssertEqual(WorkoutSetProgress.currentSetIndex(logged: [true, true, true], targetCount: 2), 2)
    }

    func testResumeCandidateCountsOnlyLoggedRowsNotEditedOnes() {
        let id = UUID()
        // Set 2 has a row (its weight was edited) but was never logged.
        let candidate = WorkoutSetProgress.resumeCandidate(
            id: id, targetSets: 3, workingSetsLogged: [true, false]
        )

        XCTAssertEqual(candidate, WorkoutResumeCandidate(id: id, plannedSetCount: 3, loggedSetCount: 1))
        XCTAssertTrue(candidate.hasRemainingSets)
    }

    func testResumeCandidatePlansAtLeastTheStoredRows() {
        let id = UUID()
        let candidate = WorkoutSetProgress.resumeCandidate(
            id: id, targetSets: 2, workingSetsLogged: [true, true, true]
        )

        XCTAssertEqual(candidate.plannedSetCount, 3)
        XCTAssertFalse(candidate.hasRemainingSets)
    }

    func testResumeSkipsAnExerciseWhoseOnlyRowWasEditedNotLogged() {
        let ids = makeIDs(count: 2)
        // Nothing was logged, only exercise 1's first set was edited: a fresh
        // workout still opens at the top.
        let edited = [
            WorkoutSetProgress.resumeCandidate(id: ids[0], targetSets: 3, workingSetsLogged: [false]),
            WorkoutSetProgress.resumeCandidate(id: ids[1], targetSets: 3, workingSetsLogged: [])
        ]
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: edited, remembered: nil), 0)

        // Exercise 1 fully logged moves the fallback on to exercise 2.
        let logged = [
            WorkoutSetProgress.resumeCandidate(id: ids[0], targetSets: 3, workingSetsLogged: [true, true, true]),
            edited[1]
        ]
        XCTAssertEqual(WorkoutRouteModel.resumeIndex(in: logged, remembered: nil), 1)
    }

    func testResumePositionStoreRoundTripsForgetsAndCapsEntries() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-position-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("WorkoutResumePosition.json")

        let store = WorkoutResumePositionStore(fileURL: fileURL, maxEntries: 2)
        let first = UUID(), second = UUID(), third = UUID()
        let firstLog = UUID(), secondLog = UUID(), thirdLog = UUID()

        XCTAssertNil(store.exerciseLogID(for: first))

        store.remember(exerciseLogID: firstLog, for: first)
        XCTAssertEqual(store.exerciseLogID(for: first), firstLog)
        // A second store reads what the first persisted.
        XCTAssertEqual(
            WorkoutResumePositionStore(fileURL: fileURL).exerciseLogID(for: first),
            firstLog
        )

        store.remember(exerciseLogID: secondLog, for: first)
        XCTAssertEqual(store.exerciseLogID(for: first), secondLog)

        store.forget(sessionID: first)
        XCTAssertNil(store.exerciseLogID(for: first))
        XCTAssertNil(WorkoutResumePositionStore(fileURL: fileURL).exerciseLogID(for: first))

        store.remember(exerciseLogID: firstLog, for: first)
        store.remember(exerciseLogID: secondLog, for: second)
        store.remember(exerciseLogID: thirdLog, for: third)
        // Only the two most recent sessions survive.
        XCTAssertEqual(store.exerciseLogID(for: second), secondLog)
        XCTAssertEqual(store.exerciseLogID(for: third), thirdLog)
        XCTAssertNil(store.exerciseLogID(for: first))
    }

    // MARK: - Helpers

    private func makeResumeCandidates(ids: [UUID], logged: [Int]) -> [WorkoutResumeCandidate] {
        zip(ids, logged).map { id, loggedCount in
            WorkoutResumeCandidate(id: id, plannedSetCount: 3, loggedSetCount: loggedCount)
        }
    }

    private func detail(
        targetSets: Int,
        minReps: Int,
        maxReps: Int,
        loadKg: Double?,
        unitSystem: UnitSystem
    ) -> String {
        WorkoutRouteModel.detail(
            targetSets: targetSets,
            minReps: minReps,
            maxReps: maxReps,
            targetLoadKg: loadKg,
            unitSystem: unitSystem
        )
    }

    private func makeIDs(count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    private func makeInputs(ids: [UUID], names: [String]? = nil) -> [WorkoutRouteInput] {
        ids.enumerated().map { index, id in
            WorkoutRouteInput(
                id: id,
                name: names?[index] ?? "Exercise \(index + 1)",
                targetSets: 3,
                minReps: 8,
                maxReps: 8,
                targetLoadKg: 100,
                loggedSetCount: 0,
                result: nil
            )
        }
    }
}
