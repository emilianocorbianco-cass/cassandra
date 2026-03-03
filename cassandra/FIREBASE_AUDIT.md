# Firebase/Firestore Persistence Audit

Date: 2026-02-27  
Repository: `cassandra`

## Validation run
- `flutter analyze` -> **No issues found**
- `flutter test` -> **All tests passed**
- `npm --prefix functions run build` -> **TypeScript build OK**
- `firebase emulators:exec --config /tmp/firebase.firestore.audit.json --only firestore "echo rules-ok"` -> **OK**

## Critical

### C1. Fixed: unauthorized direct membership creation path (security + data integrity)
- **File(s):**
  - `firestore.rules:58-76`
  - `firestore.rules:140-148`
  - `lib/services/firestore/firestore_service.dart:501-537`
- **Description:** member-doc create is now tied to a valid group state transition (`memberCount` increment) or creator-bootstrap path in the same request context.
- **Suggested fix applied:** strict rule predicates + profile sync writes only existing member docs.

### C2. Fixed: picks outbox could get permanently blocked by one stale entry
- **File(s):**
  - `lib/app/state/app_state.dart:812-860`
  - `lib/app/state/app_state.dart:1890-1942`
  - `lib/app/state/app_state.dart:2742-2760`
- **Description:** one permanent failure no longer blocks replay of all queued entries.
- **Suggested fix applied:** structured retry result with permanent-error dropping (`permission-denied`, `failed-precondition`, `invalid-argument`, `not-found`).

### C3. Fixed: group delete partial cleanup risk
- **File(s):**
  - `lib/services/firestore/firestore_service.dart:632-703`
  - `functions/src/index.ts:760-840`
  - `functions/src/index.ts:935-1024`
  - `functions/src/index.ts:2101-2119`
- **Description:** deletion now removes invite early, clears stale invite docs, and has idempotent backend cleanup for `deleting=true` groups.
- **Suggested fix applied:** hardening in client deletion flow + scheduled backend cleanup worker.

### C4. Fixed: profile conflict resolution was global and could overwrite unrelated fields
- **File(s):**
  - `lib/app/config/storage_keys.dart:13-15`
  - `lib/app/state/app_state.dart:253-316`
  - `lib/app/state/app_state.dart:327-475`
  - `lib/app/state/app_state.dart:1365-1469`
- **Description:** merge arbitration now tracks local updates per field instead of one global timestamp.
- **Suggested fix applied:** persisted per-field update timestamps for `displayName`, `teamName`, `favoriteTeam`, `photoUrl`, `language`, `defaultVisibility`.

### C5. Fixed: uploaded images were persisted as bearer `downloadURL`
- **File(s):**
  - `lib/services/storage/storage_service.dart:26-127`
  - `lib/app/state/app_state.dart:955-1031`
  - `lib/app/state/app_state.dart:1390-1445`
  - `lib/app/state/app_state.dart:2537-2624`
  - `lib/features/profile/widgets/profile_image_picker.dart:105-127`
  - `lib/features/group/widgets/group_image_picker.dart:99-121`
  - `lib/features/badges/widgets/avatar_with_badges.dart:117-129`
- **Description:** app now persists Firebase Storage assets as `storage://<path>` and renders via authenticated SDK reads (`getData`) instead of long-lived bearer URLs.
- **Suggested fix applied:** storage reference normalization/migration, authenticated byte reads, and reference-aware existence/deletion checks.

### C6. Fixed: deleting-group recovery depended only on scheduled Functions
- **File(s):**
  - `lib/services/firestore/firestore_service.dart:705-736`
  - `lib/app/state/app_state.dart:215-231`
- **Description:** recovery now also runs during authenticated bootstrap for group admins.
- **Suggested fix applied:** client-triggered `resumeDeletingGroupsForAdmin` self-healing path added in post-auth bootstrap.

## Warning

No open warnings after the applied fixes.

## Improvement

### I1. Add emulator tests for join/create coupling rules
- **File(s):**
  - `firestore.rules:58-76`
  - `firestore.rules:140-148`
- **Suggested fix:** add deny/allow matrix tests for member create with/without matching group transition.

### I2. Add explicit tests for outbox permanent-error eviction
- **File(s):**
  - `lib/app/state/app_state.dart:1890-1942`
- **Suggested fix:** verify stale denied entries are dropped and following valid entries are still flushed.

### I3. Add monitoring for cleanup jobs
- **File(s):**
  - `functions/src/index.ts:935-1024`
  - `functions/src/index.ts:2109-2119`
- **Suggested fix:** alert on repeated cleanup failures and expose an operator runbook command.
