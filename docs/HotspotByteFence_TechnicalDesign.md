# Hotspot Byte Fence (HBF) — Technical Design

**Version:** 0.2  
**Date:** 2026-09-01  
**Product baseline:** `HotspotByteFence_PRD.md`  
**Implementation status:** Domain and measurement implementation may begin; strong-blocking integration remains gated by the GitHub-candidate feasibility report.

Required companion contracts:

- [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md) defines the complete state-transition table, command contract, fail-closed disconnect algorithm, `SFAuthorization` boundary, and UI/accessibility/localization mapping.
- [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md) defines the concrete v1 persistence records, serialization, migration, integrity checks, LKG, tombstones, preference transaction ordering, local evidence, redacted reports, and non-sandboxed threat model.
- [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md) maps AC-01 through AC-81 to test IDs, fixtures, oracles, and F/R gates.
- [`HotspotByteFence_DecisionsNeeded.md`](HotspotByteFence_DecisionsNeeded.md) records binding implementation and release decisions, while runtime facts remain explicit candidate-gate inputs.
- [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md) defines the real-Mac topology, destructive-test safeguards, evidence paths, and operator confirmation contract.

---

## 1. Approved Architecture Decision

HBF v1 is a directly distributed GitHub Copy App: a non-sandboxed, `arm64` macOS application that uses public APIs only. The published GitHub package is an unsigned ZIP. Before supported use, the user must ad hoc-sign the extracted `.app` locally; this is an installation prerequisite for the supported path. Developer ID signing, notarization, and Hardened Runtime are not distribution prerequisites. The unsigned asset digest is verified before signing, and the post-signing app or executable digest is recorded separately. A locally signed app is a derived artifact and cannot inherit exact-candidate gate evidence unless that exact signed artifact is tested. The exact artifact's signature, Hardened Runtime, notarization, quarantine, and Gatekeeper results are recorded without turning them into mandatory Developer ID capability claims. HBF does not install a privileged helper or daemon.

This posture is intentional. Strong blocking requires an administrator-authorized CoreWLAN configuration commit, while Authorization Services is unavailable to an App Sandbox process. `SFAuthorization` is created only for an explicit blocking authorization action, remains in memory, and is invalidated when it is no longer needed. A previous authorization result is audit history only; it cannot authorize a later process.

The initial validation target is macOS 26.6.2 build 25G83 on `arm64`. The macOS 13.0 deployment target is a compilation floor, not a support claim.

### 1.1 Assumptions

- One HBF process owns the canonical store and runtime engine.
- Only one resolved completed profile is measured at a time.
- All network and clock adapters can fail and must return explicit results.
- The exact artifact declares either strong-blocking-capable or measurement-only behavior in immutable build metadata or its release manifest.
- Candidate approval is a release-process record bound to the exact executable and GitHub asset digest, with signature status recorded when present. It is not a mutable user preference.
- Local ad hoc signing is a supported-installation prerequisite. Published unsigned-asset identity, post-signing app identity, and exact-candidate gate evidence are recorded as separate values; local signing does not grant an entitlement or release approval.
- Operator validation mode is a non-persisted launch context for the same exact GitHub candidate artifact. It changes test-facing status and confirmation requirements, not production logic.

### 1.2 Non-goals

- App Sandbox support in v1
- A privileged helper, launch daemon, or privileged XPC service
- Mac App Store distribution
- Remote telemetry or cloud state
- Private Wi-Fi APIs or BSSID-specific preference mutation

---

## 2. System Structure

```text
SwiftUI MenuBarExtra / Settings
              |
              v
       AppCoordinator (@MainActor)
              |
              v
        RuntimeEngine (actor)
       /    |      |       \
      v     v      v        v
 Identity Counter Cycle  Enforcement
 Adapter  Adapter Engine   Engine
      \     |      |        /
       \    |      |       /
        PersistenceStore actor
              |
      versioned files + LKG copy
```

`RuntimeEngine` is the sole coordinator for profile resolution, measurement transitions, cycle changes, and enforcement decisions. UI code submits commands and observes immutable snapshots; it does not call CoreWLAN or mutate persisted state directly.

### 2.1 Components

| Component | Responsibility | Required injected boundary |
|---|---|---|
| `AppCoordinator` | Lifecycle wiring, menu/settings presentation, user commands | `RuntimeEngine` |
| `RuntimeEngine` | Serial event ordering and compositional state reduction | clock, lifecycle, adapters, store |
| `WiFiIdentityAdapter` | Interface enumeration, SSID bytes, BSSID, optional link events, and polling snapshots | `CWWiFiClient`-vended interfaces plus injected observation clock |
| `InterfaceCounterAdapter` | Checked 64-bit RX/TX snapshots by interface index/name | `NET_RT_IFLIST2`, `if_msghdr2`, `if_data64` |
| `CycleEngine` | Effective cycle, clock-adjustment detection, reset decisions | wall and monotonic clocks, calendar, time zone |
| `MeasurementEngine` | Baseline ownership, delta checks, usage overflow checks | identity, counters, cycle |
| `AuthorizationProvider` | Explicit in-memory administrator authorization | `SFAuthorization` |
| `PreferenceCoordinator` | Configuration archive, fingerprint, commit, restoration | `CWConfiguration`, `commitConfiguration` |
| `Disconnector` | Exact-target revalidation and current-interface disconnect | `CWInterface.disassociate()` |
| `EnforcementEngine` | Limit transition, retry schedule, suppression observation, and observation-quality classification | authorization, preference, disconnector, observation source |
| `PersistenceStore` | Atomic durable state, LKG recovery, migrations, tombstones | application-support filesystem |
| `NotificationService` | Authorization, success/failure notifications, throttle | `UNUserNotificationCenter` |
| `LoginItemService` | Login registration and status | `SMAppService.mainApp` |

---

## 3. Concurrency and Event Ordering

All domain mutations execute inside `RuntimeEngine`. CoreWLAN callbacks, five-second timer events, sleep/wake notifications, settings commands, and persistence completions are converted into ordered runtime events.

For a target interface, identity resolution, counter sampling, preference mutation, disconnect, and restoration are serialized. At most one open preference transaction may exist for an interface. A stale sample or identity snapshot cannot cross a preference write, cycle transition, sleep/wake boundary, or manual reset.

The event priority at a single scheduling point is:

1. Store integrity, schema, migration, deterministic counter-capability, and arithmetic overflow failures.
2. Sleep, wake, quit, relaunch, and lifecycle closure.
3. Time-adjustment and clock rollback events that are backward or uncertain.
4. Open preference-transaction reconciliation required by lifecycle closure, a cycle transition, or an eligibility/build-mode change.
5. Deterministic forward cycle transition and reset-day change effects.
6. Identity permission and current Wi-Fi resolution.
7. Authorization and build-mode capability changes.
8. Enforcement retry, blocking command, restoration command, and suppression observation.
9. Counter sample and baseline creation.
10. UI-only selection, language, mute, and settings display changes.

This priority list is the reducer oracle and must remain identical to Section 2 of `HotspotByteFence_StateModel.md`. The StateModel table is normative for transition behavior; this copy is an implementation-facing mirror and may not introduce a second ordering.

Every event returns a new immutable UI snapshot after any required durable write succeeds. A required persistence failure prevents the corresponding state transition from becoming externally visible as successful.

The complete event, command, guard, durable-write, side-effect, retry, and failure table is normative in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md). The reducer implementation must use that table as its acceptance oracle. Any new runtime event must be added there before code can rely on it.

---

## 4. Compositional State Model

HBF does not use one flat application-state enum. The runtime snapshot combines the following dimensions.

| Dimension | States | Scope |
|---|---|---|
| Global safety | `Normal`, `RecoveryRequired`, `TimeAdjustmentRequired`, `MultipleProfilesConnected` | Application; multiple-profile effect limited to current resolution |
| Connection | `Monitoring`, `Disconnected`, `UnknownNetwork`, `NeedsBSSIDConfirmation`, `LocationPermissionRequired`, `MeasurementUnavailable` | Current resolution/profile |
| Selection | `None`, `SelectedDisconnected`, `SelectedConnected` | UI |
| Protection | `StrongBlockingReady`, `LimitReached`, `BlockingFailed`, `BlockingPaused`, `BlockingNotGuaranteed`, `RestorationConflict` | Profile |
| Preference transaction | `None`, `Prepared`, `Applied`, `RestorationPending`, `Restored`, `Conflict`, `Unverified` | Interface/profile |
| Restoration observation | `None`, `Pending`, `Verified`, `Unverified` | Transaction |
| Candidate lifecycle | `Production`, `OperatorValidation` | Process launch context; never persisted as user configuration |

### 4.1 Global precedence

`RecoveryRequired` and `TimeAdjustmentRequired` stop measurement and every network action. `MultipleProfilesConnected` is application-global for state presentation, but stops measurement and blocking only for the currently resolved target set until one target remains. Profile management and settings remain available. A local `MeasurementUnavailable` stops only the affected target but cannot override a global state.

### 4.2 Selected, connected, and enforced profiles

- Selection changes only the management context.
- Exact interface name, SSID bytes, and confirmed BSSID determine the connected profile.
- Enforcement follows the eligible limit-reached profile even when another profile is selected.
- A disconnected selected profile may be reset or paused but is never measured or automatically reconnected.

The internal persisted enum values, user-facing localization keys, accessibility identifiers, and unknown-enum recovery behavior are defined in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md). User-facing labels such as `Recovery Required` are never persistence keys.

---

## 5. Measurement Flow

For each nominal five-second tick while awake:

1. Resolve all Wi-Fi interfaces through the long-lived `CWWiFiClient`.
2. Apply global recovery, permission, ambiguity, and multi-target rules.
3. Calculate the current profile cycle before reading or applying a delta.
4. Obtain the exact target interface index and checked `UInt64` RX/TX counters.
5. Reject the sample on parse failure, index mismatch, counter regression, checked-add overflow, identity change, lifecycle boundary, or cycle boundary.
6. When no trusted baseline exists, persist a new baseline and add no traffic.
7. Otherwise compute checked RX and TX deltas, checked total delta, and checked accumulated usage.
8. Persist the new usage and baseline according to the five-second/10 MB rule.
9. Evaluate the exact-byte limit after the durable measurement transition.

`MeasurementUnavailable` is used only for a transient failure on a capability already proven for the exact GitHub candidate artifact. A deterministic capability failure enters global `RecoveryRequired`.

---

## 6. Strong-Blocking Transaction

The production and operator-validation paths use the same transaction logic.

1. Persist the profile's limit-reached transition.
2. Re-read the exact interface, SSID bytes, and BSSID.
3. Read the complete public `CWConfiguration` and create immutable original and intended archives.
4. Compute versioned fingerprints over every public field represented by the archive.
5. If target entries are present, persist and flush `Prepared` before any system write.
6. Revalidate the exact target immediately before `commitConfiguration`.
7. Commit with the in-memory `SFAuthorization`, read back, and compare the complete intended configuration.
8. Mark `Applied` only after read-back succeeds. When the target entry was already absent, record a verified no-op without an applied transaction.
9. Re-read the current identity immediately before `disassociate()`.
10. Call `disassociate()` only when the final observation still matches the exact target. If it does not, make no call. Because the public API has no atomic target guard, the implementation must not claim that this pre-call check eliminates the residual target-switch window; that boundary remains a release-gate result.
11. Query again until the target is confirmed absent or the bounded verification attempt fails.
12. Observe the interface for 30 awake seconds. A reconnect without a valid one-shot manual-intent token fails suppression.

An uncertain commit or read-back enters `Unverified`. It does not authorize another preference value. Retry enforcement may proceed only after transaction reconciliation determines a safe next action.

Because `CWInterface.disassociate()` acts on the interface's current network and public CoreWLAN does not expose an atomic SSID/BSSID guard for the call, HBF does not claim stronger atomicity than it can prove. The v1 implementation must use the fail-closed algorithm in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md): exact identity is re-read before the preference write, again before the disconnect call, and the result is accepted only after bounded post-query absence of the target. Any residual target-switch window remains a release-gate risk until proven on the exact supported macOS build.

### 6.1 Candidate gate

The candidate executable is launched in explicit operator-validation context. Each destructive network case requires a fresh warning and confirmation. The UI displays `Validation Candidate`. The artifact may be distributed only with its measured mode and gate status declared; it cannot claim strong blocking until its identity, counter, suppression, preservation, and restoration reports pass.

The report is bound to application version, source revision, GitHub release asset SHA-256, actual code-signature status, architecture, and exact macOS build. Notarization or stapling, when present, must not replace or rebuild the tested executable.

### 6.2 Observation implementation

`EnforcementEngine` consumes `WiFiObservationV1` values rather than depending directly on CoreWLAN callbacks. The adapter produces `eventBacked` values from an actual `CWWiFiClient` link/SSID/BSSID callback and `pollBacked` values from a one-second awake poll or an immediate read after a public lifecycle notification. A lifecycle notification without a current-state read is `lifecycleOnly`.

The observation coordinator records the monotonic interval, awake duration, source, and maximum gap, then emits the persisted summary fields `result`, `source`, `awakeSecondsObserved`, `maxGapSeconds`, and `targetAbsentAtEnd`. It closes a window as `Unverified` when sleep, quit, relaunch, or a gap over two seconds occurs. Strong-blocking suppression requires event-backed coverage for 30 awake seconds and a target-absent final observation. Restoration observation may use poll-backed coverage, but the two results are stored and reported separately.

---

## 7. Preference Restoration

Restoration does not require the target SSID or BSSID to remain connected. It requires:

- the exact target interface;
- an open HBF transaction;
- decodable original, intended, and last-written archives;
- matching fingerprint algorithm versions; and
- a current configuration fingerprint equal to HBF's last-written fingerprint.

If ownership matches, HBF writes the original configuration and verifies the complete read-back before marking the transaction `Restored`. If ownership differs, it performs no write and enters `Conflict`. Decode or read-back uncertainty enters `Unverified`.

After verified read-back, HBF separately observes network state for 30 awake seconds. A macOS-initiated or unclassified reconnection is an expected possible consequence of restoring automatic connection and does not invalidate configuration restoration. An interrupted window changes only the observation result to `Unverified`.

---

## 8. Persistence Design

### 8.1 Files

All files reside in the app's Application Support directory, whose directory mode is owner-only. State files use owner read/write permissions.

| File | Purpose |
|---|---|
| `state.json` | Canonical versioned store |
| `state.lkg.json` | Last-known-good validated revision |
| `installation.json` | Crash-safe completed-profile marker |
| `tombstones.json` | Deleted stable profile identifiers and deletion revision |

Temporary replacement files use unique names in the same directory. A commit writes and flushes the temporary file, atomically replaces the destination, validates the decoded revision, and updates the LKG copy only after canonical validation succeeds.

The concrete file modes, symlink/path checks, schema fields, serialization formats, migration rules, LKG selection, tombstone ordering, local-evidence storage, redacted-report generation, and anti-rollback scope are defined in [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md). This technical design must not be implemented with looser records than that schema.

### 8.2 Logical schema

```text
StoreEnvelope
  schemaVersion: UInt
  storeRevision: UInt64-as-decimal-string
  previousGoodRevision: UInt64-as-decimal-string?
  installationID: UUIDString
  hasCompletedProfile: Bool
  observedArtifact: ArtifactObservationRecord
  globalState
  selectedProfileID?
  languageOverride: system | ko | en
  profiles: [ProfileRecord]
  preferenceTransactions: [PreferenceTransaction]
  commandResults: [CommandResultRecord]
  notificationState: NotificationStateRecord
  eventLog: EventLogRecord
  tombstoneDigest: SHA256Hex
  integrity: IntegrityRecord
```

Every byte count and revision that can exceed JSON's exact integer range is encoded as a canonical decimal string and decoded with checked conversion. Unknown fields may be preserved only when the version-specific migration explicitly supports them; an unknown future schema enters recovery.

`ProfileRecord`, `PreferenceTransaction`, `CommandResultRecord`, `notificationState`, `events`, `tombstoneDigest`, and `integrity` are not placeholder implementation choices. Their v1 fields, required/nullable status, enum values, archive format, fingerprint algorithm id, transaction ordering, event retention, and privacy/redaction classes are fixed in [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md).

### 8.3 Recovery and deletion

- A missing canonical store is first-run only when no completed-profile marker, recovery copy, or valid completed store exists.
- Recovery never replaces known usage with zero.
- A completed-profile commit validates the store before writing the installation marker.
- Profile deletion first commits a tombstone, then purges active/LKG records, transactions, and profile-scoped events, and finally appends only a global deletion event with `profileID=null`.
- Recovery-copy selection applies tombstones before exposing profiles.
- Authorization objects, credentials, packet contents, URLs, and geographic coordinates are never persisted.

---

## 9. Permission and Privilege Boundary

| Boundary | v1 rule | Failure behavior |
|---|---|---|
| App Sandbox | Disabled by approved design | A sandbox-enabled production artifact fails the distribution posture check |
| Hardened Runtime | Optional; record `enabled`, `disabled`, or `unavailable` for the exact artifact | An unsigned artifact must not claim Hardened Runtime; no release block solely for absence |
| Developer ID signing/notarization | Not required for GitHub direct distribution; record actual signature and notarization status | Apply user-visible Gatekeeper/quarantine launch instructions; no Developer ID gate |
| Location Services | Requested only for Wi-Fi identity | Pause identity-dependent measurement/blocking |
| Counter access | Public 64-bit `sysctl` path | Deterministic failure: global recovery; transient failure: local unavailable |
| Administrator authorization | Explicit `SFAuthorization`, memory-only, least privilege | Measurement may continue; blocking not guaranteed |
| Wi-Fi preference mutation | Public CoreWLAN only, reversible transaction first | No safe round-trip: no write |
| Local state | Application Support, owner-only permissions | Required write failure: global recovery |
| Login launch | `SMAppService.mainApp` after local ad hoc signing and user approval | If signing or approval is unavailable, run only while open and disclose the downtime gap |
| Notifications | `UNUserNotificationCenter` | Persistent in-app warning remains |

The build must carry `NSLocationUsageDescription` for macOS SSID/BSSID identity access, with Korean and English localized purpose strings. The published GitHub asset is unsigned, and supported user setup requires local ad hoc signing before first launch. The `com.apple.wifi.events` entitlement is not assumed to be available: the candidate defaults to polling and public notifications unless the exact tested artifact proves the event path. If an event path requires the entitlement and the exact artifact does not have it, HBF must not claim entitlement-backed event behavior. Entitlement, Info.plist, actual Hardened Runtime/signature/notarization status, App Sandbox absence, release manifest, Gatekeeper result, and report checks are listed in [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md).

### 9.1 Authorization boundary

`SFAuthorization` is requested only by an explicit user action or explicit restoration retry that the user initiated. The candidate must record the exact CoreWLAN configuration-commit right string and Authorization Services flags before strong-blocking integration proceeds. The default flags for the explicit action are `interactionAllowed`, `extendRights`, and `preAuthorize` when the selected public right supports them. Launch checks and automatic retries must use only prompt-free checks. A relaunch with an open preference transaction and no usable in-memory authorization leaves the transaction in `RestorationPending`, shows `Blocking Not Guaranteed`, and performs no new preference write until the user explicitly authorizes restoration. The detailed lifecycle contract is in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md).

---

## 10. Build and Release Modes

The executable contains a generated, immutable `BuildManifestV1` resource and a matching compile-time capability constant. Both must agree before the runtime starts. The mutable store records only the observed values for audit and can never promote a capability.

`BuildManifestV1` contains exactly:

```text
schemaVersion: 1
bundleIdentifier: com.copylawbot.hotspotbytefence
applicationVersion: String
sourceRevision: String or null
compiledMode: strongBlockingCapable | measurementOnly
architecture: arm64
minimumOS: "13.0"
counterSourceID: netRTInterfaceList2-ifData64-v1
strongObservationRequirement: eventBacked-30s-awake-v1
```

The manifest is canonical UTF-8 JSON with sorted keys and no insignificant whitespace. HBF refuses to start a measurement or blocking engine when the manifest is malformed, its bundle identifier or architecture does not match the process, its `compiledMode` disagrees with the compile-time constant, or its counter/observation source identifiers are unknown. `BuildManifestV1` is an artifact description, not an authorization or a release approval token.

The external `ReleaseManifestV1` is maintained by the release process. Its exact schema is fixed below:

In this schema, `releaseAssetSHA256` identifies the published unsigned ZIP, while `executableSHA256` identifies the exact executable used for the candidate or release test. When the tested path includes local ad hoc signing, the latter is the post-signing executable digest and the signing procedure and actual signature state must be recorded with the evidence.

```text
ReleaseManifestV1
  schemaVersion: 1
  releaseManifestID: nonempty ASCII String
  releaseStatus: validationCandidate | approvedStrongBlocking | measurementOnly
  applicationVersion: String
  sourceRevision: nonempty String
  githubReleaseTag: nonempty String
  releaseAssetSHA256: SHA256Hex
  executableSHA256: SHA256Hex
  embeddedBuildManifestSHA256: SHA256Hex
  architecture: arm64
  macOSSupportRows: [SupportRowV1]
  codeSignatureStatus: unsigned | adhoc | developerID
  codeSignatureTeamID: String or null
  hardenedRuntimeStatus: unavailable | enabled | disabled
  notarizationStatus: notApplicable | notarized | failed | unknown
  quarantineStatus: present | removed | absent | unknown
  gatekeeperStatus: allowed | userApproved | blocked | notApplicable
  gateReportSHA256: Object<GateID, SHA256Hex or null>
  gateVerdicts: Object<GateID, PASS | FAIL | PENDING | BLOCKED>

SupportRowV1
  macOSVersion: String
  macOSBuild: String
  architecture: arm64
  supportStatus: strongBlocking | measurementOnly | unsupported
```

`GateID` is exactly one of `F-01` through `F-12` or `R-01` through `R-15`. Both gate objects contain the complete fixed key set in lexicographic order. A null report digest is allowed only for a gate that is not applicable or has not run; `approvedStrongBlocking` requires every F/R digest to be non-null and every corresponding verdict to be `PASS`. `releaseStatus=measurementOnly` requires the identity and counter capability gates to be `PASS` and forbids a strong-blocking claim. `releaseStatus=validationCandidate` cannot be distributed as a protected user release.

The canonical external manifest is UTF-8 JSON with no insignificant whitespace, lexicographically sorted object keys, the declared array order for `macOSSupportRows`, and explicit nulls and enum strings. `releaseManifestSHA256` is the SHA-256 of those canonical bytes and is recorded outside the manifest; it is not a self-referential field. A strong-blocking distribution claim is valid only when all fields and hashes match the tested candidate without rebuilding the executable. The release manifest is not read from the mutable application store to enable blocking; the release process is the authority for what is distributed and claimed.

The artifact lifecycle is therefore:

1. Build the exact executable with `BuildManifestV1` and the selected compiled mode.
2. Publish that unchanged executable as the GitHub validation candidate and run the operator-only workflow.
3. Bind the candidate's executable, embedded manifest, source revision, and asset digest to the F/R reports.
4. Approve the unchanged artifact as `strongBlockingCapable` only when all required gates pass, or publish it as `measurementOnly` only when identity and counter gates pass and the strong-blocking gate fails.
5. Never let an external report, mutable store, user preference, or signature status promote a `measurementOnly` executable.

When local user signing is part of the supported installation path, candidate evidence must bind both the published unsigned asset digest and the exact post-signing app or executable digest, together with the canonical signing procedure and its entitlements. A user-resigned copy without matching evidence is a derived local artifact and cannot inherit a strong-blocking or measurement-capable release claim solely from the unsigned GitHub asset.

The operator-validation launch context is process-local, explicit, and never persisted. It changes warnings and confirmation requirements only. It does not bypass capability checks, authorization, observation-quality rules, or transaction safety.

Runtime authorization availability is also runtime-only and not persisted. After relaunch, logout, or reboot, HBF may perform only a non-interactive check that cannot display a prompt. If that check cannot obtain a usable authorization, protection remains `BlockingNotGuaranteed` until the user invokes the explicit authorization action. Enforcement retries never prompt.

---

## 11. Verification Layers

### 11.1 Domain verification

- Exact decimal limit parsing and half-up display rounding
- Checked arithmetic and overflow transitions
- Counter baseline and discontinuity rules
- Reset-day fallback and clock/time-zone transitions
- Profile resolution and state precedence
- Retry and notification schedules
- Persistence migration, corruption, LKG, and tombstone behavior

### 11.2 Adapter integration verification

- CoreWLAN Swift mappings on the selected SDK
- Interface-name/index matching for `NET_RT_IFLIST2`
- Configuration archive, decode, equality, and fingerprint determinism
- Atomic file replacement and permission checks
- Lifecycle and login-item status mappings

### 11.3 GitHub-candidate real-Mac gates

- Identity permission granted, denied, revoked, and restored
- Exact GitHub candidate artifact's non-sandboxed 64-bit counter capability
- Authorization success and denial without automatic reprompt
- Exact-target disconnect and post-action query
- Target-present, target-absent, duplicate-security, and unrelated-profile preservation
- Full suppression and restoration observation windows
- Crash/relaunch reconciliation with an open preference transaction

The current evidence and pending gate cases are recorded in `HotspotByteFence_CapabilityGates.md`.

Every verification item above must be assigned to an AC row and evidence id in [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md). A domain test, adapter check, mock, or artifact different from the exact GitHub release asset can satisfy only its own layer; it cannot mark an F/R gate or release capability as passed.

---

## 12. Implementation Order

1. Create the non-sandboxed macOS project shell and immutable build-mode metadata.
2. Implement domain types, checked numeric parsing, cycle engine, and state reducer.
3. Create the fixture/oracle assets and the operator-runner contract in `HotspotByteFence_VerificationTraceability.md` and `HotspotByteFence_OperatorRunbook.md`.
4. Implement and run the GitHub-candidate identity/counter feasibility probes.
5. Implement crash-safe persistence, the exact configuration archive, and recovery.
6. Implement measurement integration, observation coordination, and lifecycle handling.
7. Implement UI, localization, login launch, and notifications.
8. Implement the operator-only strong-blocking candidate workflow.
9. Run the GitHub-candidate feasibility gate before integrating automatic enforcement into normal runtime.
10. Complete the real-Mac release gate on every support-matrix entry.

The candidate workflow may be connected to normal-runtime enforcement after F-01 through F-11 and `F-12-preflight` pass. Strong-blocking distribution remains stopped until the release gate also binds the per-case `F-12-classification` evidence and all required R cases. If the feasibility gate cannot prove administrator authorization, lossless configuration round-trip, target-only disconnect, event-backed suppression observation, or safe restoration, the workflow must remain operator-only or measurement-only as applicable.
