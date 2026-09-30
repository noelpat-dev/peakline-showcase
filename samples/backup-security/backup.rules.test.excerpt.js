// Excerpt from Peakline (private repository), shared for portfolio review.
// © 2026 Noel Patricks. All rights reserved. Not licensed for reuse.
// Source: firebase/rules-tests/backup.rules.test.js (first 260 lines)

// Emulator tests for firestore.rules (Spark backup layout).
//
// Run from this folder with the Firestore emulator:
//   firebase emulators:exec --only firestore --project demo-peakline "npm test"

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds
} = require('@firebase/rules-unit-testing');
const {
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  documentId,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch
} = require('firebase/firestore');

const PROJECT_ID = 'demo-peakline';
const OWNER = 'alice';
const OTHER = 'mallory';

let testEnv;

const POINTER = `users/${OWNER}/backup/state`;
const slotPath = (slot) => `${POINTER}/slots/${slot}`;
const chunkPath = (slot, name) => `${slotPath(slot)}/chunks/${name}`;

const ago = (seconds) => Timestamp.fromMillis(Date.now() - seconds * 1000);

function manifest(overrides = {}) {
  return {
    schemaVersion: 4,
    storageSchemaVersion: 4,
    cryptoVersion: 1,
    slot: 'a',
    createdAt: serverTimestamp(),
    compressedByteCount: 1000,
    chunkCount: 3,
    encryptionAlgorithm: 'AES-GCM-256',
    keyDerivation: 'PBKDF2-HMAC-SHA256',
    iterationCount: 210000,
    saltBase64: 'A'.repeat(22) + '==',
    nonceBase64: 'B'.repeat(16),
    tagBase64: 'C'.repeat(22) + '==',
    generationID: 'gen-1',
    payloadSHA256: 'd'.repeat(64),
    expectedPreviousGenerationID: null,
    epoch: 0,
    state: 'uploading',
    ...overrides
  };
}

function chunk(index, overrides = {}) {
  return {
    generationID: 'gen-1',
    index,
    payloadBase64: 'QUJD',
    sha256: 'e'.repeat(64),
    ...overrides
  };
}

// A pointer as a client creates it (server times). `deleting` is 'none',
// 'cloud' or 'account'.
function pointer(overrides = {}) {
  return {
    currentSlot: null,
    generationID: null,
    updatedAt: serverTimestamp(),
    deleting: 'none',
    epoch: 0,
    lastManifestAt: serverTimestamp(),
    ...overrides
  };
}

// The same, seeded with concrete times. `lastManifestAt` is when the last
// manifest was recorded.
const seededPointer = (overrides = {}) => ({
  currentSlot: 'a',
  generationID: 'gen-1',
  updatedAt: ago(600),
  deleting: 'none',
  epoch: 0,
  lastManifestAt: ago(600),
  ...overrides
});

const seededTombstone = (mode = 'cloud', overrides = {}) => seededPointer({
  currentSlot: null, generationID: null, deleting: mode, ...overrides
});

// Seeds documents with security rules off. Timestamps are concrete values.
async function seed(entries) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [docPath, data] of Object.entries(entries)) {
      await setDoc(doc(db, docPath), data);
    }
  });
}

async function removeDocs(...paths) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    for (const docPath of paths) await deleteDoc(doc(context.firestore(), docPath));
  });
}

async function pointerExists() {
  let exists = false;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    exists = (await getDoc(doc(context.firestore(), POINTER))).exists();
  });
  return exists;
}

const seedManifest = (slot, overrides = {}) => seed({
  [slotPath(slot)]: manifest({ slot, createdAt: ago(600), ...overrides })
});

// The seconds-since-epoch time a sign-in happened, `secondsAgo` seconds back.
const authTime = (secondsAgo = 0) => Math.floor(Date.now() / 1000) - secondsAgo;

// A signed-in owner. By default the mailbox is verified and the sign-in is
// fresh; pass claims to change that (a claim set to undefined is left out).
const ownerDb = (claims = {}) => {
  const token = { email_verified: true, auth_time: authTime(), ...claims };
  for (const key of Object.keys(token)) if (token[key] === undefined) delete token[key];
  return testEnv.authenticatedContext(OWNER, token).firestore();
};
const otherDb = () => testEnv.authenticatedContext(OTHER, { email_verified: true, auth_time: authTime() }).firestore();
const anonDb = () => testEnv.unauthenticatedContext().firestore();

// Claims for a session that signed in a while ago / has an unconfirmed mailbox.
const staleSignIn = { auth_time: authTime(600) };
const noSignInTime = { auth_time: undefined };
const unverified = { email_verified: false };
const noVerifiedClaim = { email_verified: undefined };

// Writing a manifest is one batch: the pointer records the time in
// lastManifestAt (creating the pointer for the first upload) and the manifest
// is created or overwritten. `pointerFields` overrides the pointer's update.
async function putManifest(db, slot, overrides = {}, pointerFields = {}) {
  const batch = writeBatch(db);
  if (await pointerExists()) {
    batch.update(doc(db, POINTER), {
      updatedAt: serverTimestamp(), lastManifestAt: serverTimestamp(), ...pointerFields
    });
  } else {
    batch.set(doc(db, POINTER), pointer(pointerFields));
  }
  batch.set(doc(db, slotPath(slot)), manifest({ slot, ...overrides }));
  return batch.commit();
}

// Publishing: the pointer flips to the slot's generation.
const flipTo = (db, slot, generationID, extra = {}) => updateDoc(doc(db, POINTER), {
  currentSlot: slot, generationID, updatedAt: serverTimestamp(), ...extra
});

const startDeletion = (db, mode, extra = {}) => updateDoc(doc(db, POINTER), {
  currentSlot: null, generationID: null, deleting: mode, updatedAt: serverTimestamp(), ...extra
});

const switchOff = (db, epoch, extra = {}) => updateDoc(doc(db, POINTER), {
  currentSlot: null, generationID: null, deleting: 'none', epoch, updatedAt: serverTimestamp(), ...extra
});

describe('Peakline backup rules (Spark slots)', () => {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8')
      }
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  describe('owner only', () => {
    beforeEach(async () => {
      await seed({
        [POINTER]: seededPointer(),
        [slotPath('a')]: manifest({ createdAt: ago(600), state: 'complete' }),
        [chunkPath('a', '0')]: chunk(0),
        [`users/${OWNER}/backups/latest`]: { generationID: 'legacy' }
      });
    });

    it('lets the owner read every backup path', async () => {
      const db = ownerDb();
      await assertSucceeds(getDoc(doc(db, POINTER)));
      await assertSucceeds(getDoc(doc(db, slotPath('a'))));
      await assertSucceeds(getDoc(doc(db, chunkPath('a', '0'))));
      await assertSucceeds(getDocs(collection(db, `${slotPath('a')}/chunks`)));
      await assertSucceeds(getDoc(doc(db, `users/${OWNER}/backups/latest`)));
    });

    it('denies another signed-in user every read', async () => {
      const db = otherDb();
      await assertFails(getDoc(doc(db, POINTER)));
      await assertFails(getDoc(doc(db, slotPath('a'))));
      await assertFails(getDoc(doc(db, chunkPath('a', '0'))));
      await assertFails(getDocs(collection(db, `${slotPath('a')}/chunks`)));
      await assertFails(getDoc(doc(db, `users/${OWNER}/backups/latest`)));
    });

    it('denies another signed-in user every write and delete', async () => {
      const db = otherDb();
      await assertFails(putManifest(db, 'b', { generationID: 'gen-2' }));
      await assertFails(startDeletion(db, 'cloud'));
      await assertFails(startDeletion(db, 'account'));
      await assertFails(deleteDoc(doc(db, slotPath('a'))));
      await assertFails(deleteDoc(doc(db, chunkPath('a', '0'))));
      await assertFails(deleteDoc(doc(db, POINTER)));
      await assertFails(deleteDoc(doc(db, `users/${OWNER}/backups/latest`)));
    });

    it('denies signed-out access', async () => {
      const db = anonDb();
      await assertFails(getDoc(doc(db, POINTER)));
      await assertFails(getDoc(doc(db, slotPath('a'))));
      await assertFails(setDoc(doc(db, slotPath('b')), manifest({ slot: 'b' })));
      await assertFails(deleteDoc(doc(db, POINTER)));
    });

    it('denies anything outside the backup layout', async () => {
      await assertFails(setDoc(doc(ownerDb(), `users/${OWNER}/other/thing`), { a: 1 }));
      await assertFails(getDoc(doc(ownerDb(), `users/${OWNER}`)));
    });
  });

  describe('slot manifests', () => {
    it('creates an uploading manifest, and the pointer with it, for the first upload', async () => {
      await assertSucceeds(putManifest(ownerDb(), 'a'));
    });

    it('creates an uploading manifest in slot b a minute after the last one', async () => {
      await seed({ [POINTER]: seededPointer() });
      await seedManifest('a', { state: 'complete' });

// … (122 tests in total; the rest omitted)
