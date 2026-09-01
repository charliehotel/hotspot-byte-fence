# Hotspot Byte Fence (HBF) — Decisions Needed

**Version:** 0.2  
**Date:** 2026-09-01  
**Scope:** Binding implementation and release decisions. The remaining external facts are candidate-gate inputs, not unresolved product design questions.

This file records decisions that are now binding across the PRD and companion documents. A runtime fact that can only be learned from the exact candidate remains `PENDING` in the gate record, but the implementation contract and failure behavior are fixed here.

Destructive candidate execution and evidence redaction follow [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md).

---

## 1. Bundle and GitHub Packaging Inputs

**Decision:** Keep the bundle identifier `com.copylawbot.hotspotbytefence` for v1.

| Option | Effect |
|---|---|
| Keep `com.copylawbot.hotspotbytefence` | Allows implementation and local project setup to proceed with the existing PRD baseline |
| Replace before Xcode project creation | Avoids later bundle-id migration, but requires updating the existing document baseline |

**Resolved value:** Keep `com.copylawbot.hotspotbytefence`.

**Resolved distribution policy:** Distribute the v1 artifact directly through a GitHub Release as a Copy App. The published package is an unsigned ZIP containing the `.app` and a `SHA-256SUMS` manifest. Before supported use, the user must ad hoc-sign the extracted `.app` locally. This is an installation prerequisite for the supported path and is not Developer ID signing or notarization. Developer ID signing, notarization, and Hardened Runtime are not release prerequisites. Every release must include the exact unsigned asset SHA-256, the canonical local signing procedure, and first-launch/Gatekeeper instructions. The unsigned asset digest must be verified before signing. A locally signed app is a derived artifact; its signature and digest are recorded separately and it does not inherit exact-candidate gate evidence unless that exact signed artifact is tested. A release versioning convention remains a packaging input, but it does not block domain, measurement, or candidate-gate implementation.

---

## 2. Initial Support Matrix

**Decision:** Limit the initial support claim to macOS 26.6.2 build 25G83 on `arm64` until additional exact rows pass.

| Option | Effect |
|---|---|
| Keep only macOS 26.6.2/25G83/arm64 initially | Smallest proof burden; no broader support claim |
| Add macOS 13+ rows | Requires identity, counter, blocking, restoration, UI, and release proof on every added build/architecture |

**Resolved value:** Keep only macOS 26.6.2 build 25G83 on `arm64` as a pending validation row. The macOS 13.0 deployment target remains a compilation floor only.

---

## 3. CoreWLAN Wi-Fi Event Entitlement

**Decision:** Use polling as the universal fallback, but require event-backed observation for a strong-blocking suppression proof.

| Option | Effect |
|---|---|
| Use entitlement if available and approved | Enables event-driven link handling if the exact candidate gate proves it works |
| Avoid entitlement-dependent behavior | Reduces release risk; requires polling/lifecycle fallback to satisfy observation windows |

**Resolved value:** Do not assume the entitlement is available. The candidate uses one-second polling and public lifecycle notifications for general observation. Event callbacks requiring `com.apple.wifi.events` are optional for measurement and restoration observation, but F-12 must prove event-backed coverage before strong-blocking suppression can be verified. Absence of the entitlement does not block a measurement-only release; it prevents a strong-blocking claim.

---

## 4. Exact Authorization Right String

**Decision:** Discover and record the exact OS-accepted CoreWLAN commit right during F-06; do not invent a broad custom right.

| Option | Effect |
|---|---|
| Use documented CoreWLAN/admin right if the SDK publishes one | Strongest maintainable path |
| Record OS-accepted right from the GitHub-candidate feasibility probe | Acceptable only if public and reproducible in the gate report |

**Resolved value:** The `AuthorizationProvider` exposes only the operation `coreWLANConfigurationCommit`. F-06 records the exact right string, flags, prompt count, denial, cancellation, and relaunch behavior accepted by the exact candidate. Until that evidence exists, strong-blocking integration remains disabled. The right is a runtime capability input, not a signing input.

---

## 5. Operator Test Network Topology

**Decision:** Use the fixed topology roles `T1` through `T4` defined in the operator runbook.

| Option | Effect |
|---|---|
| One target hotspot plus one unrelated preferred network on the same Wi-Fi interface | Covers target/unrelated preference preservation |
| Add a second Wi-Fi interface and second target | Required to prove `Multiple Profiles Connected` and cross-interface behavior |
| Add VPN/virtual tunnel fixture | Required to prove VPN traffic accounting |

**Resolved value:** `T1` target hotspot and `T2` unrelated preferred network are required for strong-blocking proof. `T3` second interface and `T4` VPN path are required for their respective acceptance criteria. Missing roles leave the affected gate `PENDING` or `BLOCKED`; they are never inferred or marked passed.

---

## 6. Redacted Report Sharing Policy

**Decision:** Hash sensitive network identifiers by default in shared reports.

| Option | Effect |
|---|---|
| Hash SSID/BSSID/interface identifiers by default | Safer for sharing; local evidence remains diagnosable |
| Operator-approved human labels | Easier to read; may reveal private network identity |

**Resolved value:** Hash SSID, BSSID, and interface identifiers by default in shared reports. Keep full local-sensitive values only in owner-only local evidence.

---

## 7. Resolved Cross-Document Contracts

### 7.1 Authorization persistence

The usable `SFAuthorization` object and `processAuthorizationAvailable` are runtime-only. The store may persist only `lastAuthorizationOutcome` and related audit information. A previous success never authorizes a later process.

### 7.2 Configuration archive

`CWConfigurationArchiveV1` contains the ordered `networkProfiles` list, each profile's raw `ssidData` and `CWSecurity` raw value, and the four public configuration flags. Its canonical serializer, replay algorithm, equality oracle, and unsupported-field failure are defined in [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md). A fingerprint without a reversible archive cannot authorize restoration.

### 7.3 Profile deletion

Deletion is a full profile-scoped purge. A tombstone remains only to prevent resurrection. A completed store may retain one global `profileDeletion` event with `profileID=null`; no profile-scoped event or identifier remains after purge.

### 7.4 State and time precedence

`MultipleProfilesConnected` is application-global as a safety flag, but it stops measurement and blocking only for the current resolved target set. A deterministic forward cycle transition is not a time-adjustment error and reconciles an open preference transaction before resetting. Backward or uncertain time adjustment stops all network actions until acknowledgement.

### 7.5 Artifact and release authority

The executable's compile-time capability constant and embedded `BuildManifestV1` must agree. The external `ReleaseManifestV1` binds the exact candidate, source, asset, executable, build manifest, support row, and gate reports. Mutable local state cannot promote capability, and an external report cannot change the bytes that were tested.

### 7.6 Observation gate phases

F-12 has a preflight phase and a classification phase. `F-12-preflight` proves that the candidate can expose and record event-backed observations and the bounded polling fallback; it is the observation prerequisite for gated candidate integration. `F-12-classification` is derived from the applicable suppression and restoration R cases and is required before a strong-blocking release verdict. Polling-only evidence may support measurement or restoration observation, but it never proves automatic-reconnection suppression.
