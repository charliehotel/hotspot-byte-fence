# Hotspot Byte Fence (HBF) — Capability Gate Record

**Version:** 0.2  
**Date:** 2026-09-01  
**Current verdict:** `PENDING`  
**Scope:** Initial `arm64` validation target only

This record distinguishes API discovery from exact GitHub-candidate proof. A compiler check, Swift interpreter run, mock adapter, or helper artifact that is different from the exact GitHub release asset is not a capability-gate pass. The GitHub candidate may be completely unsigned or ad hoc signed; Developer ID signing, notarization, and Hardened Runtime are not prerequisites.

Required design and evidence companions:

- [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md): state, command, authorization, and fail-closed disconnect contracts that F/R gates must exercise.
- [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md): persistence, transaction, local evidence, redacted report, and threat-model contracts that gate reports must preserve.
- [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md): AC-01 through AC-81 mapping to F/R gates, fixtures, oracles, entitlement checks, and release manifest checks.
- [`HotspotByteFence_DecisionsNeeded.md`](HotspotByteFence_DecisionsNeeded.md): remaining release inputs that block final support claims until answered or proven.
- [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md): fixed test topology, operator confirmations, abort rules, and evidence paths for destructive real-Mac cases.

---

## 1. Environment Snapshot

| Item | Observed value |
|---|---|
| macOS | 26.6.2 |
| Build | 25G83 |
| Architecture | `arm64` |
| Xcode SDK | macOS 26.5 |
| Swift | 6.3.3 |
| Distribution posture | GitHub direct Copy App, non-sandboxed; unsigned by default; ad hoc signing optional; Developer ID/notarization/Hardened Runtime recorded if present but not required |
| App Sandbox | Disabled by approved v1 design |

This environment is the only initial validation entry. macOS 13.0 remains a deployment floor and has no support claim.

---

## 2. Evidence Collected Before Implementation

| Check | Surface | Result | What it proves | What it does not prove |
|---|---|---|---|---|
| CoreWLAN Swift mapping | Swift 6.3.3 interpreter importing current SDK | `PASS` | `CWWiFiClient.shared()`, client-vended interface access, `ssidData()`, `bssid()`, `configuration()`, and `disassociate()` compile in the current SDK | Location authorization, candidate runtime behavior, disconnect success, or safe preference mutation |
| 64-bit route counter availability | Unsandboxed Swift interpreter calling `sysctl(NET_RT_IFLIST2)` | `PASS` | The current OS returns an interface-list buffer and exposes `if_msghdr2`/`if_data64` layouts | Candidate runtime behavior, parser correctness, interface matching, or long-running continuity |
| UI/login API availability | Current SDK declarations | `PASS` | `MenuBarExtra` and `SMAppService.mainApp` are available at the macOS 13 deployment floor | Login-item approval or complete UI behavior |
| GitHub candidate artifact | Exact application/ZIP asset intended for release | `NOT RUN` | Nothing yet | All release capability claims |

No existing result authorizes measurement or strong-blocking distribution.

---

## 3. GitHub-Candidate Feasibility Gate

Strong-blocking candidate integration may proceed only when F-01 through F-11 and the `F-12-preflight` phase are terminal `PASS` for the exact candidate. The `F-12-classification` phase is completed from the real blocking/restoration cases and is a release-evidence prerequisite, not a second precondition for building the candidate workflow.

| ID | Scenario | Required evidence | Status |
|---|---|---|---|
| F-01 | Distribution posture | Exact GitHub asset SHA-256, App Sandbox absence, actual unsigned/ad hoc/Developer ID status, actual Hardened Runtime status, quarantine state, and Gatekeeper launch outcome are recorded; Developer ID is not required | `PENDING` |
| F-02 | Location granted | Exact interface name, nonempty SSID bytes, and canonical BSSID are returned without storing coordinates | `PENDING` |
| F-03 | Location denied/revoked | Identity-dependent measurement and blocking stop with the required state | `PENDING` |
| F-04 | Candidate counter read | `NET_RT_IFLIST2` returns checked 64-bit RX/TX for the selected interface in the exact GitHub candidate | `PENDING` |
| F-05 | Counter continuity | Controlled traffic increases the selected interface counters without adding another interface | `PENDING` |
| F-06 | Administrator authorization | Explicit `SFAuthorization` succeeds and denial is handled without automatic reprompt | `PENDING` |
| F-07 | Configuration round-trip | Complete public `CWConfiguration` archives, decodes, compares, and replays losslessly | `PENDING` |
| F-08 | Target disconnect safety | After exact revalidation, `disassociate()` is called only for the observed target, post-query confirms target absence, and any residual target-switch window is explicitly reported | `PENDING` |
| F-09 | Restoration ownership | Original configuration is restored only when the current fingerprint matches HBF's last write | `PENDING` |
| F-10 | Unrelated preservation | Non-target preferred networks and public configuration values remain byte/semantic equivalent | `PENDING` |
| F-11 | Process-local authorization | Relaunch does not treat persisted success as usable authorization; a non-interactive check never prompts, and unavailable authorization requires explicit user action | `PENDING` |
| F-12 | Observation source and coverage | The exact candidate first proves the observation capability and instrumentation, then records event-backed callback delivery, one-second polling fallback, awake duration, maximum observation gap, and suppression/restoration result classification from the applicable R cases | `PENDING` |

F-06 through F-10 and F-12 can disrupt the current Wi-Fi connection, modify system preferences, or require a live observation window. They require a separately confirmed operator session and must not be run as an incidental automated test. F-12 is a two-stage gate: `F-12-preflight` runs before destructive cases and proves callback/entitlement visibility, polling cadence, and evidence instrumentation; `F-12-classification` is finalized from the applicable suppression/restoration cases after the R run. The preflight result is a prerequisite for strong R-06/R-07, while the complete F-12 verdict is not credited until its per-case classification evidence exists.

F-06 must record the exact `SFAuthorization` right string and flags used for `commitConfiguration(_:authorization:)`. F-07 must record the `CWConfigurationArchiveV1` schema version, canonical bytes, replay result, read-back result, and equality comparator result. F-08 must include the conservative pre-call revalidation and bounded post-query algorithm from `HotspotByteFence_StateModel.md`; it must not claim atomic target-only disconnect unless the tested public API behavior proves it on the exact macOS build. F-12 is a prerequisite for strong blocking: polling-only or lifecycle-only evidence may be retained, but it cannot produce a verified suppression result. A poll-backed restoration observation may credit restoration evidence only when its timing coverage is complete; it never upgrades suppression to verified.

### 3.1 Gate verdict rule

- `PASS`: F-01 through F-11 pass and the `F-12-preflight` phase passes for the exact candidate. The F-12 record must identify whether its per-case classification is pending or bound to R-case evidence.
- `FAIL`: A required public API or approved distribution boundary cannot satisfy the scenario reproducibly.
- `PENDING`: Evidence is incomplete or not bound to the exact candidate.
- `BLOCKED`: A named external prerequisite, such as the exact GitHub artifact, required macOS permission, or operator-approved network setup, is unavailable. Developer ID signing identity is not an external prerequisite for v1.

The strong-blocking release verdict additionally requires `F-12-classification` to be bound to the applicable R-06/R-07/R-08/R-10 records. Therefore a candidate may be eligible for gated implementation while the release record remains `PENDING`.

A feasibility `FAIL` stops normal-runtime strong-blocking integration. Domain and measurement work may continue only when the failed item does not invalidate their capability boundary.

---

## 4. Release Capability Gates

### 4.1 Identity capability gate

Requires F-01 through F-03 on the exact release candidate.

Current verdict: `PENDING`

### 4.2 Counter capability gate

Requires F-01, F-04, F-05, exact-candidate startup reproduction, and transient-failure recovery.

Current verdict: `PENDING`

### 4.3 Strong-blocking release gate

Requires all feasibility cases plus the following real-Mac scenarios:

| ID | Scenario | Status |
|---|---|---|
| R-01 | Target-present preference mutation | `PENDING` |
| R-02 | Target-absent verified no-op | `PENDING` |
| R-03 | Duplicate-security-profile preservation | `PENDING` |
| R-04 | Unrelated preferred-network preservation | `PENDING` |
| R-05 | Exact-target disconnect verification and residual TOCTOU result | `PENDING` |
| R-06 | Full 30-second awake suppression observation | `PENDING` |
| R-07 | Reconnect without manual-intent token fails suppression | `PENDING` |
| R-08 | One-shot manual-intent classification during suppression | `PENDING` |
| R-09 | Restoration read-back and fingerprint equality | `PENDING` |
| R-10 | Full 30-second post-restoration observation | `PENDING` |
| R-11 | Automatic or unclassified reconnect after restoration does not invalidate configuration restoration | `PENDING` |
| R-12 | User preference change creates conflict and is not overwritten | `PENDING` |
| R-13 | Crash/relaunch with `Prepared` transaction | `PENDING` |
| R-14 | Crash/relaunch with `Applied` transaction | `PENDING` |
| R-15 | Pause, reset, limit increase, and voluntary quit restoration paths | `PENDING` |

Current verdict: `PENDING`

R-13 and R-14 must prove relaunch reconciliation for `Prepared` and `Applied` transactions, including the no-automatic-prompt restoration path when no process-local authorization is available. R-05 must explicitly report whether any residual target-switch/TOCTOU risk remains for `CWInterface.disassociate()` on the tested macOS build. R-01 through R-04 and R-09 through R-12 must include the persistence schema's archive/fingerprint algorithm id and redacted-report separation. R-06 and R-07 must include the observation source and maximum-gap result; a polling-only result cannot be reported as a strong-blocking suppression pass.

---

## 5. Support Matrix

| macOS | Build | Architecture | Identity | Counter | Strong blocking | Distribution status |
|---|---|---|---|---|---|---|
| 26.6.2 | 25G83 | `arm64` | `PENDING` | `PENDING` | `PENDING` | Unsupported until applicable gates pass |

Adding a row requires a new exact candidate report. A deployment target or API availability check does not add support.

---

## 6. Manifest Binding and Operator Session

### 6.1 Embedded `BuildManifestV1`

Every app bundle must contain one canonical `BuildManifestV1` and a matching compile-time capability constant. The embedded manifest contains only these fields:

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

The canonical manifest is UTF-8 JSON with sorted keys and no insignificant whitespace. The executable must refuse to start its measurement or blocking engine when the manifest is malformed, has an unexpected bundle identifier or architecture, or disagrees with the compile-time mode constant. The mutable store records the manifest and its SHA-256 for audit only. It never promotes a mode.

### 6.2 External `ReleaseManifestV1`

The external `ReleaseManifestV1` uses the exact schema in Section 10 of `HotspotByteFence_TechnicalDesign.md`: schema/version/id/status, candidate hashes, fixed support-row shape, signature/runtime/quarantine/Gatekeeper fields, and complete F/R digest and verdict maps. Its canonical JSON digest is recorded as `releaseManifestSHA256` in candidate evidence. The release process compares every value with the local candidate evidence before approval.

`strongBlockingCapable` is distributable only when F-01 through F-12, the identity and counter capability gates, and R-01 through R-15 pass for the exact unchanged artifact. `measurementOnly` is distributable only when identity and counter capability gates pass and the strong-blocking gate fails. An external report, a mutable store, a user preference, or a signature status cannot promote `measurementOnly` to strong blocking. A candidate that is not yet approved is not a protected user release and must be exercised only through the operator-validation workflow.

### 6.3 Operator preconditions

The destructive cases use the fixed role topology below. The actual SSID, BSSID, interface name, phone number, and credentials are operator-local data and must be represented only by local evidence hashes or approved labels in shared reports.

| Role | Required setup | Used by |
|---|---|---|
| `T1` | One target hotspot with a stable known identity and controlled traffic | F-02, F-03, F-04, F-05, F-08, F-12, R-01, R-02, R-05, R-06, R-07, R-08 |
| `T2` | One unrelated preferred network on the same Wi-Fi interface | F-07, F-09, F-10, R-03, R-04, R-09, R-12 |
| `T3` | A second Wi-Fi interface and second completed target profile, when available | AC-66 and the multiple-profile scenario |
| `T4` | A VPN or virtual interface carrying traffic over `T1` | AC-53 and the counter accounting scenario |

Before each run, the operator records the role availability, current network identities, candidate hashes, permission state, awake state, and evidence directory. F-06 through F-10 and F-12 require a separate confirmation immediately before the case. The run aborts on an unexpected target identity, unrelated-network disconnect, preference read-back mismatch, unexpected authorization prompt, sleep, or local-evidence write failure. Full steps and redaction rules are in [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md).

---

## 7. Report Fields for Every Candidate Run

- Application version
- Full source revision
- Embedded `BuildManifestV1` SHA-256 and compiled capability mode
- External `ReleaseManifestV1` identifier and SHA-256, when present
- Executable SHA-256
- GitHub release tag and exact asset SHA-256
- Actual code signature status and designated requirement, if a signature exists
- Hardened Runtime result: `enabled`, `disabled`, or `unavailable`
- App Sandbox absence result
- Notarization and stapling status, with `notApplicable` accepted for the unsigned GitHub path
- Quarantine attribute and Gatekeeper launch/approval result
- Architecture
- Exact macOS version and build
- Test start/end time and awake observation duration
- Permission and authorization outcomes
- Redacted target interface/SSID/BSSID identifiers suitable for local comparison
- Original, intended, written, and restored configuration fingerprints
- Disconnect and post-disconnect observations
- Suppression and restoration observation results
- Observation source (`eventBacked`, `pollBacked`, or `lifecycleOnly`), awake duration, and maximum gap
- Operator topology role availability and run identifier
- Unrelated-network preservation result
- Final verdict and unresolved risks

Credentials, authorization objects, packet contents, URLs, and full user-identifying network names must not be written to this record.

The local original evidence and the redacted shared report are separate artifacts. Local evidence may contain local-sensitive interface, SSID, BSSID, and configuration archive data needed for owner-side comparison. Shared reports must use hashes, approved labels, or redactions and must never contain credentials, authorization objects, packet contents, URLs, geographic coordinates, or full user-identifying network names.
