# Hotspot Byte Fence (HBF) — Verification Traceability Matrix

**Version:** 0.3
**Date:** 2026-09-01  
**Normative source:** [`HotspotByteFence_PRD.md`](HotspotByteFence_PRD.md)  
**Implementation status:** The SwiftPM core source, unit-test surface, and initial `FX-Counter-001` fixture exist under `Sources/HotspotByteFenceCore` and `Tests/HotspotByteFenceCoreTests`. The full Xcode app, runtime harness, candidate runner, app bundle, and GitHub candidate artifact do not exist yet; F/R and complete D/I/UI/REP evidence remain pending.

This matrix maps every PRD acceptance criterion, AC-01 through AC-81, to an implementation-facing test or GitHub-candidate gate. Local core test results are reported separately from F/R evidence; passing them does not credit a candidate or release gate. Real-Mac destructive execution follows [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md).

---

## 1. Evidence ID Conventions

| Prefix | Layer | Required surface |
|---|---|---|
| `D-` | Domain test | Deterministic reducer/engine harness with injected clock, identity, counter, persistence, notification, disconnector spies |
| `I-` | Adapter integration test | macOS API adapter exercised in a local unsigned or development-signed build; not a release capability pass |
| `UI-` | UI and accessibility test | Menu bar/settings app with accessibility identifiers, Korean/English String Catalogs, Light/Dark captures |
| `F-` | GitHub-candidate feasibility gate | Exact non-sandboxed GitHub release path; published unsigned asset plus the canonical post-download ad hoc-signed app when the case requires signing; operator workflow where destructive |
| `R-` | Strong-blocking release gate | Exact unchanged candidate on each supported macOS build |
| `REP-` | Report/schema validator | Machine-checkable local evidence and redacted report validation |

---

## 2. Required Fixtures and Oracles

| Fixture/oracle | Contents | Blocks |
|---|---|---|
| `FX-Counter-001` | RX/TX increments, regression, reset, parse failure, mixed records, `ifm_msglen` bounds, truncation, zero-length and unknown-layout records, unaligned input, duplicate target index, name/index mismatch, UInt64 overflow, reset-straddling sample | AC-01, AC-02, AC-34~37, AC-53, AC-56, AC-68, AC-76 |
| `FX-Identity-001` | SSID hex corpus, BSSID corpus, interface names, coherent double-read snapshots, getter/event race, unknown/new/ambiguous/duplicate/shared cases | AC-27~32, AC-62, AC-65, AC-80 |
| `FX-Clock-001` | Reset-day calendar corpus, DST edge, time-zone change, wall/monotonic divergence, sleep/wake/relaunch | AC-13~18, AC-35, AC-44, AC-49, AC-50, AC-56, AC-57, AC-71, AC-78 |
| `FX-Persistence-001` | Valid/corrupt/missing canonical and LKG stores, unknown schema, migration failure, marker repair, `CommitJournalV1` phases, required-but-missing journal, every multi-file crash cut point, revision/digest mismatch recovery, tombstone interruption, flush failure | AC-19, AC-33, AC-37, AC-38, AC-70, AC-74, AC-77, AC-79 |
| `FX-CoreWLAN-001` | Target-present, target-absent, duplicate security profiles, unrelated preferred networks, external user mutation | AC-08~10, AC-40, AC-41, AC-54, AC-55, AC-64, AC-70, AC-73~75, AC-79 |
| `FX-Permission-001` | Location granted, denied, restricted, revoked, restored, and manual-identity boundary without coordinates | AC-67 |
| `FX-Authorization-001` | Explicit authorization success, denial, cancellation, relaunch non-interactive check, exact right/flags, restoration authorization need | AC-27, AC-39, AC-63, AC-79 |
| `FX-ConfigurationArchive-001` | Every `CWConfigurationArchiveV1` public flag, ordered profiles, raw SSID bytes, security raw values, canonical bytes, replay, read-back, equality mismatch, unsupported-field failure | AC-70, AC-74, AC-75 |
| `FX-Observation-001` | Event-backed callback, entitlement absent, polling fallback, lifecycle-only input, one-second cadence, two-second gap, 30-second awake window, reconnection classification | AC-09, AC-41, AC-64, AC-73 |
| `FX-Notification-001` | Notification grant/deny, mute expiry during sleep, once-per-cycle success, five-minute failure throttle | AC-21, AC-22, AC-42, AC-43, AC-60 |
| `FX-UI-001` | Accessibility identifiers, state snapshots, Korean/English string coverage, Light/Dark screenshots, truncation checks | AC-03~07, AC-20, AC-23~25, AC-48, AC-52, AC-69 |
| `FX-Release-001` | Published unsigned asset hash, canonical local signing procedure, tested app-bundle/executable hashes using `hbf-app-bundle-v1-sha256` and post-signing values when applicable, actual signature state, entitlements, Info.plist, GitHub release manifest, Gatekeeper/quarantine result, support matrix row, operator-validation context/status projection, local/redacted reports | AC-63, AC-72 |

### 2.1 Canonical implementation and evidence surfaces

| Surface | Required path or command | Pass oracle |
|---|---|---|
| Domain tests | `Tests/HotspotByteFenceCoreTests/` and `swift test` | Implemented core cases pass with deterministic inputs and no system side effect; full `D-*` coverage remains pending |
| Read-only counter probe | `swift run HotspotByteFence --probe-counter <interface>` | The current macOS returns checked `UInt64` RX/TX values through `NET_RT_IFLIST2`; this is local adapter evidence, not an F-04/F-05 candidate pass |
| Read-only identity probe | `swift run HotspotByteFence --probe-identity` | Interfaces are enumerated without printing SSID/BSSID; unavailable identity remains unavailable and no network action occurs |
| Adapter tests | `Tests/HotspotByteFenceTests/Adapters/` and `xcodebuild test -scheme HotspotByteFence -only-testing:HotspotByteFenceTests/Adapters` | All `I-*` cases pass on the selected SDK; this does not credit F/R |
| UI tests | `Tests/HotspotByteFenceUITests/` and `xcodebuild test -scheme HotspotByteFence -only-testing:HotspotByteFenceUITests` | Accessibility identifiers, state snapshots, localization, and appearance checks pass |
| Fixture assets | `Tests/HotspotByteFenceCoreTests/Fixtures/HotspotByteFence/` | The initial counter fixture validates the typed parser oracle; the remaining fixture families and negative corpus are pending |
| Report validator | `Scripts/validate-hbf-report` | Invalid schema, prohibited data, missing digest, or inconsistent verdict is rejected |
| Candidate runner | `Scripts/hbf-gate-run` | It records the exact candidate, manifest, topology, oracle, and operator confirmation without synthesizing results; it launches destructive cases only with a matching process-local `OperatorValidationContextV1`, and the candidate never projects `StrongBlockingReady` in that lifecycle |
| Real-Mac evidence | `QA/Evidence/<applicationVersion>/<macOSBuild>/<runID>/` | Local evidence and redacted report are both present and hash-bound to the candidate |

The remaining Xcode, full adapter, UI, report-validator, candidate-runner, and real-Mac evidence paths do not yet exist. Their `I`, `UI`, `F`, `R`, and `REP` statuses remain unimplemented or pending; a row cannot be marked passed from a prose fixture description or from the local read-only probes.

### 2.2 Status semantics

The `Current status` column is an aggregate planning status, not runtime evidence. `Not implemented` means that the product path or its test surface does not exist yet; `Gate pending` means that the design contract exists but the exact candidate evidence is absent; neither value is a pass. Once implementation begins, the report validator must preserve separate status objects for domain (`D`), adapter (`I`), UI (`UI`), feasibility (`F`), release (`R`), and reporting (`REP`) layers, each bound to the same run ID, candidate digest, and manifest digest.

---

## 3. Acceptance Criteria Traceability

| AC | Primary design contract | Test/gate IDs | Required fixture/oracle | Current status |
|---|---|---|---|---|
| AC-01 | Target-only measurement | `D-MEAS-001`, `F-04`, `F-05` | `FX-Counter-001` | Not implemented |
| AC-02 | RX + TX | `D-MEAS-002`, `F-05` | `FX-Counter-001` | Not implemented |
| AC-03 | Decimal units | `D-NUM-001`, `UI-MENU-001` | `FX-UI-001` | Not implemented |
| AC-04 | Menu bar simplicity | `UI-MENU-002` | `FX-UI-001` | Not implemented |
| AC-05 | 50% state | `D-NUM-002`, `UI-MENU-003` | `FX-UI-001` | Not implemented |
| AC-06 | 80% state | `D-NUM-003`, `UI-MENU-003` | `FX-UI-001` | Not implemented |
| AC-07 | 90% state | `D-NUM-004`, `UI-MENU-003` | `FX-UI-001` | Not implemented |
| AC-08 | Limit enforcement | `D-ENF-001`, `F-08`, `R-05` | `FX-CoreWLAN-001` | Gate pending |
| AC-09 | Reconnection enforcement | `D-ENF-002`, `F-12`, `R-06`, `R-07` | `FX-CoreWLAN-001`, `FX-Observation-001` | Gate pending |
| AC-10 | Other networks remain usable | `D-ENF-003`, `F-10`, `R-04`, `R-05` | `FX-CoreWLAN-001` | Gate pending |
| AC-11 | Pause Blocking | `D-CMD-001`, `UI-CMD-001`, `R-15` | `FX-Clock-001`, `FX-CoreWLAN-001` | Not implemented |
| AC-12 | Usage beyond limit | `D-MEAS-003`, `UI-MENU-004` | `FX-UI-001` | Not implemented |
| AC-13 | Pause expires at reset | `D-CYCLE-001` | `FX-Clock-001` | Not implemented |
| AC-14 | Default reset | `D-CYCLE-002` | `FX-Clock-001` | Not implemented |
| AC-15 | Day 31 fallback | `D-CYCLE-003` | `FX-Clock-001` | Not implemented |
| AC-16 | February fallback | `D-CYCLE-004` | `FX-Clock-001` | Not implemented |
| AC-17 | No unnecessary fallback | `D-CYCLE-005` | `FX-Clock-001` | Not implemented |
| AC-18 | Sleeping through reset | `D-CYCLE-006`, `UI-LIFE-001` | `FX-Clock-001` | Not implemented |
| AC-19 | Persistence | `D-PERSIST-001`, `I-STORE-001` | `FX-Persistence-001` | Not implemented |
| AC-20 | Quit warning | `UI-LIFE-002` | `FX-UI-001` | Not implemented |
| AC-21 | Blocking failure warning | `D-ENF-004`, `UI-NOTIFY-001` | `FX-Notification-001` | Not implemented |
| AC-22 | Notification mute independence | `D-NOTIFY-001`, `UI-NOTIFY-002` | `FX-Notification-001` | Not implemented |
| AC-23 | Manual reset warning | `UI-CMD-002`, `D-CMD-002` | `FX-UI-001` | Not implemented |
| AC-24 | Limit lowered below usage | `D-CMD-003` | `FX-Counter-001` | Not implemented |
| AC-25 | Localization | `UI-L10N-001` | `FX-UI-001` | Not implemented |
| AC-26 | Independent profiles | `D-PROFILE-001`, `UI-PROFILE-001` | `FX-Identity-001` | Not implemented |
| AC-27 | Profile activation | `D-PROFILE-002`, `F-06` | `FX-Identity-001`, `FX-Authorization-001` | Gate pending |
| AC-28 | Unknown network | `D-IDENT-001`, `UI-STATE-001` | `FX-Identity-001` | Not implemented |
| AC-29 | Unique profile matching | `D-IDENT-002` | `FX-Identity-001` | Not implemented |
| AC-30 | Ambiguous profile matching | `D-IDENT-003`, `UI-STATE-002` | `FX-Identity-001` | Not implemented |
| AC-31 | BSSID re-confirmation | `D-IDENT-004`, `UI-CMD-003` | `FX-Identity-001` | Not implemented |
| AC-32 | Network identity immutability | `D-PROFILE-003`, `UI-CMD-004` | `FX-Identity-001` | Not implemented |
| AC-33 | Profile deletion | `D-PERSIST-002`, `UI-CMD-005` | `FX-Persistence-001` | Not implemented |
| AC-34 | Interface-only measurement | `D-MEAS-004`, `F-05` | `FX-Counter-001` | Gate pending |
| AC-35 | Measurement gap | `D-MEAS-005`, `D-CYCLE-007` | `FX-Counter-001`, `FX-Clock-001` | Not implemented |
| AC-36 | Sampling boundary | `D-MEAS-006`, `UI-HELP-001` | `FX-Counter-001`, `FX-UI-001` | Not implemented |
| AC-37 | Persistence cadence | `D-PERSIST-003` | `FX-Persistence-001` | Not implemented |
| AC-38 | Persisted-state failure | `D-PERSIST-004`, `UI-RECOVERY-001` | `FX-Persistence-001` | Not implemented |
| AC-39 | Blocking authorization | `D-AUTH-001`, `F-06`, `F-11` | `FX-Authorization-001` | Gate pending |
| AC-40 | Profile-specific blocking | `D-ENF-005`, `R-03`, `R-04` | `FX-CoreWLAN-001` | Gate pending |
| AC-41 | Blocking retry and restoration | `D-ENF-006`, `F-12`, `R-06`, `R-09`, `R-15` | `FX-CoreWLAN-001`, `FX-Observation-001` | Gate pending |
| AC-42 | Notification fallback | `D-NOTIFY-002`, `UI-NOTIFY-003` | `FX-Notification-001` | Not implemented |
| AC-43 | Notification deduplication | `D-NOTIFY-003` | `FX-Notification-001` | Not implemented |
| AC-44 | Reset-day change | `D-CMD-004`, `D-CYCLE-008` | `FX-Clock-001` | Not implemented |
| AC-45 | Limit increase confirmation | `D-CMD-005`, `UI-CMD-006` | `FX-UI-001` | Not implemented |
| AC-46 | Manual reset scope | `D-CMD-006`, `R-15` | `FX-Persistence-001`, `FX-CoreWLAN-001` | Not implemented |
| AC-47 | Quit cleanup | `UI-LIFE-003`, `R-15` | `FX-CoreWLAN-001`, `FX-UI-001` | Gate pending |
| AC-48 | Display and setup state | `UI-MENU-005`, `D-STATE-001` | `FX-UI-001` | Not implemented |
| AC-49 | Profile-local cycle | `D-CYCLE-009` | `FX-Clock-001` | Not implemented |
| AC-50 | Time and sleep transitions | `D-CLOCK-001`, `UI-STATE-003` | `FX-Clock-001` | Not implemented |
| AC-51 | Local diagnostics | `D-EVENT-001`, `REP-PRIV-001` | `FX-Persistence-001` | Not implemented |
| AC-52 | Language and launch settings | `UI-L10N-002`, `I-LOGIN-001` | `FX-UI-001` | Not implemented |
| AC-53 | VPN traffic accounting | `D-MEAS-007`, `F-05` | `FX-Counter-001` | Gate pending |
| AC-54 | Blocking target revalidation | `D-ENF-007`, `F-08`, `R-05` | `FX-CoreWLAN-001` | Gate pending |
| AC-55 | Preference ownership conflict | `D-PREF-001`, `F-09`, `R-12` | `FX-CoreWLAN-001` | Gate pending |
| AC-56 | Reset-boundary delta | `D-CYCLE-010`, `D-MEAS-008` | `FX-Clock-001`, `FX-Counter-001` | Not implemented |
| AC-57 | Clock rollback | `D-CLOCK-002`, `UI-STATE-004` | `FX-Clock-001` | Not implemented |
| AC-58 | Limit precision and validation | `D-NUM-005`, `UI-CMD-007` | `FX-UI-001` | Not implemented |
| AC-59 | Offline manual reset | `D-CMD-007` | `FX-Identity-001` | Not implemented |
| AC-60 | Notification mute expiry | `D-NOTIFY-004` | `FX-Notification-001` | Not implemented |
| AC-61 | Resuming blocking | `D-CMD-008`, `D-ENF-008` | `FX-CoreWLAN-001` | Not implemented |
| AC-62 | Profile alias and identity validation | `D-PROFILE-004`, `UI-CMD-008` | `FX-Identity-001` | Not implemented |
| AC-63 | Blocking release gate outcome | `REP-REL-001`, `F-01` through `F-12`, `R-01` through `R-15` | `FX-Release-001` | Gate pending |
| AC-64 | Preference restoration observation | `D-PREF-002`, `F-12`, `R-10`, `R-11` | `FX-CoreWLAN-001`, `FX-Observation-001` | Gate pending |
| AC-65 | Shared interface-and-SSID capability boundary | `D-PROFILE-005`, `R-03` | `FX-Identity-001`, `FX-CoreWLAN-001` | Gate pending |
| AC-66 | Multiple resolved target profiles | `D-IDENT-005`, `UI-STATE-005` | `FX-Identity-001`, `T3` topology role | Not implemented |
| AC-67 | Identity permission boundary | `D-PERM-001`, `F-02`, `F-03` | `FX-Permission-001` | Gate pending |
| AC-68 | Counter source and width | `I-COUNTER-001`, `F-04`, `D-MEAS-009` | `FX-Counter-001` | Gate pending |
| AC-69 | Compositional profile state | `D-STATE-002`, `UI-STATE-006` | `FX-UI-001` | Not implemented |
| AC-70 | Preference transaction safety | `D-PREF-003`, `F-07`, `F-09`, `R-13`, `R-14` | `FX-Persistence-001`, `FX-ConfigurationArchive-001`, `FX-CoreWLAN-001` | Gate pending |
| AC-71 | Time-adjustment acknowledgement | `D-CLOCK-003`, `UI-CMD-009` | `FX-Clock-001` | Not implemented |
| AC-72 | Release-mode traceability | `REP-REL-002`, `F-01` | `FX-Release-001` | Gate pending |
| AC-73 | Blocking reconnection observation | `D-ENF-009`, `F-12`, `R-06`, `R-07`, `R-08` | `FX-CoreWLAN-001`, `FX-Observation-001` | Gate pending |
| AC-74 | Lossless preference recovery | `D-PREF-004`, `F-07`, `R-09`, `R-13`, `R-14` | `FX-CoreWLAN-001`, `FX-ConfigurationArchive-001`, `FX-Persistence-001` | Gate pending |
| AC-75 | Preference mutation scope | `D-PREF-005`, `R-01`, `R-02`, `R-03`, `R-04` | `FX-CoreWLAN-001`, `FX-ConfigurationArchive-001` | Gate pending |
| AC-76 | Arithmetic overflow safety | `D-NUM-006`, `D-MEAS-010` | `FX-Counter-001` | Not implemented |
| AC-77 | Persistence failure and migration safety | `D-PERSIST-005` | `FX-Persistence-001` | Not implemented |
| AC-78 | Lifecycle clock boundaries | `D-CLOCK-004`, `UI-LIFE-004` | `FX-Clock-001` | Not implemented |
| AC-79 | Eligibility and build-mode transitions | `D-ENF-010`, `D-PREF-006`, `R-15` | `FX-CoreWLAN-001`, `FX-Release-001` | Gate pending |
| AC-80 | Manual identity grammar | `D-PROFILE-006`, `UI-CMD-010` | `FX-Identity-001` | Not implemented |
| AC-81 | State scope and counter-gate precedence | `D-STATE-003`, `F-04`, `F-05`, `REP-REL-003` | `FX-Counter-001`, `FX-Release-001` | Not implemented |

---

## 4. F/R Gate Traceability

| Gate | Required AC coverage | Additional oracle |
|---|---|---|
| F-01 | AC-63, AC-72 | Exact GitHub asset SHA-256, canonical post-signing app-bundle/executable SHA-256 values when applicable, entitlements, Info.plist, actual Hardened Runtime/signature status, no App Sandbox, Gatekeeper/quarantine result |
| F-02 | AC-27, AC-67 | Location granted coherent `IdentitySnapshotV1` proof without coordinates |
| F-03 | AC-67 | Denied/revoked permission state transition |
| F-04 | AC-01, AC-34, AC-68 | Exact GitHub candidate counter source and bounded `NET_RT_IFLIST2` mixed-record parser, including malformed-record corpus |
| F-05 | AC-01, AC-02, AC-34, AC-53 | Controlled traffic continuity |
| F-06 | AC-27, AC-39 | Explicit authorization prompt and denial |
| F-07 | AC-70, AC-74 | Lossless configuration archive and replay |
| F-08 | AC-08, AC-54 | Stable identity snapshot, target-only disconnect post-query, and valid operator-validation context for the destructive case |
| F-09 | AC-55, AC-70, AC-74 | Restoration ownership fingerprint |
| F-10 | AC-10, AC-40, AC-75 | Unrelated configuration preservation |
| F-11 | AC-39 | Relaunch process-local authorization boundary |
| F-12 | AC-09, AC-41, AC-64, AC-73 | `ObservationGateReportV1` with separate preflight and classification digests/verdicts and per-case context-validation results; preflight permits gated candidate integration, while the aggregate F-12 verdict is `PASS` only after per-case source, awake coverage, maximum gap, and suppression/restoration classification are bound to applicable R evidence for release |
| R-01 | AC-75 | Target-present mutation |
| R-02 | AC-75 | Target-absent verified no-op |
| R-03 | AC-40, AC-65, AC-75 | Duplicate-security/shared-scope preservation |
| R-04 | AC-10, AC-40, AC-75 | Unrelated preferred-network preservation |
| R-05 | AC-08, AC-10, AC-54 | Exact-target disconnect and residual TOCTOU observation |
| R-06 | AC-09, AC-41, AC-73 | Full suppression observation |
| R-07 | AC-09, AC-73 | Reconnect without manual-intent token |
| R-08 | AC-73 | One-shot manual-intent classification |
| R-09 | AC-41, AC-64, AC-74 | Restoration read-back equality |
| R-10 | AC-41, AC-64 | Post-restoration observation window |
| R-11 | AC-64 | Reconnect after restoration does not invalidate read-back restoration |
| R-12 | AC-55 | User preference change creates conflict and is not overwritten |
| R-13 | AC-70, AC-74 | Crash/relaunch with `Prepared` |
| R-14 | AC-70, AC-74 | Crash/relaunch with `Applied` |
| R-15 | AC-11, AC-41, AC-46, AC-47, AC-79 | Pause, reset, limit increase, quit restoration paths |

---

## 5. Build, Entitlement, and Manifest Checks

Release and candidate verification must inspect these artifacts before any functional gate is credited:

| Artifact | Required value |
|---|---|
| App Sandbox entitlement | Absent or false |
| Hardened Runtime | Record `enabled`, `disabled`, or `unavailable`; absence does not fail the GitHub distribution path |
| Network/Wi-Fi event entitlement | `com.apple.wifi.events` present only if the selected CoreWLAN event path requires it on the target SDK/OS; absence must be tested and recorded |
| Location usage description | `NSLocationUsageDescription` with Korean and English localized purpose strings; a future equivalent requires a new support-matrix proof |
| Bundle identifier | `com.copylawbot.hotspotbytefence` unless changed by an explicit decision |
| Supported architecture | `arm64` for v1 unless additional proof is added |
| Embedded `BuildManifestV1` | Canonical manifest fields, compile-time capability constant, manifest SHA-256, bundle/architecture/mode/source agreement |
| External `ReleaseManifestV1` | Exact schema in `HotspotByteFence_TechnicalDesign.md` Section 10: schema/version/id/status, unsigned-asset/app-bundle/executable candidate hashes, fixed support-row shape, signature/runtime/quarantine/Gatekeeper fields, and complete F/R digest and verdict maps; its canonical digest is recorded as `releaseManifestSHA256` |
| Local signing record | Published unsigned asset SHA-256, exact ad hoc signing procedure, post-signing app-bundle and executable SHA-256 values, actual signature state, and any post-signing entitlement inspection |
| Local evidence | Full non-shared evidence with local-sensitive identifiers allowed |
| Redacted report | Shareable derivative with hashes/redactions and no prohibited data |

The `com.apple.wifi.events` entitlement is not assumed for the GitHub path. The published asset is unsigned and supported user setup uses the canonical local ad hoc-signing procedure in `README.md`; that signature step does not itself grant an entitlement. The default candidate implementation uses one-second polling plus public notifications, while strong-blocking suppression requires event-backed observation under F-12. If an event path requires the entitlement and the exact tested artifact does not have it, F-12 records the absence, suppression remains `Unverified`, and the artifact can proceed only as measurement-only when identity and counter gates pass.
