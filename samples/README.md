# Selected source

These files come from the private Peakline repository, lightly trimmed where marked. They're here to show how the app is engineered: they won't build on their own, and they're not licensed for reuse (see [LICENSE](../LICENSE)).

| File | What it shows |
| --- | --- |
| [design/SummitToolbarButton.swift](design/SummitToolbarButton.swift) | A small design-system component. It swaps iOS 26's default glass toolbar buttons for the app's own hairline glyphs, and keeps the edge swipe-back working when the system back button is hidden. |
| [design/RestSunArtwork.swift](design/RestSunArtwork.swift) | The rest timer's "sun crossing the sky", driven by the clock rather than by animation state, so returning to the app never makes it jump. It respects Reduce Motion. |
| [workout/WorkoutRouteModel.swift](workout/WorkoutRouteModel.swift) | The pure value model behind "today's route": stops, progress, new bests and "start this one now" reordering. SwiftUI-free and fully unit-tested. |
| [workout/WorkoutRouteModelTests.swift](workout/WorkoutRouteModelTests.swift) | Its XCTest suite. |
| [coaching/ProgressionRules.swift](coaching/ProgressionRules.swift) | Deterministic progression rules behind the coach's next-target suggestions. |
| [backup-security/BackupSlotStorage.swift](backup-security/BackupSlotStorage.swift) | The two-slot encrypted backup store: paths, the pointer, the publish expectation, the upload fence, and the compare-and-swap publish that won't replace a backup the user didn't review. |
| [backup-security/firestore.rules](backup-security/firestore.rules) | The Firestore security rules that make that design hold on the server: owner-only access, verified email, a frozen-once-complete slot, a one-a-minute pointer limit, recent-sign-in deletion and tombstones. |
| [backup-security/backup.rules.test.excerpt.js](backup-security/backup.rules.test.excerpt.js) | An excerpt of the 122 emulator tests for those rules. |
