// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: GymTracker/Services/BackupSlotStorage.swift (lines 1-517: layout, pointer, publish expectation, fence and the compare-and-swap publish)

import FirebaseFirestore
import Foundation

// MARK: - Database surface

/// A field the server fills in with its own clock (`FieldValue.serverTimestamp`).
/// The rules compare it to the request time, so a client cannot back-date it.
struct BackupServerTimestamp: Equatable {}

enum BackupDatabaseError: Error, Equatable {
    /// The security rules refused the request.
    case permissionDenied
}

/// The few document operations the backup layout needs, by full path
/// (`users/{uid}/backup/state`). Firestore implements it; tests use a fake that
/// mirrors the rules, so slot selection and the pointer flip can be exercised
/// without a server.
protocol BackupDocumentDatabase {
    func getDocument(_ path: String) async throws -> [String: Any]?
    /// Like `getDocument`, but never answered from a local cache. Deletion
    /// checks use it so "gone" means gone on the server.
    func getDocumentFromServer(_ path: String) async throws -> [String: Any]?
    func setDocument(_ path: String, data: [String: Any]) async throws
    func updateDocument(_ path: String, fields: [String: Any]) async throws
    func deleteDocuments(_ paths: [String]) async throws
    /// Applies the writes as one atomic batch. The rules check each write
    /// against the state the whole batch leaves behind.
    func commit(_ writes: [BackupBatchWrite]) async throws
    /// Up to `limit` ids of documents directly in the collection, from the server.
    func documentIDs(inCollection path: String, limit: Int) async throws -> [String]
}

/// One write of an atomic batch.
enum BackupBatchWrite {
    case set(String, [String: Any])
    case update(String, [String: Any])
}

extension BackupDocumentDatabase {
    func getDocumentFromServer(_ path: String) async throws -> [String: Any]? {
        try await getDocument(path)
    }
}

// MARK: - Layout

/// Each user owns exactly two backup slots. A new backup is written to the slot
/// that is not current, so the current one stays intact until the pointer flips.
enum BackupSlot: String, CaseIterable, Equatable, Sendable {
    case a
    case b

    var other: BackupSlot { self == .a ? .b : .a }
}

/// Where a user's backup documents live.
struct BackupPaths: Equatable {
    let uid: String

    var pointer: String { "users/\(uid)/backup/state" }
    func slot(_ slot: BackupSlot) -> String { "\(pointer)/slots/\(slot.rawValue)" }
    func chunks(_ slot: BackupSlot) -> String { "\(self.slot(slot))/chunks" }
    /// Chunk documents are named by their plain decimal index.
    func chunk(_ slot: BackupSlot, _ index: Int) -> String { "\(chunks(slot))/\(index)" }

    // Pre-slot layout, read and deleted but never written.
    var legacyLatest: String { "users/\(uid)/backups/latest" }
    var legacyChunks: String { "\(legacyLatest)/chunks" }
    var legacyGenerations: String { "\(legacyLatest)/generations" }
    func legacyGeneration(_ id: String) -> String { "\(legacyGenerations)/\(id)" }
    func legacyGenerationChunks(_ id: String) -> String { "\(legacyGeneration(id))/chunks" }
}

/// What a deletion made of the pointer. `cloud` is "delete cloud backup, keep
/// the account": it can be switched off again, explicitly. `account` is an
/// account deletion: irreversible for every client.
enum BackupDeletionMode: String, Equatable, Sendable {
    case none
    case cloud
    case account
}

/// The pointer document: which slot is current, whether a deletion has begun,
/// the epoch, and when the last manifest was recorded. With a deletion mode set
/// and no slot it is the tombstone a deletion leaves behind; it is never
/// removed by a client. The epoch rises each time a cloud deletion is switched
/// off, so an upload that started earlier cannot publish into the new backup.
/// `lastManifestAt` is the one-a-minute rate control; it lives here because
/// the pointer is never deleted.
struct BackupPointer: Equatable {
    var currentSlot: BackupSlot?
    var generationID: String?
    var deletion: BackupDeletionMode
    var epoch: Int
    /// When the last manifest was recorded (not part of equality).
    var lastManifestAt: Date?

    var deleting: Bool { deletion != .none }

    init(currentSlot: BackupSlot?, generationID: String?, deleting: Bool, epoch: Int = 0) {
        self.init(currentSlot: currentSlot, generationID: generationID, deletion: deleting ? .cloud : .none, epoch: epoch)
    }

    init(currentSlot: BackupSlot?, generationID: String?, deletion: BackupDeletionMode, epoch: Int = 0) {
        self.currentSlot = currentSlot
        self.generationID = generationID
        self.deletion = deletion
        self.epoch = epoch
    }

    init(_ data: [String: Any]) {
        currentSlot = (data["currentSlot"] as? String).flatMap(BackupSlot.init(rawValue:))
        generationID = data["generationID"] as? String
        if let mode = (data["deleting"] as? String).flatMap(BackupDeletionMode.init(rawValue:)) {
            deletion = mode
        } else {
            // A value this build does not know is treated as the strictest mode.
            deletion = data["deleting"] == nil ? .none : .account
        }
        epoch = (data["epoch"] as? Int) ?? (data["epoch"] as? NSNumber)?.intValue ?? 0
        lastManifestAt = data["lastManifestAt"] as? Date
    }

    static func == (lhs: BackupPointer, rhs: BackupPointer) -> Bool {
        lhs.currentSlot == rhs.currentSlot
            && lhs.generationID == rhs.generationID
            && lhs.deletion == rhs.deletion
            && lhs.epoch == rhs.epoch
    }
}

// MARK: - Publish expectation and fence

/// The cloud copy an upload is allowed to replace: what the person reviewed, or
/// what the save inspected just before. The store checks it against a fresh
/// server read and never adopts a newer copy it finds there; a mismatch stops
/// the save so the person can review again.
enum BackupPublishExpectation: Equatable, Sendable {
    /// The cloud held no backup.
    case noBackup
    /// The cloud held this generation in the slot layout.
    case generation(String)
    /// The cloud held a pre-slot backup: this generation, or nil for the
    /// original layout that has none.
    case legacy(String?)
    /// Tests and tools only: replace whatever is current. Production saves
    /// always pass what they inspected.
    case unchecked

    /// How the copy a person was shown is kept: "none", "generation:<id>",
    /// "legacy" or "legacy:<id>". `.unchecked` is never a viewed copy.
    var viewedCopyValue: String? {
        switch self {
        case .noBackup: return "none"
        case .generation(let id): return "generation:\(id)"
        case .legacy(let id): return id.map { "legacy:\($0)" } ?? "legacy"
        case .unchecked: return nil
        }
    }

    init?(viewedCopyValue value: String) {
        if value == "none" {
            self = .noBackup
        } else if value == "legacy" {
            self = .legacy(nil)
        } else if value.hasPrefix("generation:") {
            self = .generation(String(value.dropFirst("generation:".count)))
        } else if value.hasPrefix("legacy:") {
            self = .legacy(String(value.dropFirst("legacy:".count)))
        } else {
            return nil
        }
    }
}

/// How a running upload stays tied to the rest of the app. The slot writer
/// calls it before every write and before publishing; it throws when consent
/// was withdrawn, a review became pending, the workspace changed, or the
/// upload was cancelled.
struct BackupUploadFence {
    private let check: @MainActor () throws -> Void

    init(_ check: @escaping @MainActor () throws -> Void) {
        self.check = check
    }

    func verify() async throws {
        try await check()
    }
}

// MARK: - Slot store

/// The Firebase backup layout, independent of Firebase itself.
///
/// Save: confirm the cloud still holds the copy that was reviewed, pick the slot
/// that is not current, write its manifest as `uploading`, write chunks `0..<N`,
/// mark the manifest `complete`, read the chunks back, then flip the pointer
/// (compare-and-swap on the generation and epoch). Until the flip, readers keep
/// resolving the previous slot. A pre-slot copy is left alone; only a deletion
/// job removes it.
///
/// Read: follow the pointer to its slot. With no pointer, fall back to the
/// pre-slot `backups/latest` layout.
struct BackupSlotStore: RemoteFullAppBackupStoring {
    private let database: BackupDocumentDatabase
    private let paths: BackupPaths
    private let chunkByteLimit: Int

    init(
        database: BackupDocumentDatabase,
        uid: String,
        chunkByteLimit: Int = FullAppBackupLimits.maxCloudChunkBytes
    ) {
        self.database = database
        paths = BackupPaths(uid: uid)
        self.chunkByteLimit = chunkByteLimit
    }

    // MARK: Reading

    func latestMetadata() async throws -> FullAppBackupMetadata? {
        guard let resolved = try await resolveCurrent() else { return nil }
        return try header(from: resolved).metadata
    }

    func latestHeader() async throws -> RemoteFullAppBackupHeader? {
        guard let resolved = try await resolveCurrent() else { return nil }
        return try header(from: resolved)
    }

    func latestRecord() async throws -> RemoteFullAppBackupRecord? {
        guard let resolved = try await resolveCurrent() else { return nil }
        let header = try header(from: resolved)
        let chunkCount = try validatedChunkCount(from: resolved)
        let encryptedData: Data
        let expectedGenerationID: String?
        switch resolved.layout {
        case .slot(let slot):
            expectedGenerationID = header.generationID
            encryptedData = try await encryptedPayload(
                chunkCount: chunkCount,
                expectedGenerationID: expectedGenerationID
            ) { paths.chunk(slot, $0) }
        case .legacyGeneration(let id):
            expectedGenerationID = id
            encryptedData = try await encryptedPayload(
                chunkCount: chunkCount,
                expectedGenerationID: expectedGenerationID
            ) { "\(paths.legacyGenerationChunks(id))/\(Self.legacyChunkName($0))" }
        case .legacyLatest:
            expectedGenerationID = nil
            encryptedData = try await encryptedPayload(
                chunkCount: chunkCount,
                expectedGenerationID: nil
            ) { "\(paths.legacyChunks)/\(Self.legacyChunkName($0))" }
        }
        // Slots and legacy generations always carry the hash; the original
        // latest/chunks layout never did.
        if resolved.layout != .legacyLatest || resolved.data["payloadSHA256"] != nil {
            guard let expectedHash = resolved.data["payloadSHA256"] as? String,
                  expectedHash == FirebaseFullAppBackupStore.sha256Hex(encryptedData) else {
                throw FirebaseFullAppBackupError.integrityCheckFailed
            }
        }
        return RemoteFullAppBackupRecord(
            metadata: header.metadata,
            crypto: header.crypto,
            encryptedData: encryptedData,
            formatVersion: header.formatVersion,
            generationID: header.generationID,
            isLegacyLayout: header.isLegacyLayout,
            cryptoVersion: header.cryptoVersion
        )
    }

    // MARK: Saving

    func saveRecord(_ record: RemoteFullAppBackupRecord) async throws {
        _ = try await publish(record)
    }

    /// Replaces whatever is current. For tests and tools; a save from the app
    /// passes what it inspected to `publish(_:expecting:fence:)`.
    func publish(_ record: RemoteFullAppBackupRecord) async throws -> String? {
        try await publish(record, expecting: .unchecked, fence: nil)
    }

    func publish(
        _ record: RemoteFullAppBackupRecord,
        expecting expectation: BackupPublishExpectation,
        fence: BackupUploadFence?
    ) async throws -> String? {
        try record.crypto.validateSupported()
        guard record.formatVersion == BackupHeaderV4.formatVersion,
              record.cryptoVersion == BackupHeaderV4.cryptoVersion,
              let generationID = record.generationID,
              BackupHeaderV4.isValidGenerationID(generationID) else {
            throw FirebaseFullAppBackupError.unsupportedFormat
        }
        guard (0...FullAppBackupLimits.maxCompressedPayloadBytes).contains(record.metadata.compressedByteCount),
              record.metadata.compressedByteCount == record.encryptedData.count,
              record.encryptedData.count <= FullAppBackupLimits.maxCompressedPayloadBytes + 16 else {
            throw FirebaseFullAppBackupError.payloadTooLarge
        }
        let chunks = FirebaseFullAppBackupStore.split(record.encryptedData, chunkByteLimit: chunkByteLimit)
        guard (1...FullAppBackupLimits.maxCloudChunkCount).contains(chunks.count) else {
            throw FirebaseFullAppBackupError.chunkLimitExceeded
        }
        let payloadHash = FirebaseFullAppBackupStore.sha256Hex(record.encryptedData)

        // 1. Read the pointer from the server and check it against what was
        //    reviewed. A copy that appeared since is never adopted: the save
        //    stops before writing anything.
        try Task.checkCancellation()
        try await fence?.verify()
        let pointer = try await readPointer(fromServer: true)
        // A deleted backup is never re-enabled from here. A cloud deletion
        // waits for the person's explicit choice (`reenableCloudBackup`); an
        // account deletion has no way back at all.
        switch pointer?.deletion ?? .none {
        case .none: break
        case .cloud: throw FirebaseFullAppBackupError.cloudBackupTurnedOff
        case .account: throw FirebaseFullAppBackupError.deletionInProgress
        }
        try await confirm(expectation)
        // The manifest will name the pointer's generation as the one it
        // replaces, so the pointer just read must agree with what was reviewed.
        switch expectation {
        case .generation(let reviewed):
            guard pointer?.generationID == reviewed else { throw FirebaseFullAppBackupError.reviewedBackupChanged }
        case .noBackup, .legacy:
            guard pointer?.generationID == nil else { throw FirebaseFullAppBackupError.reviewedBackupChanged }
        case .unchecked:
            break
        }
        let epoch = pointer?.epoch ?? 0
        let slot = pointer?.currentSlot?.other ?? .a

        // 2. Manifest first, as `uploading`, in one batch with the pointer's
        //    rate timestamp (`lastManifestAt`): the rules refuse a manifest
        //    that does not move it, or that comes within a minute of its
        //    previous value, whatever happened to the earlier manifest.
        var manifest = manifestFields(
            for: record,
            slot: slot,
            generationID: generationID,
            chunkCount: chunks.count,
            payloadHash: payloadHash
        )
        manifest["expectedPreviousGenerationID"] = pointer?.generationID ?? NSNull()
        manifest["epoch"] = epoch
        manifest["state"] = "uploading"
        try Task.checkCancellation()
        try await fence?.verify()
        let recordManifest: BackupBatchWrite
        if pointer != nil {
            recordManifest = .update(
                paths.pointer,
                ["updatedAt": BackupServerTimestamp(), "lastManifestAt": BackupServerTimestamp()]
            )
        } else {
            recordManifest = .set(
                paths.pointer,
                [
                    "currentSlot": NSNull(),
                    "generationID": NSNull(),
                    "updatedAt": BackupServerTimestamp(),
                    "deleting": BackupDeletionMode.none.rawValue,
                    "epoch": 0,
                    "lastManifestAt": BackupServerTimestamp()
                ]
            )
        }
        do {
            try await database.commit([recordManifest, .set(paths.slot(slot), manifest)])
        } catch BackupDatabaseError.permissionDenied {
            // The server does not say why. A manifest inside the minute is the
            // one cause the client can tell; anything else (an unconfirmed
            // mailbox, a deletion that just began) gets neutral wording.
            if let last = pointer?.lastManifestAt, Date().timeIntervalSince(last) < 60 {
                throw FirebaseFullAppBackupError.savedTooRecently
            }
            throw FirebaseFullAppBackupError.uploadRefused
        }

        // 3. Deterministic chunks 0..<N.
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            try await fence?.verify()
            try await database.setDocument(
                paths.chunk(slot, index),
                data: [
                    "generationID": generationID,
                    "index": index,
                    "payloadBase64": chunk.base64EncodedString(),
                    "sha256": FirebaseFullAppBackupStore.sha256Hex(chunk)
                ]
            )
        }

        // 4. Freeze the slot: chunks can no longer change.
        try Task.checkCancellation()
        try await fence?.verify()
        try await database.updateDocument(paths.slot(slot), fields: ["state": "complete"])

        // 5. Read the slot back before it can become current.
        try Task.checkCancellation()
        try await fence?.verify()
        try await verifySlot(slot, generationID: generationID, payloadHash: payloadHash, chunkCount: chunks.count)

        // 6. Flip the pointer. This single write is the commit point; the rules
        //    make it a compare-and-swap on the previous generation and epoch,
        //    and check the manifest as the write leaves it. A last look at the
        //    fence comes right before it.
        try Task.checkCancellation()
        try await fence?.verify()
        do {
            // An update: the deleting mode, epoch and rate timestamp stay as
            // they are, which is what the flip rule requires.
            try await database.updateDocument(
                paths.pointer,
                fields: [
                    "currentSlot": slot.rawValue,
                    "generationID": generationID,
                    "updatedAt": BackupServerTimestamp()
                ]
            )
        } catch BackupDatabaseError.permissionDenied {
            throw FirebaseFullAppBackupError.publishConflict
        }

        // From here the new backup is live. A pre-slot copy is not deleted
        // here: the rules allow legacy deletes only inside a deletion job, and
        // readers follow the pointer, so it is ignored until then.
        return generationID
    }

    // MARK: Expectation and re-enabling

    /// Checks a fresh server read of the current backup against what the caller
    /// reviewed. Never adopts what it finds.
    private func confirm(_ expectation: BackupPublishExpectation) async throws {
        guard expectation != .unchecked else { return }
        guard try await observeCurrent() == expectation else {
            throw FirebaseFullAppBackupError.reviewedBackupChanged
        }
    }

    private func observeCurrent() async throws -> BackupPublishExpectation {
        guard let resolved = try await resolveCurrent(fromServer: true) else { return .noBackup }
        switch resolved.layout {
        case .slot:
            return .generation(resolved.data["generationID"] as? String ?? "")
        case .legacyGeneration(let id):
            return .legacy(id)
        case .legacyLatest:
            return .legacy(nil)
        }
    }

    /// Turns a cloud-only deletion off, so the next save may upload again. This
    /// is an explicit operation: it is called only after the person chooses to
    /// back up again, never from `publish`. The deletion must have finished (no
    /// manifest left), the sign-in must be recent (the rules check `auth_time`),
    /// and the epoch rises by one. An account deletion cannot be switched off.
    /// Nothing happens when the backup was never deleted.
    func reenableCloudBackup() async throws {
        guard let stored = try await database.getDocumentFromServer(paths.pointer) else { return }
        let tombstone = BackupPointer(stored)
        switch tombstone.deletion {
        case .none: return
        case .account: throw FirebaseFullAppBackupError.deletionInProgress
        case .cloud: break
        }
        for slot in BackupSlot.allCases {
            if try await database.getDocumentFromServer(paths.slot(slot)) != nil {
                throw FirebaseFullAppBackupError.deletionInProgress
            }
        }
        do {
            try await database.updateDocument(
                paths.pointer,
                fields: [
                    "currentSlot": NSNull(),
                    "generationID": NSNull(),
                    "updatedAt": BackupServerTimestamp(),
                    "deleting": BackupDeletionMode.none.rawValue,
                    "epoch": tombstone.epoch + 1
                ]
            )
        } catch BackupDatabaseError.permissionDenied {
            throw FirebaseFullAppBackupError.recentSignInRequired
        }
    }

    // MARK: Resolving

    private struct ResolvedManifest {
        enum Layout: Equatable {
            case slot(BackupSlot)
            case legacyGeneration(String)
            case legacyLatest
        }

        let layout: Layout
        let data: [String: Any]

        var isLegacy: Bool {
            if case .slot = layout { return false }
            return true
        }
    }

    /// `fromServer` skips the local cache: publishing and its checks never act
    /// on a cached copy.

// … (Firestore adapter and decoding helpers omitted)
