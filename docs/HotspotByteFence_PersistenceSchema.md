# Hotspot Byte Fence (HBF) — Persistence Schema and Recovery Contract

**Version:** 0.3
**Date:** 2026-09-01  
**Normative source:** [`HotspotByteFence_PRD.md`](HotspotByteFence_PRD.md)  
**Implementation status:** Initial typed persistence foundation is implemented under `Sources/HotspotByteFenceCore` with canonical JSON, owner-only permissions, LKG validation, journal phases, digest checks, explicit recovery results, and initial typed installation-marker/tombstone cross-file transitions. The complete `StoreEnvelopeV1`, full profile-reference purge validation, command ledger, and preference archive remain pending.

This document defines the concrete v1 logical store. It must be implemented with typed Swift `Codable` records or stricter equivalent parsers. Ad hoc string manipulation is not acceptable at the persistence boundary. Real-Mac candidate execution and evidence handling follow [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md).

---

## 1. Files and Permissions

All files live under the application support directory for `com.copylawbot.hotspotbytefence`. The directory must be created with owner-only access. On macOS, the target mode is `0700` for directories and `0600` for regular files. If the file system cannot enforce these permissions, HBF enters `recoveryRequired` before measuring or blocking.

| File | Required mode | Purpose | Atomic write set |
|---|---:|---|---|
| `state.json` | `0600` | Canonical versioned store | Every durable domain transition |
| `state.lkg.json` | `0600` | Last-known-good validated store | Updated only after canonical validation succeeds |
| `installation.json` | `0600` | Completed-profile marker and installation id | Written after first completed profile store validates |
| `tombstones.json` | `0600` | Deleted profile ids and deletion revisions | Written before profile purge is reported |
| `commit-journal.json` | `0600` | Cross-file transition phase and validated digests | Written and flushed before any multi-file transition |
| `failed-state/<timestamp>-state.json` | `0600` | Preserved unreadable/corrupt canonical files | Best-effort diagnostic preservation |
| `evidence-local/*.json` | `0600` | Full local GitHub-candidate evidence | Local only; may contain redacted identifiers but no secrets |
| `reports-redacted/*.json` | `0644` or stricter | Shareable report with hashed/redacted identity | Generated from local evidence, never the canonical source |

Atomic replacement uses a unique temporary file in the same directory, `fsync`/equivalent flush on the file, atomic rename over the destination, and directory flush where the platform supports it. HBF validates the decoded destination before the transition is visible. The LKG copy is updated only after the canonical file validates.

---

## 2. Serialization Rules

| Value class | JSON representation | Validation |
|---|---|---|
| `UInt64` byte counts and revisions | Canonical decimal string, no sign, no leading zeros except `"0"` | Checked parse into `UInt64` |
| SSID bytes | Lowercase hex string, even length, 2 to 64 hex chars | 1-32 raw octets |
| BSSID | Lowercase colon-separated six octets | Regex-equivalent byte parser, not display-only string |
| Interface name | Nonempty string from BSD interface name | Stored exactly after adapter validation |
| Date-only cycle id | `YYYY-MM-DD` plus IANA time-zone id | Calendar-valid local date |
| Instants | RFC 3339 UTC with fractional seconds | Wall-clock instants only; monotonic values are not persisted |
| Durations | Integer seconds | Nonnegative bounded values |
| Binary archives | Base64url without padding | Decode length and archive schema before use |
| Enum values | Lower camel-case strings from this schema | Unknown value without migration enters recovery |
| Hashes/fingerprints | Lowercase hex SHA-256 | Algorithm id must match stored value |

The v1 store uses UTF-8 JSON with sorted object keys for deterministic diagnostics. JSON key ordering is not used for semantic integrity; typed decoding is authoritative.

---

## 3. Store Envelope

```text
StoreEnvelopeV1
  schemaVersion: UInt = 1
  storeRevision: UInt64String
  previousGoodRevision: UInt64String?
  installationID: UUIDString
  hasCompletedProfile: Bool
  observedArtifact: ArtifactObservationRecord
  globalState: GlobalStateRecord
  selectedProfileID: UUIDString?
  languageOverride: "system" | "ko" | "en"
  profiles: [ProfileRecord]
  preferenceTransactions: [PreferenceTransactionRecord]
  commandResults: [CommandResultRecord]
  notificationState: NotificationStateRecord
  eventLog: EventLogRecord
  tombstoneDigest: SHA256Hex
  integrity: IntegrityRecord
```

`storeRevision` increments by one for every successful canonical store transition. A transition that must atomically update another file, such as a tombstone or installation marker, records the external file revision and digest inside the event log.

---

## 4. Records

### 4.0 Supporting records and cross-file metadata

The files named in Section 1 have typed records as well as the canonical
`StoreEnvelopeV1`. These records are part of the v1 schema; a file is not
considered valid merely because its JSON is syntactically valid.

#### InstallationMarkerV1 (`installation.json`)

| Field | Type | Required | Notes |
|---|---|---:|---|
| `schemaVersion` | UInt | Yes | `1` |
| `installationID` | UUIDString | Yes | Must equal the canonical store and LKG |
| `hasCompletedProfile` | Bool | Yes | Once true, never becomes false through ordinary profile deletion |
| `firstCompletedStoreRevision` | UInt64String | Yes | Revision that first contained a complete profile |
| `firstCompletedStoreDigest` | SHA256Hex | Yes | Digest of the validated canonical store at that revision |
| `createdAt` | Instant | Yes | Marker creation time |
| `updatedAt` | Instant | Yes | Last marker validation or repair time |

The marker is written only after the corresponding canonical store and LKG
validate. A marker with `hasCompletedProfile=true` is never replaced by a
fresh-install marker. A marker with an unknown schema or inconsistent
installation id enters `recoveryRequired`.

#### CommitJournalV1 (`commit-journal.json`)

| Field | Type | Required | Notes |
|---|---|---:|---|
| `schemaVersion` | UInt | Yes | `1` |
| `installationID` | UUIDString | Yes | Must equal the canonical store, LKG, marker, and tombstones |
| `operation` | Closed transition enum | Yes | `firstCompletedProfile`, `measurementSample`, `limitReached`, `preferencePrepare`, `preferenceApplied`, `restoration`, `profileDeletion`, or `recoveryFromLKG` |
| `targetStoreRevision` | UInt64String | Yes | Revision intended by the transition |
| `phase` | Closed phase enum | Yes | `prepared`, `canonicalCommitted`, `lkgCommitted`, `markerCommitted`, `purgeInProgress`, or `complete` |
| `canonicalDigest` | SHA256Hex or null | Yes | Last validated `state.json` digest for this transition |
| `lkgDigest` | SHA256Hex or null | Yes | Last validated `state.lkg.json` digest for this transition |
| `installationDigest` | SHA256Hex or null | Yes | Last validated `installation.json` digest for this transition |
| `tombstoneDigest` | SHA256Hex or null | Yes | Last validated `tombstones.json` digest for this transition |
| `updatedAt` | Instant | Yes | Journal phase update time |

The operation fixes the affected replacement set and the only legal phase
sequence:

| Operation | Affected replacement files | Legal phase sequence |
|---|---|---|
| `firstCompletedProfile` | `state.json`, `state.lkg.json`, `installation.json` | `prepared` → `canonicalCommitted` → `lkgCommitted` → `markerCommitted` → `complete` |
| `measurementSample`, `limitReached`, `preferencePrepare`, `preferenceApplied`, `restoration` | `state.json`, `state.lkg.json` | `prepared` → `canonicalCommitted` → `lkgCommitted` → `complete` |
| `profileDeletion` | `state.json`, `state.lkg.json`, `tombstones.json` | `prepared` → `purgeInProgress` → `complete` |
| `recoveryFromLKG` | `state.json`, `state.lkg.json`; current tombstone digest is a read-only guard | `prepared` → `canonicalCommitted` → `lkgCommitted` → `complete` |

In `prepared`, each affected file's digest records the last fully validated
pre-transition bytes. `canonicalCommitted` requires the target `state.json`
revision and digest; `lkgCommitted` additionally requires the target LKG
revision and digest; `markerCommitted` additionally requires the target
installation-marker digest. `purgeInProgress` requires a durable tombstone
with `purgeCompleted=false` and records the latest validated digest for every
file reached so far. `complete` requires every affected destination and all
cross-file invariants to validate at the target revision. A digest for a
non-affected file is null unless it is included as a read-only cross-file
guard. A phase transition that does not satisfy these requirements is itself
invalid and enters `recoveryRequired`.

The journal is written and flushed in `prepared` phase before the first file
replacement. After each required replacement, the destination is decoded and
validated, its digest is recorded, and the journal is flushed again. A
transition becomes `complete` only after every required file and cross-file
invariant validates. The journal is retained as the latest completed record;
it must not be deleted as a substitute for recovery evidence.

At launch, a non-complete journal, a journal digest or revision mismatch, or a
cross-file relation that cannot be explained by the journal enters
`recoveryRequired`. HBF preserves all candidate files and never chooses a
lower or merely newer copy automatically. The only automatic continuation is
resuming a `profileDeletion` whose durable tombstone has `purgeCompleted=false`;
the deleted profile remains hidden until the purge validates. A missing journal
is valid only for a first-run store or a fully validated state with no
cross-file transition in progress; if cross-file relations show that a transition
required a journal, the missing file enters `recoveryRequired`.

#### IntegrityRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `algorithm` | `hbf-store-v1-sha256` | Yes | Fixed v1 algorithm identifier |
| `canonicalDigest` | SHA256Hex | Yes | Digest of the canonical envelope with integrity digests set to null |
| `lkgDigest` | SHA256Hex or null | Yes | Digest of the validated LKG envelope using the same canonicalization |
| `lastValidatedRevision` | UInt64String | Yes | Must equal `storeRevision` |
| `previousValidatedRevision` | UInt64String or null | Yes | Must be lower than `lastValidatedRevision` when present |
| `validatedAt` | Instant | Yes | Last successful validation time |

The digest input is UTF-8 JSON with sorted keys, explicit nulls, and the
canonical decimal and hexadecimal encodings from Section 2. The digest does
not include the digest fields themselves. A digest mismatch, decreasing
revision, or inconsistent LKG relation enters `recoveryRequired`; HBF does
not silently repair the canonical store from a lower revision.

#### TimeAdjustmentRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `reason` | `earlierCycle` or `backwardWallClock` or `wallMonotonicDivergence` | Yes | Machine-readable acknowledgement reason |
| `trustedCycleDate` | Local date string | Yes | Cycle that must not be rolled back |
| `observedCycleDate` | Local date string | Yes | Current calculated cycle |
| `timeZoneID` | IANA string | Yes | Zone used for the observation |
| `observedAt` | Instant | Yes | Wall-clock observation time |
| `acknowledgementRequired` | Bool | Yes | Must be true while global state is `timeAdjustmentRequired` |

#### InterfaceSSIDScopeRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `interfaceName` | String | Yes | Canonical BSD interface name |
| `ssidHex` | Hex string | Yes | Raw SSID bytes, never a display-name encoding |

The scope deliberately excludes BSSID because the public preferred-network
configuration mutation is interface-and-SSID scoped. BSSID remains in the
identity snapshot used for exact current-network revalidation.

### 4.1 ArtifactObservationRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `buildManifestSchemaVersion` | UInt | Yes | Embedded `BuildManifestV1` schema version |
| `compiledModeObserved` | `strongBlockingCapable` or `measurementOnly` | Yes | Audit only; cannot promote runtime capability |
| `buildManifestSHA256` | SHA256Hex | Yes | Digest of the canonical embedded build manifest |
| `sourceRevision` | String or null | Yes | Revision recorded by the artifact; null only for a non-release development build |
| `distributionSource` | `githubRelease` | Yes | v1 direct-distribution source |
| `releaseManifestID` | String or null | Yes | Immutable release input when available |
| `releaseManifestSHA256` | SHA256Hex or null | Yes | SHA-256 of the canonical external `ReleaseManifestV1`; required with `releaseManifestID` for candidate/release evidence |
| `releaseAssetSHA256` | SHA256Hex or null | Yes | Digest of the published unsigned GitHub ZIP asset; required before release evidence is accepted |
| `appBundleSHA256` | SHA256Hex or null | Yes | Digest of the exact tested `.app`; when signed, measured after signing with `hbf-app-bundle-v1-sha256` |
| `executableSHA256` | SHA256Hex or null | Yes | Digest of the exact tested app executable, including its post-signing state when the tested path uses local ad hoc signing |
| `codeSignatureStatus` | `unsigned`, `adhoc`, or `developerID` | Yes | Actual status; Developer ID is not required |
| `codeSignatureTeamID` | String or null | Yes | No secret material; normally null for unsigned/ad hoc artifacts |
| `hardenedRuntimeStatus` | `unavailable`, `enabled`, or `disabled` | Yes | Record actual status; an unsigned artifact must use `unavailable` |
| `notarizationStatus` | `notApplicable`, `notarized`, `failed`, or `unknown` | Yes | `notApplicable` is the default published unsigned path; record the actual post-signing status when a derived app is tested |
| `gatekeeperStatus` | `allowed`, `userApproved`, `blocked`, or `notApplicable` | Yes | Exact first-launch result on the target Mac |
| `quarantineStatus` | `present`, `removed`, `absent`, or `unknown` | Yes | State observed for the published unsigned asset or the separately identified post-signing artifact |
| `architecture` | String | Yes | `arm64` for the v1 validation row |
| `macOSBuild` | String | Yes | Exact build observed at launch |
| `observedAt` | Instant | Yes | Wall-clock audit time |

### 4.2 GlobalStateRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `safetyState` | `normal`, `recoveryRequired`, `timeAdjustmentRequired`, `multipleProfilesConnected` | Yes | Global precedence state |
| `recoveryReason` | `corruptStore`, `unknownSchema`, `migrationFailure`, `writeFailure`, `flushFailure`, `arithmeticOverflow`, `counterCapabilityFailure`, `integrityFailure`, `permissionModeFailure`, `archiveDecodeFailure`, `deletionRecovery`, `releaseManifestMismatch`, or null | Yes | Machine-readable reason |
| `timeAdjustment` | TimeAdjustmentRecord or null | Yes | Present only when acknowledgement is required |
| `counterCapability` | `pending`, `passed`, `deterministicFailure` | Yes | Exact GitHub candidate artifact capability state |
| `identityCapability` | `pending`, `passed`, `failed` | Yes | Exact GitHub candidate artifact capability state |

### 4.3 ProfileRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `profileID` | UUIDString | Yes | Stable identifier, never reused |
| `aliasNFC` | String | Yes | Trimmed, NFC-normalized, nonempty, unique |
| `ssidHex` | Hex string | Yes when complete | Raw SSID bytes, not display string |
| `interfaceName` | String | Yes when complete | Canonical BSD name |
| `confirmedBSSIDs` | Sorted unique BSSID array | Yes | Append-only except profile deletion |
| `isComplete` | Bool | Yes | True only when identity, limit, reset day complete |
| `sharesInterfaceSSID` | Bool | Yes | Makes profile measurement-only for blocking |
| `limitBytes` | UInt64String | Yes | 10,000,000 through 1,000,000,000,000 |
| `resetDay` | UInt 1-31 | Yes | Configured value, not fallback date |
| `cycle` | CycleRecord | Yes | Trusted cycle identity |
| `measurement` | MeasurementRecord | Yes | Usage and baseline |
| `protection` | ProtectionRecord | Yes | Limit, pause, retry, failure |
| `createdAt` | Instant | Yes | Event audit |
| `updatedAt` | Instant | Yes | Last profile mutation |

### 4.4 CycleRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `trustedCycleDate` | Local date string | Yes | Effective reset date most recently accepted |
| `cycleStartInstant` | Instant | Yes | First representable local instant for cycle |
| `timeZoneID` | IANA string | Yes | Zone used to calculate trusted cycle |
| `lastTrustedWallClock` | Instant | Yes | Not used as monotonic proof |
| `timeAcknowledgementRequired` | Bool | Yes | Mirrors global state when relevant |

### 4.5 MeasurementRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `usageBytes` | UInt64String | Yes | Exact current cycle usage |
| `baselinePending` | Bool | Yes | No delta may be added until false |
| `lastTrustedIdentity` | IdentitySnapshotRecord or null | Yes | Present only with trusted baseline |
| `lastRXBytes` | UInt64String or null | Yes | Target interface counter |
| `lastTXBytes` | UInt64String or null | Yes | Target interface counter |
| `lastSampleWallClock` | Instant or null | Yes | Actual sample time |
| `lastPersistedUsageAt` | Instant | Yes | Cadence evidence |
| `bytesSinceLastFlush` | UInt64String | Yes | Newly measured bytes since the previous durable snapshot; 10 MB trigger is evaluated only after a valid counter sample |

No monotonic timestamp is persisted. The process may hold monotonic observations in memory only.

While the store is healthy, every successful awake measurement transition is
durably flushed on the nominal five-second sampling cadence. If a valid sample
observes at least 10 MB in `bytesSinceLastFlush`, that transition is flushed
immediately. This byte count covers measured deltas only; it is not a bound on
physical traffic transferred between counter samples. A missed sample or a
failed flush is recorded as a measurement gap or storage failure and must not
be represented as recovered exact usage after relaunch.

### 4.6 IdentitySnapshotRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `profileID` | UUIDString | Yes | Exact resolved profile |
| `interfaceName` | String | Yes | Canonical BSD name |
| `interfaceIndex` | UInt32 | Yes | Counter matching guard |
| `linkState` | `associated` | Yes | A trusted measurement identity is persisted only while associated |
| `ssidHex` | Hex string | Yes | Raw bytes |
| `bssid` | BSSID string | Yes | Confirmed canonical BSSID |

### 4.7 ProtectionRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `limitReached` | Bool | Yes | Current cycle |
| `pauseBlocking` | Bool | Yes | Current cycle only |
| `blockingCapability` | `strongReady`, `notGuaranteed`, `pendingGate`, `measurementOnly`, `sharedInterfaceSSID`, `authorizationUnavailable` | Yes | UI protection reason |
| `lastAuthorizationOutcome` | `neverRequested`, `granted`, `denied`, `unavailable`, `invalidated` | Yes | Audit only |
| `processAuthorizationAvailable` | Bool | No on disk | Runtime-only; must not be persisted |
| `retry` | RetryRecord | Yes | Enforcement retry state |
| `lastSuppressionObservation` | ObservationSummaryRecord or null | Yes | Last suppression-window result; runtime authorization is not included |
| `lastFailureReason` | `counterReadFailed`, `targetIdentityChanged`, `disconnectUnverified`, `authorizationDenied`, `preferenceCommitFailed`, `preferenceReadBackFailed`, `restorationConflict`, `restorationUnverified`, `storageFailure`, `releaseGatePending`, `permissionRequired`, `timeAdjustmentRequired`, or null | Yes | Closed persistent warning source |
| `ownedTransactionID` | UUIDString or null | Yes | Open preference transaction |

If an implementation language cannot omit `processAuthorizationAvailable` from encoding safely, this field must not exist in the persisted type.

### 4.8 RetryRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `state` | `none`, `scheduled`, `running`, `stopped` | Yes | Profile-local |
| `attemptIndex` | UInt | Yes | 0, 1, 2, 3, then 5-minute steady state |
| `nextEligibleAt` | Instant or null | Yes | Wall-clock scheduling hint; revalidated by state |
| `lastAttemptAt` | Instant or null | Yes | Audit |

### 4.9 PreferenceTransactionRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `transactionID` | UUIDString | Yes | Stable transaction id |
| `profileID` | UUIDString | Yes | Owning profile |
| `targetScope` | InterfaceSSIDScopeRecord | Yes | Interface and SSID only for preference mutation |
| `phase` | `prepared`, `applied`, `restorationPending`, `restored`, `conflict`, `unverified` | Yes | No `none` record is stored |
| `observation` | `none`, `pending`, `verified`, `unverified` | Yes | Separate network observation |
| `observationSource` | `none`, `eventBacked`, `pollBacked`, `lifecycleOnly` | Yes | `none` iff observation is `none`; source quality is part of the result |
| `archiveSchemaVersion` | UInt | Yes | Starts at 1 |
| `fingerprintAlgorithm` | `hbf-cwconfig-v1-sha256` | Yes | Exact canonical algorithm id |
| `originalArchive` | Base64url | Yes | Reversible public configuration archive |
| `originalFingerprint` | SHA256Hex | Yes | Fingerprint of original archive semantics |
| `intendedArchive` | Base64url | Yes | Reversible intended configuration archive |
| `intendedFingerprint` | SHA256Hex | Yes | Fingerprint of intended semantics |
| `lastWrittenArchive` | Base64url or null | Yes | Present after applied write |
| `lastWrittenFingerprint` | SHA256Hex or null | Yes | Present after applied write |
| `preparedAt` | Instant | Yes | Must precede system write |
| `appliedAt` | Instant or null | Yes | After read-back intended match |
| `restoredAt` | Instant or null | Yes | After read-back original match |
| `lastError` | `preparedWriteOutcomeUnknown`, `externalPreferenceChange`, `readBackUnavailable`, `commitFailed`, `commitReadBackMismatch`, `archiveDecodeFailure`, `archiveNonRepresentable`, `authorizationUnavailable`, `staleTargetIdentity`, `postDisconnectUnverified`, `storeWriteFailure`, or null | Yes | Closed machine-readable decode/write/read-back/conflict reason |

`hbf-cwconfig-v1-sha256` is SHA-256 over the canonical UTF-8 JSON bytes of `CWConfigurationArchiveV1`. The archive contains exactly the public fields that the current CoreWLAN SDK exposes for this configuration:

```text
CWConfigurationArchiveV1
  schemaVersion: 1
  networkProfiles: [CWNetworkProfileArchiveV1]  // NSOrderedSet order preserved
  requireAdministratorForAssociation: Bool
  requireAdministratorForIBSSMode: Bool
  requireAdministratorForPower: Bool
  rememberJoinedNetworks: Bool

CWNetworkProfileArchiveV1
  ssidHex: lowercase hex for raw ssidData, 1-32 octets
  securityRawValue: UInt64String  // known CWSecurity raw value 0...15 only
```

The canonical JSON representation uses UTF-8, no insignificant whitespace, lexicographically sorted object keys, decimal unsigned strings for `securityRawValue`, lowercase hex for SSID bytes, explicit booleans, and the original array order. The only accepted security values are the known nonnegative `CWSecurity` raw values `0` through `15`; `kCWSecurityUnknown` and every other value are unsupported. The canonical bytes are then encoded as unpadded Base64url for `originalArchive`, `intendedArchive`, and `lastWrittenArchive`. A decoder must parse the archive, validate every field, re-serialize it canonically, and reject any non-canonical or unsupported value before replay.

The adapter creates a mutable copy of the live `CWConfiguration`, copies each existing `CWNetworkProfile` by its raw `ssidData` and `security` value, preserves the ordered profile list, applies only the intended SSID removals, and writes the complete public flag set back to `CWMutableConfiguration`. It must never reconstruct a profile from the display-string `ssid` property. `requireAdministratorForIBSSMode` is deprecated in the current SDK but remains in the v1 archive because it is still a public configuration field; if the selected SDK cannot read, write, or verify it, the field is treated as unavailable. A null or invalid public `ssidData`, an unknown security value, an unavailable public flag, or a read-back field that differs from the canonical archive produces `archiveNonRepresentable` and forbids the preference write.

The equality oracle is canonical-byte equality of two decoded `CWConfigurationArchiveV1` values, cross-checked against the target SDK's `isEqualToConfiguration` result when available. The archive round-trip test passes only when decode, replay, read-back, canonical-byte equality, and the SDK equality result agree. If a future SDK adds a public field that can affect replay, v1 must either add it in a new archive schema version or reject preference mutation on that OS build; it must not silently omit the field.

### 4.9.1 ObservationSummaryRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `result` | `none`, `pending`, `verified`, `unverified` | Yes | Window outcome |
| `source` | `none`, `eventBacked`, `pollBacked`, `lifecycleOnly` | Yes | `eventBacked` is required for a strong-blocking suppression proof |
| `awakeSecondsObserved` | UInt | Yes | Excludes sleep intervals |
| `maxGapSeconds` | UInt | Yes | Maximum monotonic gap between accepted observations |
| `targetAbsentAtEnd` | Bool | Yes | Required for a verified suppression result |

During an active suppression window, `result=verified` requires `source=eventBacked`, `awakeSecondsObserved >= 30`, `maxGapSeconds <= 2`, and `targetAbsentAtEnd=true`. A restoration observation may use `pollBacked` under the same timing coverage, but that result is not a strong-blocking proof. `lifecycleOnly` never proves presence or absence.

Cross-field transaction invariants are mandatory:

- `phase=prepared` requires `originalArchive`, `intendedArchive`, both
  fingerprints, `preparedAt`, and null `appliedAt`, `restoredAt`, and
  `lastWrittenFingerprint`.
- `phase=applied` or `phase=restorationPending` requires a non-null
  `lastWrittenArchive`, `lastWrittenFingerprint`, and `appliedAt`.
- `phase=restored` requires `restoredAt`, a successful original read-back, and
  `observation` equal to `none`, `pending`, `verified`, or `unverified`;
  `observationSource` must be `none` when the observation is `none`, and must
  not be `lifecycleOnly` when the observation is `verified`. An `unverified`
  observation is valid when the configuration read-back succeeded but the
  separate post-restoration observation window was interrupted or inconclusive.
- `phase=conflict` requires `lastError=externalPreferenceChange` and forbids
  any restoration write until a new user-authorized recovery action is
  defined.
- `phase=unverified` requires a non-null `lastError` and forbids a new
  preference value until reconciliation or explicit recovery completes.

### 4.10 CommandResultRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `commandName` | `createProfileFromCurrentNetwork`, `createProfileManualIdentity`, `appendBSSID`, `selectProfile`, `togglePauseBlocking`, `manualResetUsage`, `changeLimit`, `changeResetDay`, `requestBlockingAuthorization`, `recordManualReconnectIntent`, `retryRestoration`, `muteFailureNotification`, `deleteProfile`, or `quitApplication` | Yes | Closed command-name enum; prevents a key from being reused for another command |
| `idempotencyKey` | UUIDString | Yes | Generated by HBF; scoped with `installationID` |
| `outcome` | `succeeded`, `cancelled`, `rejected`, or `failed` | Yes | The user-visible command outcome |
| `resultCode` | `success`, `cancelled`, `staleSnapshot`, `validationFailed`, `permissionRequired`, `authorizationRequired`, `conflict`, `unverified`, `recoveryRequired`, `notFound`, or `ineligible` | Yes | Closed command-result enum |
| `storeRevision` | UInt64String | Yes | Revision at which the outcome became durable |
| `resultDigest` | SHA256Hex | Yes | Digest of the typed result summary, with no secrets or PII |
| `recordedAt` | Instant | Yes | Result time |

The command ledger is written in the same canonical store transition as the
domain mutation. A repeated command name and idempotency key returns the
stored historical outcome and performs no second domain mutation or system
side effect. For `requestBlockingAuthorization` and
`recordManualReconnectIntent`, the dispatcher separately evaluates the
current process-local effect: a historical success does not recreate an
authorization object or a one-shot token after relaunch, logout, or reboot.
The current response therefore reports `authorizationRequired`,
`intentExpired`, or `intentUnavailable` when the volatile effect is absent,
even though the durable command outcome remains successful. A system side
effect that can outlive a process boundary remains governed by its preference
transaction and reconciliation record; the command ledger is not used as a
substitute for `Prepared`/`Applied` recovery. Completed command results older
than the current cycle plus 90 days are purged with the event-retention
maintenance transition.

### 4.11 NotificationStateRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `profileNotificationStates` | Map profileID to ProfileNotificationRecord | Yes | Profile-local |
| `systemAuthorization` | `notDetermined`, `authorized`, `denied`, `provisional`, `unknown` | Yes | UI guidance only |

### 4.12 ProfileNotificationRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `successNotifiedCycleDate` | Local date or null | Yes | Once per profile/cycle |
| `failureMute` | `none`, `untilInstant`, `untilCycleEnds` | Yes | Notification only |
| `muteExpiresAt` | Instant or null | Yes | For 10-minute/1-hour mute |
| `muteCycleDate` | Local date or null | Yes | For cycle mute |
| `lastFailureNotificationAt` | Instant or null | Yes | Five-minute throttle |

### 4.13 EventLogRecord and EventRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `retentionPolicy` | `currentCyclePlus90Days` | Yes | Fixed v1 policy |
| `events` | EventRecord array | Yes | Sorted by event sequence |

Event fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `eventID` | UUIDString | Yes | Unique |
| `sequence` | UInt64String | Yes | Monotonic within store |
| `storeRevision` | UInt64String | Yes | Revision after event commit |
| `occurredAt` | Instant | Yes | Wall-clock |
| `profileID` | UUIDString or null | Yes | Null for global events |
| `transactionID` | UUIDString or null | Yes | For preference events |
| `kind` | `launch`, `migration`, `storeFailure`, `counterSample`, `counterBaseline`, `counterDiscontinuity`, `cycleTransition`, `timeAdjustment`, `identityResolution`, `permission`, `authorization`, `blockingAttempt`, `blockingFailure`, `preferencePrepared`, `preferenceApplied`, `restorationAttempt`, `restorationConflict`, `restorationResult`, `manualReset`, `limitChange`, `pauseChange`, `profileChange`, `profileDeletion`, `notification`, `lifecycle`, `artifactAudit`, or `recovery` | Yes | Fixed v1 event kind |
| `redactionClass` | `public`, `localSensitive`, `secretProhibited` | Yes | Controls report export |
| `details` | `EventDetailsV1` typed object | Yes | The `kind` selects a fixed details variant; must exclude credentials, packets, URLs, coordinates |

Events older than the current cycle and preceding 90 days are purged during normal store maintenance. Normal retention purge is a durable store transition with its own global event. Profile deletion is stricter: all events with a deleted `profileID` are removed before deletion completes, and the retained deletion event, if any, is global with `profileID=null`.

`EventDetailsV1` may contain only the following typed fields: `reason` from a
closed reason enum, `oldState`, `newState`, `profileID`, `transactionID`,
`storeRevision`, `bytes`, `attemptIndex`, `fingerprint`, `permissionOutcome`,
`authorizationOutcome`, `observationOutcome`, `observationSource`,
`observationGapSeconds`, and `redactionClass`. Each event
kind declares which subset is legal. Unknown details fields or a
`secretProhibited` value in a persisted event are schema errors.

The v1 kind-to-field contract is:

| Event kinds | Required or permitted details |
|---|---|
| `counterSample`, `counterBaseline`, `counterDiscontinuity` | `profileID`, `bytes`, `reason`, `oldState`, `newState` |
| `identityResolution`, `permission` | `profileID`, `permissionOutcome`, `reason`, `oldState`, `newState` |
| `authorization` | `profileID`, `authorizationOutcome`, `reason`, `oldState`, `newState` |
| `blockingAttempt`, `blockingFailure` | `profileID`, `transactionID`, `attemptIndex`, `reason`, `oldState`, `newState`, `observationOutcome`, `observationSource`, `observationGapSeconds` |
| `preferencePrepared`, `preferenceApplied`, `restorationAttempt`, `restorationConflict`, `restorationResult` | `profileID`, `transactionID`, `fingerprint`, `reason`, `oldState`, `newState`, `observationOutcome`, `observationSource`, `observationGapSeconds` |
| `profileChange`, `manualReset`, `limitChange`, `pauseChange` | `profileID`, `reason`, `oldState`, `newState` |
| `profileDeletion` | `profileID=null`, `reason=profileDeleted`, `oldState`, `newState`, `storeRevision`; the deleted identifier is represented only by `tombstones.json` |
| `cycleTransition`, `timeAdjustment`, `lifecycle`, `notification`, `artifactAudit`, `migration`, `recovery`, `storeFailure` | `reason`, `oldState`, `newState`, `storeRevision` |
| `launch` | `storeRevision`, `reason`, `newState` |

Fields not listed for an event kind must be absent, not merely null.

### 4.14 TombstoneRecord

| Field | Type | Required | Notes |
|---|---|---:|---|
| `profileID` | UUIDString | Yes | Deleted stable id |
| `deletedAt` | Instant | Yes | Wall-clock |
| `deletionRevision` | UInt64String | Yes | Store revision that initiated deletion |
| `aliasDigest` | SHA256Hex | Yes | Digest of normalized alias for diagnostics |
| `purgeCompleted` | Bool | Yes | Recovery resumes purge when false |

Tombstones are applied before LKG or recovery-copy profiles are exposed. An older LKG entry with a tombstoned profile id must be ignored and purged.

### 4.15 Cross-record invariants

- Every profile id in `profiles`, `preferenceTransactions`, notification
  state, and profile-scoped event references must be active in `profiles`.
  A completed deletion must not leave a profile-scoped reference in the
  canonical store; the tombstone protects recovery copies but does not make a
  deleted reference valid.
- A retained `profileDeletion` event must have `profileID=null` and must not
  contain the deleted profile identifier in its typed details.
- `selectedProfileID` must be null or refer to an active profile.
- `ownedTransactionID` must be null or refer to exactly one open transaction
  for the same profile and interface scope.
- Every `idempotencyKey` is unique within one `installationID` and one
  `commandName`; a duplicate key must resolve to the original
  `CommandResultRecord`.
- When `releaseManifestID` is present for candidate or release evidence,
  `releaseManifestSHA256`, `releaseAssetSHA256`, `appBundleSHA256`,
  `executableSHA256`, and `buildManifestSHA256` must all be present and must
  be compared as separate values; an executable digest cannot substitute for
  the app-bundle digest.
- `globalState.counterCapability=deterministicFailure` forces
  `globalState.safetyState=recoveryRequired` and forbids a measurement-only
  claim.
- `globalState.safetyState=recoveryRequired` forbids measurement and all
  network side effects.
- `globalState.safetyState=timeAdjustmentRequired` forbids measurement,
  enforcement, suppression, disconnect, and new preference writes. It permits
  only an ownership-proven cleanup restoration of an already open transaction
  when the current configuration matches HBF's last-written fingerprint, the
  archive validates, current-process authorization is available, and write,
  read-back, and persistence guards succeed. Otherwise no preference write is
  allowed.
- `tombstoneDigest` is SHA-256 over the canonical sorted tombstone array,
  using the same UTF-8 JSON rules as Section 2.

---

## 5. Migration Contract

Supported migrations are explicit functions from one schema version to the next. Each migration must:

1. Decode the full source schema with unknown-field policy documented for that source version.
2. Validate byte counts, revisions, identity encodings, and transaction archive versions.
3. Preserve usage and trusted cycle state.
4. Preserve tombstones before exposing profiles.
5. Write a new canonical file through the atomic replacement path.
6. Validate the destination and update LKG only after validation succeeds.

Unknown future schemas, failed migrations, failed archive decoding, or unsupported transaction archive versions enter `recoveryRequired`. HBF must not create a new zero-usage store over a failed migration.

---

## 6. Integrity and Anti-Rollback Scope

HBF is a non-sandboxed same-user application and cannot cryptographically prevent a determined same-user process from editing its files. The v1 integrity goal is fail-closed detection of accidental corruption, symlink/path attacks, interrupted writes, and obvious rollback to older HBF stores.

Required checks:

- Open files without following symlinks where platform APIs allow it; reject symlinked state files.
- Verify canonical path remains inside the application support directory.
- Verify owner uid is the current user and mode is no broader than the required mode.
- Verify `storeRevision` never decreases relative to the LKG and installation marker metadata.
- Verify `installationID` is stable across canonical, LKG, installation marker, and tombstone files.
- Verify `tombstoneDigest` matches `tombstones.json`.
- Verify the commit journal's installation id, target revision, phase, and recorded digests against every required destination file.
- Verify every transaction fingerprint matches its archive.
- Verify event sequences are nondecreasing and bound to store revisions.

If rollback is suspected, HBF enters `recoveryRequired` and offers explicit recovery choices. It must not choose the lower revision automatically. This is anti-rollback detection, not tamper-proof security.

---

## 7. Transaction Ordering

The following transitions are atomic at the product-contract level. They may use multiple file replacements internally, but each transition must use `CommitJournalV1`, and the UI must not report success unless every required file and journal phase validates.

| Transition | Required order |
|---|---|
| First completed profile | Write and validate `state.json`; update LKG; then write `installation.json`; then emit success |
| Measurement sample | Validate identity/cycle; compute checked delta; write `state.json`; validate; update LKG; emit usage |
| Limit reached | Write usage/baseline and `limitReached` in the same store revision; only then schedule enforcement |
| Preference prepare | Write `prepared` transaction with original/intended archives and fingerprints; flush; only then call CoreWLAN |
| Preference applied | Write system value; read back; then write `applied` with last-written archive/fingerprint |
| Restoration | Check current fingerprint; write original; read back; then write `restored`; then start separate observation |
| Profile deletion | Write tombstone with `purgeCompleted=false`; purge active/LKG/transactions/profile-scoped events; mark tombstone complete; append a global `profileDeletion` event with `profileID=null`; validate all files |
| Recovery from LKG | Apply tombstones first; validate revision and installation id; then make selected copy canonical |

For every row above, a crash after any listed file operation leaves the journal
in the preceding phase or in a phase whose recorded digest does not match the
destination. Launch recovery must preserve the files and enter
`recoveryRequired`, except for the explicit incomplete-deletion continuation
rule. A valid but newer canonical file is not sufficient evidence to resume a
measurement transition without a matching journal phase and digest.

---

## 8. Local Evidence and Redacted Reports

Local evidence is the source of truth for GitHub-candidate and release validation. Redacted reports are derived artifacts for sharing.

| Data | Local evidence | Redacted report |
|---|---|---|
| Interface name | Allowed | Allowed only when operator marks nonidentifying; otherwise hash |
| SSID bytes | Allowed as local-sensitive | Hash or operator-approved label |
| BSSID | Allowed as local-sensitive | Hash or last octets removed |
| Configuration archive | Allowed if it contains no credentials | Not included; only fingerprints and semantic summary |
| Fingerprints | Allowed | Allowed |
| Authorization result | Allowed | Allowed, no credentials |
| Packet contents, URLs, credentials, coordinates | Prohibited | Prohibited |
| Exact GitHub asset/app-bundle/executable hashes and actual signature identity | Allowed | Allowed |

The report generator must fail if a `secretProhibited` event detail is present. HBF does not send remote telemetry in v1.

---

## 9. Non-Sandboxed Threat Model

| Threat | v1 mitigation | Residual risk |
|---|---|---|
| Same-user process edits store | Owner-only modes, symlink rejection, revision/digest validation, LKG recovery | Same-user tampering cannot be fully prevented without a different architecture |
| Rollback to older store | Monotonic revision checks across canonical/LKG/marker/tombstones | Offline backup restore can still require user recovery decision |
| Symlink or path redirection | Canonical path and no-follow checks | Platform API limitations must be recorded |
| Preference conflict by user or another process | Fingerprint ownership check before restoration | HBF leaves user change untouched and may remain unverified |
| Authorization credential leakage | Never persisted; memory-only object | Process memory remains in scope of OS security, not HBF store |
| PII leakage in reports | Redaction class and report generator checks | Operator-approved labels may still identify a network to the operator |
| Non-sandboxed broader file access | Least-privilege app code, owner-only state path, actual Hardened Runtime/notarization status recorded when present, and GitHub first-launch guidance | App compromise has same-user process privileges; an unsigned artifact receives no signature-based trust claim |
