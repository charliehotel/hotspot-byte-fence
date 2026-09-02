# Hotspot Byte Fence (HBF) — Product Requirements Document

**Product name:** Hotspot Byte Fence  
**Short name:** HBF  
**Project name:** `HotspotByteFence`  
**Target platform:** macOS  
**Product type:** Menu bar utility  
**Languages:** Korean (`ko`) / English (`en`)  
**Version:** 1.0  
**Date:** 2026-09-01  
**Status:** v1.0 product baseline — technical design and GitHub-candidate validation required  
**Decision:** GO for domain and measurement implementation against this document; CONDITIONAL GO for strong-blocking integration after the GitHub-candidate feasibility gate; CONDITIONAL GO for distribution only after the real-Mac release gate passes

---

## Required Companion Artifacts

The v1 product baseline consists of this PRD and the following companion documents. These documents are required design artifacts, not implementation evidence:

- [`HotspotByteFence_TechnicalDesign.md`](HotspotByteFence_TechnicalDesign.md): architecture, component boundaries, event ordering, implementation sequence, and verification layers.
- [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md): complete state-transition table, command contract, CoreWLAN disassociate fail-closed contract, `SFAuthorization` operation boundary, and UI/accessibility/localization state mapping.
- [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md): concrete v1 persistence records, JSON serialization, migration, LKG, tombstone, integrity/anti-rollback scope, transaction ordering, local evidence, redacted report, and non-sandboxed threat model.
- [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md): AC-01 through AC-81 to test/gate/fixture/oracle traceability, F/R gate coverage, and build/entitlement/manifest checks.
- [`HotspotByteFence_CapabilityGates.md`](HotspotByteFence_CapabilityGates.md): current GitHub-candidate and release gate record.
- `README.md`: user-facing GitHub installation, local ad hoc-signing, first-launch, and verification instructions.
- [`HotspotByteFence_DecisionsNeeded.md`](HotspotByteFence_DecisionsNeeded.md): binding implementation and release decisions, with runtime facts explicitly left to candidate gates.
- [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md): real-Mac topology, destructive-test safeguards, evidence paths, and operator confirmation contract.

When these documents disagree, this PRD controls the product requirement. The companion document must then be corrected before implementation relies on it.

---

## 0. v1.0 Decision Baseline

This document is the implementation baseline for v1.0. Normative words such as `must`, `must not`, and `shall` define required behavior. The application must not present a capability as protected until the corresponding permission and real-Mac verification gates have passed.

HBF v1 has two explicitly separated capabilities:

- **Measurement capability:** A completed profile can measure traffic when its exact network identity is resolved, subject to the measurement gaps and permission rules in this document.
- **Strong-blocking capability:** A profile can automatically disconnect and suppress automatic reconnection only when the profile is eligible for strong blocking, the required administrator authorization is available, and the artifact is an approved strong-blocking build. A GitHub validation candidate may exercise the same operations only through the explicit operator-only gate workflow described below; it must not present itself as a distributed protected build.

Strong-blocking eligibility is profile-local but is constrained by the macOS preference model. A profile is eligible only when no other completed profile uses the same pair of canonical Wi-Fi interface name and SSID bytes. BSSID sets remain necessary for exact connection matching, but they do not make automatic-connection preference changes BSSID-specific. Profiles sharing the same interface and SSID may be created only after an explicit warning and confirmation that all affected profiles are measurement-only and will report `Blocking Not Guaranteed`; HBF must not silently downgrade an existing profile's protection.

If the real-Mac strong-blocking release gate fails while the identity and counter capability gates pass, the project may distribute only a separately built **measurement-only build** whose immutable `BuildManifestV1.compiledMode` is `measurementOnly`. In that build, HBF must not call a blocking action or modify Wi-Fi automatic-connection preferences, and every completed profile must visibly report that automatic blocking is unavailable. A failure of the counter capability is not converted into a measurement-only claim: HBF must enter `Recovery Required`, must not claim accurate measurement, and must either postpone v1 or distribute only a clearly non-measurement diagnostic artifact. Blocking-related acceptance criteria are conditional on the applicable capability and release mode.

For implementation and release decisions, the gates are deliberately separated:

- The **GitHub-candidate feasibility gate** uses the exact GitHub release path: the published unsigned asset and, when supported-user behavior requires signing, the canonical post-download ad hoc-signed app. The gate record must identify both artifact states and their separate digests. Developer ID signing, notarization, and Hardened Runtime are not prerequisites for this distribution path. The tested artifact must be non-sandboxed, use public APIs only, and have its actual signature/runtime status recorded. The gate proves that the candidate can obtain exact interface name, SSID bytes, and BSSID after Location Services authorization; read the selected 64-bit interface counters; explicitly request administrator authorization through `SFAuthorization`; and execute the public CoreWLAN calls required for the operator-approved test workflow. Passing this gate authorizes strong-blocking integration work, not distribution or a user-facing protection claim.
- The **identity capability gate** means that the exact GitHub candidate artifact can obtain the exact interface name, SSID bytes, and BSSID through the selected public CoreWLAN path when the required user permission is granted.
- The **counter capability gate** means that the same exact GitHub candidate artifact can read the selected 64-bit interface counters.
- The **strong-blocking release gate** additionally requires the exact candidate's real-Mac disconnect, reconnection-suppression, unrelated-network-preservation, and lossless-restoration proof described in Section 7.1. A passing report is bound to the candidate's application version, full source revision, GitHub release asset SHA-256, actual code-signature status, architecture, and exact macOS build. The tested artifact must not be rebuilt or modified before distribution.

The v1 application itself is not App Sandbox-enabled. This is an explicit directly distributed v1 security posture because Apple's Authorization Services, including `SFAuthorization`, is unavailable to an App Sandbox process and strong blocking requires an administrator-authorized public Wi-Fi configuration change. HBF must use public APIs only, request least-privilege authorization, and enforce application-owned storage permissions. Developer ID signing, notarization, and Hardened Runtime are not required for the GitHub distribution baseline. If a build has a signature or Hardened Runtime, HBF records the actual status; an unsigned build must not claim either property or entitlement-backed behavior. v1 must not install a privileged helper or daemon. App Sandbox or a privileged-helper architecture requires a new product and threat-model decision in a later version.

### 0.1 Decision log

| Date | Decision | Alternatives considered | Reason |
|---|---|---|---|
| 2026-08-31 | Directly distribute a non-sandboxed v1 from GitHub as a Copy App; Developer ID signing and notarization are not required. A completely unsigned artifact was the initial default, with ad hoc signing optional at that time. | App Sandbox measurement-only v1; sandboxed main app with a privileged helper; Developer ID distribution. | Strong blocking requires administrator-authorized Wi-Fi configuration changes, while Authorization Services is not available to an App Sandbox process. The direct GitHub posture is the smallest v1 architecture that preserves the product's blocking goal. Gatekeeper outcome, quarantine state, and user launch instructions remain part of release evidence. |
| 2026-09-01 | Keep the published GitHub package unsigned, but require the user to apply the canonical local ad hoc-signing procedure before supported use. Record the unsigned asset digest and post-signing app-bundle/executable digests separately. | Ship a developer-signed artifact; allow an unsigned app as a supported path; require Developer ID signing. | The user-side signature satisfies the supported installation prerequisite for signing-dependent APIs such as `SMAppService` without making Developer ID or notarization a v1 requirement. A locally signed artifact remains derived from the published asset and cannot inherit exact-candidate evidence without matching post-signing evidence. |
| 2026-08-31 | Do not install a privileged helper or daemon in v1. | Root launch daemon or privileged XPC helper. | A helper adds installation, IPC authentication, upgrade, rollback, and attack-surface requirements that are unnecessary for the approved direct-distribution posture. |
| 2026-08-31 | Separate GitHub-candidate feasibility, release capability, and distribution approval gates. | Make profile eligibility depend directly on a previously passed release gate. | The prior rule was circular because the first release gate could not exercise blocking until it had already passed. |
| 2026-08-31 | Treat configuration restoration and post-restoration network observation as separate results. | Treat every automatic reconnection after restoration as restoration failure. | Restoring the user's original automatic-connection preference can legitimately allow macOS to reconnect without HBF initiating an association. |

The v1 product supports one resolved monitored profile at a time. If two or more completed profiles are simultaneously resolved on different Wi-Fi interfaces, HBF must pause measurement and blocking for all of the resolved target profiles until only one target profile remains resolved. The resulting `Multiple Profiles Connected` value is an application-global safety flag whose effect is limited to the current target resolution; profile management, settings, and disconnected-profile commands remain available. Unregistered networks on other interfaces remain outside the measurement scope.

State scope must remain explicit. `Recovery Required` for a corrupt store or an unavailable counter capability is global to the application; `Time Adjustment Required` is global because the system clock and time zone affect every profile; and `Multiple Profiles Connected` is an application-global safety flag that stops only the currently resolved target set. `Measurement Unavailable` is local to the affected target interface, while usage, limit, Pause Blocking, authorization, retry, notification, and preference-transaction state remain profile-local unless this document says otherwise.

---

## 1. Product Overview

Hotspot Byte Fence is a macOS menu bar utility that measures the amount of network data a Mac uses while connected to one user-designated Wi-Fi hotspot profile at a time. Users may register multiple profiles, but v1 resolves and measures only one target profile at a time as defined in Section 0.

Each profile represents a separately managed hotspot or SIM. The application continuously accumulates upload and download traffic for the resolved active profile, displays that profile's current usage in the macOS menu bar, and attempts to disconnect that profile's hotspot at its user-defined data limit only when the strong-blocking conditions in Section 7 are satisfied.

The primary goal is to help users safely use metered mobile hotspots without unintentionally exceeding their cellular data allowance and incurring additional charges.

The application measures traffic generated by the Mac only. Cellular data consumed directly by the hotspot device itself is outside the scope of measurement.

---

## 2. Core Product Principles

1. The menu bar must remain minimal.
2. Usage measurement must continue whenever the application is running and an active profile's designated hotspot is connected.
3. Data limits must be treated conservatively because exceeding them may incur real monetary charges.
4. Automatic blocking is a safety mechanism, but the user must always be able to override it.
5. Measurement, blocking, and warning suppression must be independent controls.
6. Usage and blocking state must survive application restarts and Mac reboots.
7. Reset cycles must work correctly for every calendar month.
8. Korean and English must be supported from v1.0.
9. Profiles must remain independent so that using one SIM does not consume or block another SIM's profile.
10. The application must fail conservatively when the active profile, measurement baseline, persisted state, or blocking result is uncertain.

---

## 3. Menu Bar Display

The menu bar displays only the current accumulated usage for the resolved active profile's current reset cycle.

Example:

`3.72GB`

The menu bar value always uses decimal GB with two fractional digits and no space before `GB`. If no connected profile is resolved, no profile is configured, the current network is unregistered or ambiguous, required identity permission is unavailable, measurement is temporarily unavailable, persisted measurement state requires recovery, or multiple target profiles are resolved, display:

`—`

The menu must guide the user to the applicable action in these states, such as creating a profile, confirming a BSSID, granting identity permission, resolving multiple targets, or recovering persisted state. It must not display `0.00GB`, because that could imply that an unmeasured network has used zero data.

Do not normally display:

- hotspot name
- percentage
- limit
- remaining data
- reset date
- icons or explanatory labels

These details belong in the menu/settings interface.

The menu bar value is formatted from the exact integer byte count using decimal division by `1,000,000,000`, rounded half up to two fractional digits. The menu bar uses an ASCII decimal point, no grouping separator, and the fixed `GB` suffix. Threshold states and blocking decisions always use the exact byte count rather than the rounded display value.

### 3.1 Usage states

Visual appearance changes according to the percentage of the active profile's configured data limit consumed.

| Usage | State |
|---|---|
| < 50% | Normal |
| >= 50% | Notice |
| >= 80% | Warning |
| >= 90% | Critical |
| >= 100% | Limit reached |

The implementation may use text color, background treatment, or another unobtrusive menu-bar-compatible visual treatment.

The design must remain legible in both macOS Light Mode and Dark Mode.

The percentage is calculated against the user-configured blocking limit, not against an independently stored carrier allowance.

Example with a 4.50 GB limit:

- 50%: 2.25 GB
- 80%: 3.60 GB
- 90%: 4.05 GB
- 100%: 4.50 GB

If Pause Blocking is enabled for an eligible profile and usage exceeds 100%, measurement and display continue normally. A measurement-only profile may also exceed 100%, but HBF must show that automatic blocking is not guaranteed.

---

## 4. Data Measurement

### 4.1 Measurement scope

Traffic is accumulated only while the Mac is connected to a resolved profile's configured hotspot/network.

Only the Wi-Fi interface associated with the connected profile is measured. HBF must not read or add counters from any other Wi-Fi interface, Ethernet, USB tethering, VPN tunnel, virtual interface, or other interface. When a VPN or virtual tunnel carries traffic over the monitored Wi-Fi interface, the underlying encrypted RX/TX bytes are part of that Wi-Fi interface's usage and must be counted once; HBF must not add the tunnel interface's counters separately. If no profile is connected and resolved, traffic must not be accumulated.

### 4.2 Traffic direction

Both are counted:

- downloaded bytes (RX)
- uploaded bytes (TX)

Total usage:

`total usage = RX + TX`

### 4.3 Data unit

Use decimal carrier-style units for every profile.

`1 GB = 1,000 MB = 1,000,000,000 bytes`

Do not use GiB (`1,073,741,824 bytes`) for usage-limit calculations.

Internally, usage must be stored as an integer byte count and converted to GB only for presentation. A profile's configured limit must be a positive value from `0.01 GB` through `1,000 GB`, in increments of `0.01 GB`.

### 4.4 Counter discontinuities

The implementation must safely handle:

- network interface changes
- interface counter resets
- sleep/wake
- Wi-Fi disconnect/reconnect
- application restart
- system reboot
- a measurement API failure or an unavailable interface

If the current underlying interface counter is lower than a previously observed value, the application must not interpret the difference as valid traffic.

The application must never manufacture or estimate unknown usage.

When the application starts, resumes from sleep, reconnects to a profile, changes Wi-Fi interface, loses the measurement interface, detects a BSSID change, or recovers from a measurement failure, it must establish a new counter baseline. Traffic between the previous valid sample and the new baseline must not be added.

A sample is valid only when the target interface is available, connected, and still matches the profile's SSID, interface name, and confirmed BSSID. If any part of that identity is unavailable or differs from the last trusted sample, HBF must not add a delta and must establish a new baseline after the identity is resolved again. If the exact target is resolved but its counter source is temporarily unavailable, HBF must show `Measurement Unavailable`, add no delta, and retry with a new baseline after recovery. If no target is connected, HBF must show `Disconnected`. A deterministic failure of the selected counter path in the exact GitHub candidate artifact enters `Recovery Required` as specified below.

### 4.5 Sampling and measurement gaps

The application reads the connected profile's Wi-Fi interface RX/TX counters on a nominal 5-second cadence while the Mac is awake. The implementation must record the actual sample time and must not manufacture missed samples. Each valid sample must evaluate the reset cycle before adding a counter delta and must evaluate the limit after adding that delta. A healthy store must durably snapshot each successful awake measurement transition on that cadence; the actual sample and flush times must be recorded.

If the interval between two trusted samples crosses an effective reset boundary, or if the current cycle identity differs from the identity associated with the previous trusted sample, HBF must discard that interval's delta, apply the new cycle state, and establish a new baseline. It must never assign pre-reset traffic to the new cycle.

The configured limit is an observed-byte threshold. The application must not apply an undisclosed safety margin. Traffic may exceed the displayed/configured limit before the next 5-second sample detects that the threshold has been reached, and the settings/help interface must disclose this limitation. The 10 MB persistence trigger has the same observation boundary: it applies only to newly measured bytes and is not a bound on physical traffic transferred between samples.

Because v1 durably flushes every successful awake sample on the nominal five-second cadence, the 10 MB condition does not create a second continuous sampler or permit deferring that required flush. It is evaluated at the valid sample boundary for accounting and disclosure, and any `bytesSinceLastFlush` value is reset after that required sample transition is durably validated.

The v1 counter source must preserve 64-bit byte values or provide equivalent wrap-safe behavior. A 32-bit interface counter is not an acceptable v1 source, even if a wrap-handling strategy is proposed. The technical design must name the public retrieval path and prove that the value remains 64-bit at the point where HBF computes deltas.

The v1 implementation baseline for the counter path is the public BSD interface-list path `sysctl(CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0)`, parsed as `if_msghdr2` with `if_data64.ifi_ibytes` and `if_data64.ifi_obytes`. The adapter must return `UInt64` values, use checked addition for RX plus TX, and reject a sample on parse, overflow, or interface-index mismatch. `getifaddrs()` data that exposes `struct if_data` and 32-bit byte fields is not an acceptable v1 source. If the path is unavailable or fails the exact GitHub candidate artifact test, HBF must enter `Recovery Required` and must not claim accurate measurement or strong blocking.

The raw `NET_RT_IFLIST2` buffer grammar is also normative. The adapter must treat the returned bytes as untrusted and walk them with a checked byte offset. Before reading any record, it must have enough bytes for the common prefix containing `ifm_msglen` and `ifm_type`; the decoded `ifm_msglen` must be at least that prefix, no greater than the remaining buffer, and must advance the offset without overflow. The current route buffer contains shorter non-target records, so record types other than `RTM_IFINFO2` may be skipped after their own length and common-prefix bounds pass. An `RTM_IFINFO2` record must additionally contain the complete supported `MemoryLayout<if_msghdr2>.size` header. Its SDK-derived `ifm_index` field and inline `ifm_data` offset must be read with bounds-checked byte copies rather than unaligned pointer loads, and the supported `if_data64` layout must be known before any counter field is read. A matching record is accepted only when the complete inline `if_data64` region, including `ifi_ibytes` and `ifi_obytes`, lies within that record. Exactly one matching record must agree with the resolved interface index and name; a missing, duplicate, truncated, zero-length, unsupported-layout, or name/index-mismatched record rejects the sample as a parser or interface-mismatch failure. These cases must be represented in the deterministic counter fixture and adapter test oracle.

The same checked-arithmetic rule applies when adding a valid delta to accumulated usage and when converting the byte count for presentation. HBF must never saturate, wrap, or silently reset an overflowing value. An arithmetic overflow preserves the last safely persisted state, stops measurement and blocking, records the failure, and enters `Recovery Required` until the user-visible recovery path resolves it.

A transient read, parse, or interface-availability failure on a previously verified counter path enters `Measurement Unavailable` for the affected target, adds no delta, and retries with a new baseline. A deterministic failure of the selected counter capability in the GitHub candidate artifact, including a failure reproduced at startup or by candidate verification, enters global `Recovery Required`; it must not be silently downgraded to measurement-only mode.

Every identity-dependent adapter read produces one stable `IdentitySnapshotV1` containing the canonical interface name, interface index, link state, raw SSID bytes, and BSSID. Because CoreWLAN exposes these values through separate reads rather than one atomic tuple, the adapter must serialize two consecutive reads from the same interface enumeration pass and accept the snapshot only when every required field is byte-for-byte equal. An event callback establishes observation provenance but does not make a mixed getter result coherent. If the two reads disagree, an event or interface change occurs between them, or any required value is unavailable, HBF must reject the snapshot and perform no measurement delta, preference write, disconnect, or suppression observation. The same stable-snapshot rule applies to the immediate checks before every preference write and disconnect.

---

## 5. Hotspot Profiles and Selection

The user can create and manage multiple Wi-Fi hotspot profiles. A profile is the unit of measurement, limit enforcement, reset-cycle calculation, persistence, notification suppression, and audit history.

### 5.1 Profile data

Each profile must store at least:

- a user-provided display alias, such as `USIM 1` or `USIM 2`
- the target SSID
- the Wi-Fi interface name
- the set of BSSIDs that the user has confirmed for this profile
- the profile-specific data limit
- the profile-specific reset day
- the current cycle identity and cycle start
- accumulated usage in integer bytes
- limit-reached, Pause Blocking, and notification suppression state

HBF computes a normalized alias by trimming Unicode whitespace first and then applying Unicode NFC normalization. The normalized alias must be non-empty, must preserve case, and must be unique across profiles. Network identity must retain non-empty SSID bytes, a non-empty canonical interface name, and at least one canonical BSSID value needed for exact matching; a display string alone is not sufficient. A canonical interface name is the exact non-empty BSD name returned for the Wi-Fi interface. BSSIDs must use lowercase colon-separated six-octet form. A profile is not complete until all three identity components and at least one confirmed BSSID are present.

The profile alias and SSID are shown in profile and settings interfaces. The menu bar continues to show usage only.

### 5.2 Profile registration

The default registration flow captures the currently connected Wi-Fi network. Capturing SSID or BSSID requires the Location Services permission described in Section 17; if that permission is unavailable, setup must stop at an explicit `Location Permission Required` state rather than saving an incomplete identity. A manual fallback may accept an SSID as 1–32 raw octets encoded as an even-length hexadecimal string with no separators, a non-empty BSD interface name, and a BSSID as six hexadecimal octets separated by colons. Manual hexadecimal input is case-insensitive and is normalized to the canonical stored form. Manual entry bypasses setup-time capture only; it does not bypass runtime identity permission, so HBF must not resolve or measure a connection while the current SSID or BSSID cannot be read. A profile remains inactive until its alias, network identity, limit, and reset day are complete. Blocking authorization is requested only when the profile is eligible for strong blocking; denial does not prevent measurement but leaves the profile visibly unprotected.

The application must not automatically create a profile for an unknown network. An unknown network is not measured and is not blocked.

When exactly one registered profile matches the complete tuple of current SSID bytes, interface name, and confirmed BSSID, that profile becomes active automatically. Profiles may share an SSID and interface only as explicitly confirmed measurement-only profiles under Section 0; their confirmed BSSID sets may be disjoint, but that distinction does not provide BSSID-specific automatic reconnection suppression. If no profile matches the complete tuple, or if more than one profile matches it, measurement and blocking must pause and the user must follow the applicable resolution flow below. HBF must reject completion of a profile or append of a BSSID that would create the same complete identity tuple in two profiles.

Network resolution must distinguish these cases:

- If the current interface and SSID do not match any profile, the network is unknown. HBF must not measure or block it; the user must create a new profile or leave it unmanaged. Selecting an existing disconnected profile does not resolve an unknown network.
- If exactly one profile has the current interface and SSID but the BSSID is new, HBF must show `Needs BSSID Confirmation` and allow an explicit append to that profile.
- If multiple profiles have the current interface and SSID but the BSSID is new, the user must select one candidate and explicitly confirm the BSSID. The append is rejected if it would duplicate another profile's complete identity.
- If the current SSID, interface, or BSSID cannot be read because the interface or required permission is unavailable, HBF must show the corresponding unavailable or permission state and must not guess the profile.

Completion or append of a profile whose interface-and-SSID pair is already used by another completed profile requires a separate warning and confirmation. The confirmation must state that the affected profiles remain measurable but cannot use strong blocking or HBF-owned automatic-connection preference changes while the pair is shared.

When a confirmed profile reconnects with a new BSSID, the application must pause measurement and blocking until the user confirms that the new BSSID belongs to the existing profile. After confirmation, append the BSSID to that profile's confirmed BSSID set. Existing confirmed BSSIDs must not be silently replaced or removed.

After a profile is completed, its SSID and Wi-Fi interface identity are immutable. The confirmed BSSID set is append-only and may change only through the explicit reconfirmation flow above. To monitor another SIM or hotspot, the user must create a new profile rather than replacing the existing profile's network identity.

### 5.3 Profile and network state

HBF must distinguish the following states:

- **Connected profile:** the single profile whose completed identity matches a currently connected Wi-Fi interface without ambiguity. Only a connected profile can accumulate usage.
- **Selected profile:** the profile currently selected in the menu/settings interface. It may remain selected while disconnected so that the user can pause blocking, inspect state, reset usage, or edit allowed settings before reconnecting.
- **Enforced profile:** a strong-blocking-eligible profile whose current cycle is limit-reached, whose blocking is not paused, whose authorization is available, and whose exact target identity is currently connected. Enforcement must continue for an enforced profile even when another profile is selected in the UI.

The term `active profile` means the connected profile when discussing measurement. When HBF disconnects a target hotspot, the profile remains selectable for management but there is no connected profile until a new network is resolved. The menu bar must display `—` while no connected profile is resolved, even if a disconnected profile remains selected.

If more than one profile could match a connected interface, or if the current BSSID is not confirmed, that interface has no connected profile and must not be measured or blocked until the user resolves the ambiguity. A profile-specific blocking action must always revalidate the exact current interface, SSID, and BSSID immediately before acting.

If more than one completed profile is resolved across all available Wi-Fi interfaces, HBF must enter `Multiple Profiles Connected`, display `—`, and perform no measurement or blocking until the user disconnects or otherwise resolves all but one target profile. A non-target network on another interface does not create this state.

### 5.4 Profile independence and deletion

Every profile has independent usage, limit, reset day, cycle state, blocking state, Pause Blocking state, notification suppression state, and audit history. If profile A reaches its limit, profile B remains usable according to profile B's state.

For deletion, a profile is inactive when it is not a connected profile and has no pending HBF enforcement or preference transaction. The user may permanently delete an inactive profile only after switching away from it, entering the exact profile alias, and confirming an irreversible warning. Deletion is a data purge: it removes the profile's configuration, usage, cycle state, notification suppression, preference transaction, and local audit history from the active store and recovery copy, and writes a tombstone so recovery cannot resurrect the deleted profile. Filesystem or external backup copies outside HBF's store are outside this guarantee.

---

## 6. Data Limit

The user can configure a data limit in GB independently for each profile.

Example:

`4.50 GB`

This is the profile's application safety/blocking threshold.

The application does not need a separate field for the carrier's advertised allowance.

For example, a user with a 5 GB mobile plan may deliberately configure a 4.5 GB limit to maintain a safety margin. HBF must not add another hidden margin.

The configured limit must be represented without binary floating-point rounding. Each `0.01 GB` step equals exactly `10,000,000` bytes, and the accepted range is exactly `10,000,000` through `1,000,000,000,000` bytes. Invalid, fractional-step, out-of-range, and overflow inputs must be rejected before saving.

The limit field accepts a decimal value with zero, one, or two fractional digits using the effective application locale's decimal separator, then normalizes it to the exact hundredth-GB integer before saving. With `System Default`, the effective locale is the current macOS locale; with a Korean or English override, it is respectively `ko-KR` or `en-US`. Only that locale's decimal separator is accepted, and the other separator is rejected. Grouping separators, exponent notation, signs, more than two fractional digits, and non-finite values are rejected. The settings view displays the saved value with exactly two fractional digits and the effective locale's decimal separator and the `GB` suffix. The menu bar remains independent of the effective locale and always uses an ASCII decimal point.

---

## 7. Automatic Blocking

Automatic blocking is a profile capability, not merely a user preference. In a distributed artifact, it is enabled by default only for a completed profile that is eligible for strong blocking, has successful administrator authorization, and is running in an approved strong-blocking build. A GitHub validation candidate may enable the same path only inside an explicit operator-only test workflow after warning that the artifact has not passed the release gate. A profile is completed when its alias, network identity, limit, and reset day have been configured.

A profile is **strong-blocking eligible** only when all of the following are true:

- the profile is complete;
- no other completed profile uses the same canonical Wi-Fi interface name and SSID bytes;
- the artifact is either an approved strong-blocking build for the current exact macOS build or a GitHub validation candidate currently running the explicit operator-only gate workflow; and
- the profile is not in `Recovery Required`, `Time Adjustment Required`, or another state that prevents a trusted target decision.

Administrator authorization is a separate capability prerequisite. Before the first strong-blocking action for an eligible profile, HBF must make one explicit user-visible `SFAuthorization` request and must not begin enforcement until the required authorization capability is available. The request must cover only the public Wi-Fi configuration commit needed by the current action. The authorization object and credentials remain in memory only, are invalidated when no longer needed, and must never be persisted. The authorization passed to `commitConfiguration` and the behavior of `disassociate()`, which has no authorization parameter, must be verified independently with the exact GitHub candidate artifact; successful authorization is never treated as proof that a configuration write or disassociation succeeded. If authorization is denied or unavailable, the profile may still measure traffic but must report `Blocking Not Guaranteed` and must not retry authorization automatically. The user must have an explicit action to try authorization again.

Authorization availability is process-local. A persisted previous success is audit history only and must not be treated as a usable authorization object after relaunch, logout, or reboot. On launch HBF may perform a non-interactive capability check that is guaranteed not to display a prompt. If a usable authorization cannot be obtained without interaction, every otherwise eligible profile reports `Blocking Not Guaranteed` until the user explicitly requests authorization again. Automatic enforcement retries must never trigger an authorization prompt.

For a profile that is not strong-blocking eligible, reaching the limit still marks the current cycle as limit-reached, continues measurement, and produces a prominent warning that automatic blocking is unavailable. HBF must not call `disassociate()`, change a Wi-Fi preference, or claim that use has been prevented for that profile.

When an eligible profile's accumulated usage reaches or exceeds its configured limit, HBF uses this order:

1. Mark the current cycle as limit-reached.
2. Re-read and revalidate the exact current interface, SSID, and BSSID. If the identity is unavailable, ambiguous, or different, perform no system change.
3. Read the complete public Wi-Fi configuration and prepare the intended interface-and-SSID-scoped configuration. If suppression requires a write, persist and durably flush the reversible `Prepared` transaction before making that write.
4. Revalidate the exact target identity immediately before the suppression write, commit the intended preference with the in-memory administrator authorization, and read it back. If the target preferred-network entry is already absent, record a verified no-op and do not create an applied preference transaction.
5. Re-read the current identity immediately before disconnecting. If the exact target remains connected, call `disassociate()` on that interface. If the target is already absent, do not disconnect another network. If identity is unavailable, do not disconnect and classify the result as unverified.
6. Verify that the exact target is absent, observe automatic-reconnection suppression for the full awake window, and reconcile or restore any HBF-owned preference transaction on failure according to Section 10.1.
7. Notify the user of the verified result.

Strong blocking is successful only after the target is confirmed disconnected and the supported automatic-reconnection behavior has been proven for that profile scope. Until then, the profile remains in a failure or not-guaranteed state.

Blocking is independent per profile. Reaching profile A's limit must not block profile B or any network whose exact interface, SSID, and BSSID identity is not profile A's target. A profile sharing an interface-and-SSID pair with another completed profile is not eligible for automatic blocking, so HBF must not make a preference change that could affect both profiles.

The application must never disable Wi-Fi globally as its normal blocking mechanism.

### 7.1 Blocking release modes and gate

The project has two explicit distribution modes and one non-distributable validation mode:

| Mode | Distribution | Measurement | Automatic blocking | Required user status |
|---|---|---|---|---|
| GitHub validation candidate | Prohibited as a protected build until all applicable gates pass | Enabled only for the explicit operator workflow after identity and counter checks | Enabled only for the confirmed gate scenario | `Validation Candidate`; never `Strong Blocking Ready` |
| Strong-blocking build | Allowed only after every applicable gate passes | Enabled when identity and counter permissions are available | Enabled only for eligible, authorized profiles | `Monitoring`, `Limit Reached`, or `Blocking Failed` as applicable |
| Measurement-only build | Allowed only after the identity and counter capability gates pass and a separately built immutable `measurementOnly` artifact is produced | Enabled when identity and counter permissions are available | Disabled for every profile; no disconnect or Wi-Fi preference mutation | `Blocking Not Guaranteed` |

The candidate lifecycle is a separate runtime guard. While `Candidate lifecycle=OperatorValidation`, the protection dimension must never become or be presented as `StrongBlockingReady`, and no persisted record may claim that state. A confirmed operator case may report only its validation action and gate result; it must not expose a protected user status or enable normal automatic enforcement. The deterministic runner must launch the exact candidate with a process-local `OperatorValidationContextV1` containing the run identifier, candidate digest, gate/case identifier, and fresh confirmation. A missing, stale, or mismatched context rejects every destructive network action. The context is never accepted from persisted state, a mutable release report, or a user preference.

Before distributing a strong-blocking build, the exact GitHub validation candidate must demonstrate on every supported macOS build that it can disconnect the target, suppress its automatic reconnection within the documented observation window, preserve unrelated Wi-Fi networks, and restore only HBF-owned changes. The candidate workflow is operator-only, requires an explicit warning and confirmation before each destructive network test, and never reports `Strong Blocking Ready`. After the report passes, the same unchanged artifact may be approved for distribution; the release record supplies the user-facing approval status and must match the candidate asset, app-bundle, and executable digests recorded in the report. If this strong-blocking gate fails while the identity and counter capability gates pass, the project may distribute only a separately built artifact with immutable `measurementOnly` mode. If either capability gate fails, the project must postpone a measurement-capable v1 release or distribute only a clearly non-measurement diagnostic artifact. HBF must not distribute an unapproved candidate or present an experimental blocking path as protected.

Within a strong-blocking build, a shared interface-and-SSID profile remains measurement-only even if its BSSID is unique. The BSSID set is used for exact matching and safe observation, not for BSSID-specific automatic-connection preference mutation.

When strong blocking is enabled, HBF may temporarily modify the monitored interface's macOS automatic-connection preference after obtaining the required administrator authorization. HBF must record the original value and restore only the changes it made. It must not overwrite unrelated user changes.

The v1 preference mutation is defined as follows. HBF reads the complete public `CWConfiguration`, preserves its ordered profile list and all other public configuration values, and prepares a copy whose `networkProfiles` omits every preferred-network entry whose raw `ssidData` equals the target SSID bytes. This is an interface-and-SSID scoped operation, not a BSSID-specific operation. Existing `CWNetworkProfile` objects must be copied without reconstructing them from display strings. If the target scope cannot be represented, round-tripped, or restored losslessly through the public API, or if no safe public mutation is available for the current configuration, HBF must perform no preference write and must report `Blocking Not Guaranteed` for that target. The release gate must include the target-present, target-absent, duplicate-security-profile, and non-target-preservation cases.

### 7.2 Reconnection attempts

If macOS automatically reconnects to an eligible blocked profile's hotspot before that profile's reset date, Hotspot Byte Fence must detect the connection and attempt to disconnect it again. A profile that is not eligible for strong blocking must not enter this retry loop.

After a blocking failure, HBF must continue attempting enforcement with a backoff schedule for as long as the target remains connected and the profile is not paused or reset. A failure notification may be muted, but the enforcement attempts must continue.

This behavior stops for that profile when:

- the profile's reset cycle changes, or
- the user pauses blocking, or
- the application is intentionally quitting.

When enforcement stops because of Pause Blocking, a reset, or an intentional application quit, HBF must restore only its own temporary Wi-Fi preference changes. HBF must never call an association API or otherwise initiate reconnection. Restoring the original automatic-connection preference may allow macOS to reconnect on its own; that reconnection is an expected possible consequence of faithful restoration and is not a restoration failure. HBF records the observed link transition without claiming that HBF or the user initiated it.

CoreWLAN link, SSID, and BSSID events do not identify whether an association was caused by the user or by macOS. During the strong-blocking suppression window, HBF must not infer manual action merely because it did not call an association API. A manual-reconnection intent for that window is recognized only through a one-shot HBF user action for the exact profile and interface, expires after 60 seconds or the next relevant link transition, and is recorded in the local event history. A reconnection during suppression without that intent is treated as automatic or unverified and fails the suppression result. This intent token is not required after enforcement has ended and the original preference has been restored.

### 7.3 Blocking action and retry contract

Before every target-suppression preference write and every disconnect, HBF must re-read the current interface, SSID, and BSSID and compare them with the exact target identity. If the identity is unavailable, ambiguous, or different, HBF must perform no new suppression or disconnect action and must record the reason locally. Because `CWInterface.disassociate()` acts on the interface's current network, a second identity check immediately before that call is mandatory; the check performed before the preference write is not sufficient. Restoration is not a target-suppression action and does not require the target to remain connected. It instead requires the exact target interface, an open HBF transaction, successful archive decoding, and the ownership fingerprint comparison in Section 10.1.

The immediate pre-call check is a fail-closed guard, not a claim of platform-level atomicity. The public API does not expose a target-identity compare-and-disassociate operation. If the current interface changes after the final check and before `disassociate()` executes, HBF must record that residual target-switch boundary as unproven; the candidate or release gate must not grant a strong-blocking claim unless the exact supported macOS build provides sufficient evidence for the required safety promise. The complete algorithm and gate wording are normative in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md).

HBF must verify the result of a disconnect attempt by querying the interface again. An API return value alone does not constitute blocking success. Blocking is successful only when the target is no longer connected, or when the target's connection state is otherwise confirmed to be absent. If the target remains connected or the result cannot be verified, the profile remains in a blocking-failure state and HBF must continue enforcement.

When HBF changes a Wi-Fi automatic-connection preference, it must first persist a versioned transaction record containing the original value and the exact value HBF intends to write. It must mark the transaction applied only after the system accepts the write. On restoration, HBF may restore the original value only when the current value still equals the last value written by HBF. If the user or another process changed the value, HBF must leave it unchanged, record a restoration conflict, and show a persistent warning.

After a blocking preference write is accepted and read back, HBF must observe the target interface for a full 30-second window while the Mac is awake to verify that the target does not reconnect without a recorded manual-reconnection intent. Relevant link/BSSID events must be processed during this window. A target reconnection without the valid one-shot intent is classified as an automatic or unverified reconnection, the blocking result is failed, and the normal retry contract applies. A reconnection carrying the valid intent is recorded as user-initiated, but does not prevent HBF from applying the normal enforcement policy when the target remains limit-reached. If the application quits or the Mac sleeps before the window completes, the blocking result is `Unverified` and HBF must not claim that automatic reconnection was suppressed.

After any preference restoration, HBF must read back and compare the complete public configuration before marking the configuration transaction `Restored`. It must then observe the network state for at least 30 seconds while the Mac is awake under the observation contract in Section 7.4. The configuration-restoration result and the post-restoration network-observation result are separate. A target reconnection during this window is recorded as an observed macOS or unclassified association and does not turn a verified configuration restoration into a failure. If the application quits or the Mac sleeps before the full observation window completes, the configuration transaction may remain `Restored` when read-back already succeeded, but the observation result is `Unverified`; HBF must not claim that post-restoration network behavior was fully observed.

An authorization denial is a capability state, not a transient blocking failure. Automatic retries must never display a new administrator-authorization prompt. The user must have an explicit action to retry authorization, while the profile continues measuring and visibly reports that automatic blocking is not guaranteed until authorization succeeds.

### 7.4 Network observation contract

Every suppression or restoration observation is composed of typed `WiFiObservationV1` values. Each value contains the canonical interface name, link state, optional raw SSID bytes, optional BSSID, an observation source, the current process lifecycle identifier, and a monotonic observation timestamp. Display names, elapsed wall-clock time, and the absence of an HBF association call are not observation evidence.

The supported observation sources are:

- `eventBacked`: a `CWWiFiClient` link, SSID, or BSSID callback was received and the adapter immediately read the current snapshot. A public lifecycle notification by itself is not an event-backed observation.
- `pollBacked`: the adapter read the current snapshot on the one-second awake polling cadence or immediately after a public lifecycle notification. Polling must not exceed a two-second gap between accepted observations while an observation window is active.
- `lifecycleOnly`: only a sleep, wake, quit, or relaunch boundary was observed. It never proves network presence or absence.

During a 30-second suppression window, a `Verified` result requires `eventBacked` observations, no awake observation gap over two seconds, and a final target-absent observation. If the exact candidate lacks the entitlement or runtime behavior needed for event-backed observations, the suppression result is `Unverified`, the strong-blocking gate fails, and the project may produce only a separately built measurement-only artifact when the identity and counter gates pass. During a restoration observation, `pollBacked` observations may establish a separate `Verified` observation result when the same coverage rule is met, but they never establish a strong-blocking suppression claim. Any sleep, quit, relaunch, or observation gap over two seconds ends the current window as `Unverified`.

The persisted observation summary uses the fixed fields `result`, `source`, `awakeSecondsObserved`, `maxGapSeconds`, and `targetAbsentAtEnd`; those values must be derived from the typed observations and never inferred from a timer or lifecycle event.

When an eligible target reconnects, HBF must attempt enforcement immediately after exact-identity verification. After a failed attempt while the target remains connected, retries occur after 5 seconds, 15 seconds, 30 seconds, 1 minute, and then every 5 minutes until the profile is paused or reset, the target disconnects, or the application intentionally quits. A reconnect or explicit state change restarts this schedule. The retry schedule must never automatically reconnect the target. A failed or unverified preference restoration does not authorize HBF to overwrite a user change; it enters the persistent restoration-conflict state instead.

---

## 8. Pause Blocking

The user must be able to temporarily disable only the connection-blocking behavior for the selected strong-blocking-eligible profile. For a measurement-only or shared-interface-and-SSID profile, the control is shown as unavailable with an explanation that blocking is already not guaranteed; it must not imply that measurement is paused.

Suggested UI terminology:

Korean: `접속 차단 일시 중지`  
English: `Pause Blocking`

When blocking is paused for an eligible profile:

- data measurement continues
- menu bar usage continues updating
- threshold visual state remains active
- usage may exceed the configured limit
- automatic hotspot disconnection stops
- reset-cycle calculations continue
- other application functionality remains active

When the user turns Pause Blocking off, normal blocking policy resumes immediately. If the selected profile is eligible, authorized, already at or above its limit, and its exact target is connected, HBF must begin the blocking action without waiting for another scheduled sample. Turning Pause Blocking off must not reconnect a disconnected hotspot.

If the profile was disconnected by HBF before Pause Blocking was enabled, enabling Pause Blocking does not automatically reconnect it. The user may reconnect manually, after which measurement resumes according to the normal profile rules.

Example:

The configured limit is 4.50 GB.

The user reaches 4.50 GB and the hotspot is blocked. The user receives temporary additional carrier data or decides that paying overage charges is acceptable.

The user enables Pause Blocking.

Usage may then continue:

`4.72GB`  
`5.31GB`  
`6.02GB`

without losing measurement.

### 8.1 Scope of Pause Blocking

Pause Blocking applies only to the selected eligible profile's current reset cycle. The control must remain available for a selected profile that HBF has disconnected and that is currently offline.

At the beginning of the next reset cycle:

- usage resets to zero
- limit-reached state clears
- blocking policy resumes automatically when the profile is eligible and authorized
- Pause Blocking returns to off

This makes the override temporary by design.

---

## 9. Reset Cycle

Each profile has its own reset cycle. A profile's cycle identity is calculated from the effective reset date in the current macOS system time zone.

### 9.1 Default

Default reset day:

`1`

For each profile, the new cycle begins at:

`00:00 local time`

on the effective reset date.

### 9.2 User configuration

The user may select a reset day independently for each profile from:

`1–31`

### 9.3 End-of-month fallback

If the configured reset day does not exist in a particular month, use that month's final calendar day.

The configured value itself must not be modified.

Examples:

Configured day: 27  
Result: always the 27th.

Configured day: 29  
Result:
- February in a non-leap year: February 28
- February in a leap year: February 29
- all other months: 29th

Configured day: 30  
Result:
- February: February 28 or 29
- other months: 30th

Configured day: 31  
Result:
- February: February 28 or 29
- April, June, September, November: 30th
- other months: 31st

After a fallback month, the application must return to the originally configured reset day whenever that day exists.

The cycle identity is the effective local reset date that most recently occurred, not merely the configured reset day or the calendar month. For example, a profile configured for day 31 has a cycle beginning on April 30 and the next cycle beginning on May 31. HBF must persist the trusted effective date together with the IANA identifier of the macOS system time zone used to calculate it. A cycle start instant is persisted separately when local-time disambiguation is required.

The cycle calendar uses civil local time. If a time-zone rule makes local 00:00 unrepresentable on an effective reset date, HBF must use the first representable instant on that local date and record the adjustment in the event history. Interval timing for counter samples must use a monotonic clock; wall-clock time is used only to determine the cycle.

Within one process and one awake interval, HBF must compare trusted wall-clock observations with an injected monotonic clock. A wall-clock movement backward, or a divergence of more than 60 seconds from the monotonic elapsed interval, is a clock-adjustment event. Sleep/wake notifications close the current sample interval; HBF must not compare elapsed time across that lifecycle boundary and must establish a new baseline after wake. After an application restart or Mac reboot, the prior process's monotonic timestamp is not comparable. HBF may use the persisted wall-clock observation only to detect that the current wall clock is earlier than the trusted observation or that the time-zone identifier changed; a later wall clock is treated as an unmeasured lifecycle gap, not as proof that no clock adjustment occurred. A forward adjustment that skips one or more reset boundaries advances directly to the current cycle, resets the profile once, discards the gap, and establishes a new counter baseline. A forward adjustment that stays within the same cycle preserves usage but still establishes a new baseline and records the adjustment.

If a time-zone or clock change makes the newly calculated cycle earlier than the persisted trusted cycle, HBF must not roll back to an older cycle or restore older usage. It must preserve the trusted state, establish a new baseline, enter a persistent `Time Adjustment Required` state, and require explicit user acknowledgement before measurement or blocking resumes. If the calculated cycle is not earlier but a backward adjustment is detected, HBF must also preserve usage, establish a new baseline, enter the same recovery state, and require acknowledgement. While this state is unresolved, HBF must perform no measurement, enforcement, suppression, disconnect, or new preference write. The only exception is an ownership-proven restoration of an already open HBF preference transaction, which is cleanup rather than resumed enforcement and must satisfy the restoration archive, fingerprint, authorization, read-back, and persistence guards. If those guards cannot be satisfied, HBF must leave the current system value unchanged and persist the applicable restoration-pending, conflict, or unverified result.

Acknowledging a time adjustment accepts the current system time zone and wall clock as the new trusted observation, retains the trusted cycle and usage when no forward cycle transition is required, marks the measurement baseline pending, and records the acknowledgement. If the current calculation is later than the trusted cycle, HBF advances to that cycle and resets once before resuming measurement. HBF must never use the acknowledgement to restore older usage or import traffic from the uncertain interval.

### 9.4 Reset behavior

At the start of a new profile cycle:

- accumulated usage becomes 0 bytes
- limit-reached state clears
- hotspot blocking state clears
- Pause Blocking becomes off
- cycle-specific notification suppression clears
- temporary HBF-owned Wi-Fi automatic-connection changes are restored when the profile's enforcement ends, even if eligibility has since been lost; the ownership checks in Section 10.1 still apply

The reset logic must not depend on the Mac being awake at exactly 00:00.

Whenever the application starts, wakes, reconnects, or performs a measurement, it must first determine whether the current reset cycle for the relevant profile has changed. If the Mac slept across one or more reset boundaries, the application must move directly to the current cycle, reset the profile state once, and must not add traffic from the sleep gap. A sleep or lifecycle transition always requires a new counter baseline before the next delta.

When a profile is completed, its initial usage is `0` bytes in the current cycle. Traffic before profile completion is not reconstructed.

Changing a profile's reset day requires an explicit confirmation. If the user cancels, the previous reset day remains active. If the user confirms and the new effective date places the current time in a new cycle, the profile immediately starts that new cycle and resets its usage, limit-reached state, Pause Blocking state, notification suppression, and HBF-owned blocking preference changes. If the confirmed reset-day change leaves the effective cycle unchanged, HBF preserves usage and cycle state, records the configuration change, discards any pending counter interval, and requires a new measurement baseline before adding another delta.

If the system time zone identifier changes, the application recalculates the relevant profile's cycle using the new current system time zone at the next relevant operation. The forward and backward-change rules above apply, even when the effective reset date happens to remain the same. A cycle transition or time-adjustment recovery must never import a counter delta collected before the transition.

Changing build mode, adding a profile that makes an existing interface-and-SSID pair shared, or otherwise losing strong-blocking eligibility must not strand an open preference transaction. HBF must first reconcile and, when ownership checks permit, restore its temporary preference change; if restoration is uncertain or conflicts with a user change, it must preserve the current system value and enter the persistent conflict or `Unverified` state. A measurement-only artifact must never create a new preference transaction.

---

## 10. Persistent State

The application must persist enough state to survive:

- normal application restart
- unexpected application termination
- logout/login
- Mac reboot

For every profile, persist at minimum:

- profile identifier and user alias
- configured SSID
- configured Wi-Fi interface
- confirmed BSSID set
- configured data limit
- configured reset day
- accumulated usage
- current cycle identity/start
- blocking/limit state
- Pause Blocking state
- notification suppression state

The store must also persist the selected profile identifier, a `hasCompletedProfile` installation marker, the strong-blocking build mode observed from the exact release artifact for audit only, and enough trusted observation state to recover safely. The artifact's immutable build metadata and release manifest are authoritative; a mutable persisted value must never enable blocking. A mismatch between the artifact mode and the observed audit value must be recorded and reconciled before blocking resumes.

- last trusted effective cycle date and cycle-start instant
- IANA system time-zone identifier used for that trusted cycle
- last trusted wall-clock observation and whether a time acknowledgement is required
- exact last trusted interface identity and RX/TX counters, or an explicit baseline-pending marker
- blocking capability, last authorization outcome for audit, retry state, and last failure/restoration state; process-local authorization availability is runtime-only memory state, is omitted from every persisted record, and persisted authorization history must never be treated as a usable authorization object
- HBF preference transaction identifier, phase, original configuration fingerprint and reversible original configuration snapshot, intended configuration fingerprint and reversible intended configuration snapshot, and the last value written by HBF

Persist byte counts as decimal integer strings on disk and decode them into checked `UInt64` values. A monotonic sample timestamp is valid only for the current process and must not be treated as comparable across an application restart or reboot; a new baseline is mandatory after those transitions. The persisted usage and presentation conversion must use the overflow behavior in Section 4.5 and must never wrap or saturate.

The application must also persist the selected language preference when an application-specific override is provided.

Usage state must be durably saved after every successful awake measurement transition on the nominal 5-second cadence. If a valid sample observes 10 MB or more of newly measured traffic since the previous durable snapshot, HBF must persist that transition immediately rather than waiting for the next scheduled opportunity. The 10 MB value applies only to measured deltas; it is not a continuous physical-traffic bound. Save immediately on application termination, sleep, profile/network changes, reset transitions, and other state transitions. The five-second rule bounds the measured persistence gap only while the store accepts and durably flushes writes. If a required write or flush fails, HBF must stop adding new usage and stop blocking actions, preserve the last-known-good store, record the failure, and enter `Recovery Required` rather than continuing with an unbounded in-memory gap.

The persisted store must be versioned and use atomic or otherwise crash-safe replacement semantics. HBF must retain a last-known-good snapshot or equivalent recovery copy so that a failed replacement does not destroy the prior valid state. A separate crash-safe installation marker records whether a completed profile has ever existed. A completed-profile commit must durably write and validate the profile store before marking the installation marker; if a valid store contains a completed profile but the marker is absent, HBF may repair the marker only after integrity validation and must record the repair. A missing store is a valid first-run condition only when that marker is absent, no recovery copy exists, and no valid store indicates that a completed profile existed. Once a completed profile has existed, a missing, unreadable, or corrupt profile/usage store is a recovery condition; HBF must not recreate it with zero usage. A schema migration must be version-specific, crash-safe, and completed before measurement or blocking resumes. Unknown future schema versions or failed migrations enter `Recovery Required`.

Every transition that must update more than one persistence file uses a crash-safe `CommitJournalV1` before the first file replacement. The journal records the operation, target store revision, ordered phase, and the validated digests of `state.json`, `state.lkg.json`, `installation.json`, and `tombstones.json` as each required file commits. The journal is flushed after each phase and is marked `complete` only after all required files validate. On launch, a missing journal is acceptable only when all cross-file relations validate and no transition is in progress. A non-complete journal, a digest or revision mismatch, or an unexplained cross-file cut point enters `Recovery Required`; HBF must preserve the candidate files and must not select a lower or merely newer copy automatically. The only automatic continuation exception is resuming an incomplete deletion purge from its already durable tombstone, without exposing the deleted profile.

In the recovery condition, HBF must stop measuring and blocking, display a persistent recovery error, preserve the unreadable data for diagnosis, and offer a user-visible path to restore a valid recovery copy. HBF must not guess which network to disconnect or perform another network action while recovery is unresolved. A destructive start-over action, if provided, requires a separate explicit confirmation and must state that prior usage cannot be reconstructed.

Because a crash or forced termination can occur between persistence points, the store may lose only the measured-but-not-yet-persisted interval allowed by the healthy five-second sampling and flush cadence. The 10 MB value does not limit unobserved physical traffic between samples. HBF must not present any lost interval as recovered or exact usage after relaunch; it must establish a new baseline and record the measurement gap. A write failure suspends this measured-gap guarantee until a valid store or recovery copy has been restored.

The application must keep a local event history for cycle transitions, counter rebaselines, limit transitions, blocking attempts and failures, authorization failures, profile changes, manual resets, time adjustments, preference restoration conflicts, and permission changes. Retain the current cycle and the preceding 90 days, then delete older events automatically. Do not record packet contents, URLs, geographic coordinates, or remote diagnostic telemetry.

### 10.1 Persistence and preference transaction contract

The canonical store is a versioned local record with the following logical groups:

- **Global:** schema version, store revision, `hasCompletedProfile`, selected profile identifier, language override, embedded `BuildManifestV1` schema/hash/source revision, non-authoritative observed build mode, and last-known-good revision. The authoritative distribution mode comes from the exact artifact's immutable build metadata and release manifest rather than this mutable store.
- **Profile identity:** stable profile identifier, NFC-normalized alias, raw SSID bytes, canonical interface name, confirmed BSSID set, and the shared-interface-and-SSID blocking eligibility result.
- **Cycle and measurement:** configured limit bytes, reset day, trusted cycle date/start instant/time-zone identifier, usage bytes, baseline-pending flag, last trusted identity, last RX/TX counters, and last trusted wall-clock observation.
- **Enforcement:** limit-reached flag, Pause Blocking flag, authorization capability, blocking capability, retry sequence/state, next retry eligibility, and persistent failure or restoration status. The usable authorization object and process-local availability flag are never persisted.
  - **Preference transaction:** transaction identifier, target interface-and-SSID scope, a reversible `CWConfigurationArchiveV1` of the original public configuration, original configuration fingerprint, a reversible `CWConfigurationArchiveV1` of the intended public configuration, intended configuration fingerprint, a reversible archive or exact value of the last HBF-written configuration, last HBF-written fingerprint, fingerprint algorithm/schema version, phase (`Prepared`, `Applied`, `RestorationPending`, `Restored`, `Conflict`, or `Unverified`), and a separate post-restoration observation result (`Pending`, `Verified`, or `Unverified`). These archives must contain only the public fields listed in the persistence schema, must not contain credentials or packet data, and must be discarded rather than used if the selected macOS version cannot safely decode or replay them.
  - **Commands, notifications, and events:** command name/idempotency key/result ledger, cycle-bound mute state, persisted mute expiry, once-per-cycle success notification state, failure-notification throttle state, and the local event history. A repeated command key returns the durable historical result without a second mutation or system side effect. For process-local commands, the response separately evaluates current effect availability; a historical success never recreates authorization or a manual-reconnection token after relaunch. The preference transaction remains authoritative for crash recovery of system writes.

Before HBF writes a Wi-Fi preference, it must persist a `Prepared` transaction and flush it successfully. The transaction must contain a lossless, reversible representation of the original and intended public configurations; a fingerprint alone is not sufficient for restoration after a crash. It may mark the transaction `Applied` only after the system accepts the write and a read-back confirms the intended configuration. During restoration, HBF may write the original configuration only if the current configuration fingerprint equals the last HBF-written fingerprint. After the write, it must read back the result before marking the configuration transaction `Restored`, then separately complete and record the post-restoration network-observation window. A restored configuration may therefore coexist with an `Unverified` observation result when the read-back succeeded but the observation window was interrupted. An uncertain write, read-back, or archive decode enters `Unverified` recovery and must not be silently retried with a new preference value.

A configuration fingerprint must be `hbf-cwconfig-v1-sha256` over the canonical UTF-8 JSON bytes of `CWConfigurationArchiveV1`, with ordered preferred-network entries, raw SSID bytes, security raw values, and every v1 public configuration flag represented explicitly. The archive schema, canonical serializer, replay algorithm, equality oracle, and unsupported-field rule are fixed in [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md). The fingerprint algorithm and schema version must be persisted with the transaction. If the public API cannot represent, archive, compare, or replay a field faithfully, HBF must not mutate that preference in v1. At most one open preference transaction may exist for a target interface, and measurement, identity resolution, enforcement, and restoration transitions for that interface must be serialized so that a stale read cannot race a preference write.

An explicit profile deletion must first durably record a deletion tombstone for the stable profile identifier, then remove that profile from the active store, last-known-good snapshot, preference transactions, and profile-scoped event history before the deletion is reported complete. After the purge validates, HBF may append one global `profileDeletion` audit event with a null `profileID`; that event must not contain the deleted identifier. The tombstone is the only retained record of the deleted profile's stable identifier. The tombstone must survive recovery-copy selection and must prevent an older recovery copy from resurrecting the profile. If the purge is interrupted, HBF must resume or report a persistent deletion-recovery state and must not report completion prematurely. External filesystem or backup copies remain outside HBF's control.

---

## 11. Login and Application Lifetime

Hotspot Byte Fence is intended to run continuously.

It must support automatic launch when the user logs into macOS. Automatic launch is enabled by default after setup and can be disabled by the user.

The settings interface must show the launch-item state as enabled and approved, awaiting user approval, disabled, or failed. If automatic launch is not approved or cannot be registered, HBF must warn that measurement and blocking are guaranteed only while the application is running and must provide guidance for restoring the login-item authorization.

### 11.1 User-initiated quit

If the user attempts to quit the application, display a warning before termination. If HBF currently owns temporary Wi-Fi automatic-connection changes, restore those changes before a confirmed voluntary quit.

Korean concept:

> 앱을 종료하면 핫스팟 데이터 사용량을 측정할 수 없습니다. 앱이 종료된 동안 사용한 데이터는 이후 복구할 수 없습니다.

English concept:

> Hotspot data usage cannot be measured while the app is not running. Data used while the app is closed cannot be recovered later.

Actions:

- Cancel
- Quit

The application must not pretend to reconstruct traffic that occurred while it was not running. A force quit, crash, or system shutdown may bypass the warning and cleanup; the next launch must reconcile HBF-owned Wi-Fi changes before enabling enforcement and establish a new measurement baseline before measuring again. If reconciliation is uncertain, HBF must not write a new Wi-Fi preference and must show the recovery warning described in Section 10.

For a normal user-initiated Quit, HBF must not terminate while an owned preference restoration is pending, failed, or unverified. It must show the restoration error and offer `Retry`; the user can still use macOS Force Quit, which follows the crash/force-termination recovery path above. HBF must not claim that a voluntary quit completed cleanup until the preference read-back and observation window have completed or no HBF-owned transaction exists.

---

## 12. Blocking Failure

Because the application's purpose includes preventing potentially chargeable overage, failure to disconnect the hotspot is a high-priority condition.

If a strong-blocking-eligible profile's configured limit has been reached and the application cannot disconnect that profile's hotspot or cannot verify the result, notify the user prominently and show a persistent in-app `Blocking Failed` state.

Korean concept:

> 데이터 한도를 초과했지만 핫스팟 연결을 차단하지 못했습니다. 계속 사용하면 추가 요금이 발생할 수 있습니다. 네트워크 사용을 중지해 주세요.

English concept:

> The data limit has been reached, but Hotspot Byte Fence could not disconnect the hotspot. Continued use may result in additional charges. Stop network usage.

The application must continue attempting to enforce blocking with backoff unless Pause Blocking, a reset cycle, loss of strong-blocking eligibility, or intentional application quit disables enforcement. A profile that is measurement-only or lacks administrator authorization is not a blocking failure because no blocking action is attempted; it must show `Blocking Not Guaranteed` and provide the relevant recovery or manual-disconnect guidance.

If administrator authorization is denied or unavailable, measurement for the profile may continue, but the profile must clearly show that automatic blocking is not guaranteed. HBF must not report the profile as safely protected and must not issue automatic authorization prompts during retries. The user must explicitly request authorization again.

---

## 13. Notification Suppression

Blocking-failure warnings must support temporary suppression independently for each profile and current cycle.

Required choices:

- suppress for 10 minutes
- suppress for 1 hour
- suppress for the remainder of the current reset cycle

Suggested Korean labels:

- `10분 동안 알림 끄기`
- `1시간 동안 알림 끄기`
- `이번 주기 동안 알림 끄기`

Suggested English labels:

- `Mute for 10 Minutes`
- `Mute for 1 Hour`
- `Mute for This Cycle`

Notification suppression affects notifications only.

It must NOT:

- stop measurement
- stop blocking attempts
- enable Pause Blocking
- modify the data limit

Notification suppression and Pause Blocking are separate functions.

A successfully enforced limit notification is sent once per profile and cycle. A blocking-failure notification is sent when the failure state begins and, if the state persists, at most once when a temporary mute expires and no more often than once per five-minute retry interval. Notification throttling never changes enforcement. If macOS notification authorization is denied or an alert cannot be displayed, the menu and settings interface must continue showing the failure state and provide guidance for restoring notification authorization.

The 10-minute and 1-hour mute options expire at their persisted wall-clock expiry time, including while the Mac sleeps. `Mute for This Cycle` is bound to the persisted cycle identity and clears when that identity changes. A mute never changes the retry schedule or the profile's blocking state.

---

## 14. Manual Usage Reset

Provide a manual method to reset the selected profile's measured usage.

Because an accidental reset can create a false sense of safety and potentially lead to carrier overage charges, require explicit confirmation.

Korean concept:

> 현재 사용량을 0으로 초기화하시겠습니까? 통신사에 기록된 실제 데이터 사용량은 초기화되지 않습니다.

English concept:

> Reset the current measured usage to zero? This does not reset the actual data usage recorded by your carrier.

Actions:

- Cancel
- Reset

After confirmation, manual reset sets the profile's usage to zero, establishes a new counter baseline when its interface is available, and reevaluates the limit state. If the profile is disconnected, HBF must mark a baseline pending and establish it on the next exact profile connection; traffic before that baseline is not reconstructed. If the reset clears a limit-reached state for an eligible profile, HBF must stop that profile's retry schedule and restore only its own temporary Wi-Fi preference changes using the ownership checks in Section 7.3. For a measurement-only profile, no blocking action or preference restoration is attempted. It does not change the profile's reset day or cycle identity, Pause Blocking state, notification suppression state, carrier-side usage, or the actual Wi-Fi connection. If the profile was disconnected, HBF must not automatically reconnect it. A preference restoration conflict or unverified restoration remains visible as a persistent warning.

---

## 15. Changing the Limit Mid-Cycle

If the user lowers a profile's configured limit below the already accumulated usage, the application must immediately treat that profile's limit as reached.

Example:

Current usage: `3.80 GB`  
Old limit: `4.50 GB`  
New limit: `3.50 GB`

Result:

- limit-reached state becomes active
- strong blocking is attempted only when the profile is eligible, authorized, and Pause Blocking is off
- the user is informed appropriately

If the user attempts to increase the limit above current usage, HBF must request separate confirmation before saving the new limit. Cancelling keeps the old limit and all existing state. After confirmation, if usage is below the new limit, HBF clears limit-reached, stops that profile's retry schedule, and restores the profile's blocking policy using the ownership checks in Section 7.3 when the profile is eligible, but does not automatically reconnect the hotspot. If usage is still at or above the new limit, the profile remains limit-reached. Pause Blocking and the once-per-cycle notification history are not changed by this operation. A preference restoration conflict or unverified restoration remains visible as a persistent warning.

---

## 16. Menu / Settings

The menu bar interface must provide access to at least:

- profile list, connected profile, and selected profile
- create profile
- edit profile settings except immutable SSID/interface identity; append a BSSID only through explicit reconfirmation
- permanently delete an inactive profile
- monitored hotspot/network
- current cycle usage
- data limit
- reset day
- next effective reset date
- automatic blocking status
- Pause Blocking
- manual usage reset
- explicit one-shot manual-reconnection intent while a strong-blocking suppression observation is active
- settings/preferences
- quit

The menu/settings interface must expose explicit profile state rather than inferring safety from the usage number alone. Status is compositional, not a single mutually exclusive enum. It must show a measurement/connection state and an independent protection state.

The measurement/connection state must distinguish: `Monitoring`, `Disconnected`, `Needs BSSID Confirmation`, `Unknown Network`, `Multiple Profiles Connected`, `Location Permission Required`, `Measurement Unavailable`, `Recovery Required`, and `Time Adjustment Required`. The protection state must distinguish: `Strong Blocking Ready`, `Limit Reached`, `Blocking Failed`, `Blocking Paused`, `Blocking Not Guaranteed`, and `Restoration Conflict`. A profile may show more than one relevant protection flag, for example `Limit Reached` plus `Blocking Paused` or `Limit Reached` plus `Blocking Not Guaranteed`. `Measurement Unavailable` and `Recovery Required` take precedence over normal measurement and blocking actions and permit no network action while unresolved. `Time Adjustment Required` also stops normal measurement, enforcement, suppression, disconnect, and new preference writes; it permits only an ownership-proven cleanup restoration of an already open HBF transaction under the documented restoration guards. These states must remain understandable without relying on color alone.

The user must be able to select and manage a disconnected profile from the profile list. Selecting a disconnected profile does not make it measurable and does not automatically reconnect its hotspot. This is the path for pausing a profile after HBF has disconnected it before the user reconnects manually.

The selected profile identifier is persisted. If it is absent or no longer exists after recovery, HBF selects no profile until the user chooses one. Selecting a profile never changes the connected-profile resolution result.

The normal menu bar item itself remains usage-only.

Example:

`3.72GB`

---

## 17. Localization

Hotspot Byte Fence v1.0 supports:

- Korean
- English

All user-facing strings must be localizable, including:

- menu items
- settings
- buttons
- warnings
- notifications
- confirmation dialogs
- error messages
- accessibility labels

Use the platform's modern localization mechanism, preferably String Catalogs (`.xcstrings`).

Default behavior should follow the user's macOS language.

Because CoreWLAN SSID/BSSID identity access may require Location Services, the application must include `NSLocationUsageDescription` and request authorization only when setup or identity resolution needs it. The settings interface must show `Location Permission Required` when authorization is denied, restricted, or unavailable, explain that HBF uses the permission only to resolve Wi-Fi identity and does not collect geographic coordinates, and provide a link to the relevant macOS privacy settings. Revoking the permission while HBF is running must pause identity resolution, measurement, and blocking until the identity can be confirmed again. Manual identity entry does not bypass this runtime boundary. A future macOS build that changes the required key needs a separate support-matrix entry and proof before support is claimed.

An application language selector must offer:

- System Default
- 한국어
- English

The selector must use `System Default` unless the user chooses Korean or English.

Product name `Hotspot Byte Fence` is not translated.

Units such as `GB` remain consistent across languages.

---

## 18. Measurement Disclaimer

The application must clearly explain in settings/help that it measures traffic generated by the Mac while connected to the selected profile's hotspot and only after that profile's network identity has been resolved.

The measurement is based on the RX/TX byte counters of the target Wi-Fi interface. It is not a carrier meter and cannot automatically account for cellular data consumed directly by the hotspot device or by other devices using the same cellular plan. Interface accounting, protocol overhead, measurement gaps, and sampling delay may cause the result to differ from carrier-reported usage. When a VPN or virtual tunnel uses the target Wi-Fi connection, the physical Wi-Fi transport bytes are included once; HBF does not count the tunnel interface separately.

Location Services authorization may be required to read the current SSID and BSSID. HBF uses that authorization for network identity resolution only and does not store geographic coordinates. Profiles that share an interface-and-SSID pair remain measurable but cannot make a BSSID-specific strong-blocking promise. Two SIMs or hotspot states that expose the same exact interface, SSID, and BSSID cannot be distinguished by HBF and must not be represented as independent completed profiles.

Korean concept:

> Hotspot Byte Fence는 이 Mac이 지정된 핫스팟을 통해 사용한 데이터만 측정합니다. 핫스팟 기기 자체 또는 다른 기기에서 사용한 셀룰러 데이터는 포함되지 않습니다.

> 이 수치는 이 Mac의 Wi‑Fi 인터페이스 기준이며 통신사 청구량과 다를 수 있습니다. 앱 종료·절전 중 사용량은 복구되지 않고, 샘플링 지연으로 설정 한도를 넘을 수 있습니다.

> VPN을 사용하는 경우에도 대상 Wi‑Fi를 통해 실제 전송된 암호화 트래픽은 한 번 포함되며, VPN 가상 인터페이스의 사용량을 별도로 더하지 않습니다.

English concept:

> Hotspot Byte Fence measures only data used by this Mac through the selected profile's hotspot. Cellular data used directly by the hotspot device or by other devices is not included.

> This value is based on this Mac's Wi-Fi interface and may differ from the carrier's billing meter. Usage during application downtime or sleep is not recovered, and sampling delay may allow usage to exceed the configured limit before detection.

> When a VPN uses the target Wi-Fi connection, the encrypted traffic transported over that physical Wi-Fi interface is included once. The VPN tunnel interface is not counted separately.

---

## 19. Safety Requirements

Because incorrect behavior may result in monetary charges:

1. Never silently assume blocking succeeded.
2. Never globally disable Wi-Fi as the normal blocking mechanism.
3. Never fabricate usage for periods when measurement was unavailable.
4. Persist measured usage safely.
5. Warn before manual usage reset.
6. Warn before application termination.
7. Continue measurement while blocking is paused.
8. Continue blocking attempts while notifications are muted.
9. Evaluate reset-cycle changes before adding new traffic.
10. Prefer conservative behavior when measurement or blocking state is uncertain.
11. Never measure an unregistered, ambiguous, or unconfirmed network.
12. Never treat an application restart or sleep gap as measured traffic.
13. Never recreate corrupt persisted usage as zero.
14. Restore only temporary Wi-Fi settings changes made by HBF.
15. Never automatically reconnect a hotspot when blocking is paused, reset, or cleared.
16. Keep profile state and blocking decisions independent across SIMs.
17. Never hide a possible sampling overrun behind an undisclosed safety margin.
18. Keep state events local and exclude packet contents, URLs, and remote telemetry.
19. Count traffic transported through a VPN or virtual tunnel over the target Wi-Fi interface once, without separately adding tunnel-interface counters.
20. Never disconnect or modify a network without immediate exact-identity revalidation and post-action verification.
21. Never roll back a trusted cycle or restore older usage after a backward clock or time-zone change.
22. Never overwrite a user-modified Wi-Fi preference while restoring HBF-owned changes.
23. Never use a 32-bit interface byte counter as the v1 measurement source.
24. Never use a private or undocumented BSSID-specific preference mechanism to imply strong blocking.
25. Never silently downgrade a profile from strong blocking to measurement-only.
26. Never treat an unknown network, an ambiguous network, or a missing identity permission as a resolved profile.

---

## 20. Acceptance Criteria

### AC-01: Target-only measurement
Given exactly one completed profile is resolved on `Hotspot A`'s Wi-Fi interface, counters from another Wi-Fi network, Ethernet, USB tethering, a VPN tunnel interface, or another virtual interface do not increase HBF usage. VPN traffic whose underlying packets traverse `Hotspot A`'s Wi-Fi interface is counted once through that physical interface.

### AC-02: RX + TX
While connected to the target hotspot, both upload and download bytes increase total usage.

### AC-03: Decimal units
`4,500,000,000 bytes` is calculated as `4.50 GB`, and the menu bar renders it as `4.50GB` using the specified half-up rounding and fixed suffix.

### AC-04: Menu bar simplicity
During normal operation the menu bar item shows only a value such as `3.72GB`.

### AC-05: 50% state
With a 4.50 GB limit, reaching 2.25 GB activates the 50% visual state.

### AC-06: 80% state
With a 4.50 GB limit, reaching 3.60 GB activates the 80% visual state.

### AC-07: 90% state
With a 4.50 GB limit, reaching 4.05 GB activates the 90% visual state.

### AC-08: Limit enforcement
In a strong-blocking build, for an eligible and authorized profile with a 4.50 GB limit, the first valid sample that brings usage to or above 4.50 GB initiates a disconnect attempt without waiting for another scheduled sample. The attempt is made only after exact target-identity verification; a measurement-only or otherwise ineligible profile performs no disconnect or preference mutation.

### AC-09: Reconnection enforcement
After the limit is reached, reconnecting to the target hotspot before reset causes another blocking attempt only when the profile remains eligible, authorized, unpaused, and the build supports strong blocking. Otherwise HBF measures when resolution is valid and reports `Blocking Not Guaranteed` without a network action.

### AC-10: Other networks remain usable
Blocking the monitored hotspot does not disable Wi-Fi globally or disconnect an unrelated Wi-Fi network, and this behavior is proven in the strong-blocking release gate.

### AC-11: Pause Blocking
When Pause Blocking is enabled for an eligible profile, target-hotspot traffic continues to be measured but automatic disconnection and preference enforcement do not occur. A measurement-only profile has no blocking capability to pause and remains visibly `Blocking Not Guaranteed`.

### AC-12: Usage beyond limit
With Pause Blocking enabled for an eligible profile, usage can display values greater than the configured limit without resetting or stopping measurement. A profile that is measurement-only may also exceed its limit, but HBF must not imply that Pause Blocking caused or prevented enforcement.

### AC-13: Pause expires at reset
At the next reset cycle, Pause Blocking automatically returns to off.

### AC-14: Default reset
With reset day 1, a new cycle begins at local 00:00 on the first day of each month.

### AC-15: Day 31 fallback
With reset day 31, April resets on April 30 at 00:00 and May resets on May 31 at 00:00.

### AC-16: February fallback
With reset day 30 or 31, February resets on February 28 in a common year and February 29 in a leap year.

### AC-17: No unnecessary fallback
With reset day 27, every month resets on the 27th.

### AC-18: Sleeping through reset
If the Mac sleeps across the effective reset time, the first relevant operation after wake recognizes the new cycle and resets state before adding new traffic.

### AC-19: Persistence
Restarting the application or rebooting the Mac preserves the last safely persisted usage and current cycle. Any measured interval not yet persisted within the healthy nominal 5-second sample/flush cadence is excluded after relaunch, marked as a gap, and is not presented as recovered usage. The 10 MB trigger applies only to newly measured bytes and does not bound physical traffic that was not observed before the lifecycle boundary. Any transition that replaces more than one persistence file must be preceded by a flushed `CommitJournalV1` and must enter `Recovery Required` after a non-complete, digest-mismatched, or unexplained cross-file cut point; HBF must not select a lower or merely newer copy automatically.

### AC-20: Quit warning
User-initiated Quit warns that usage while the application is closed cannot be measured or recovered.

### AC-21: Blocking failure warning
If HBF attempts strong blocking for an eligible, authorized profile after the limit is reached and cannot disconnect the target hotspot or verify the result, it warns that continued use may incur additional charges and shows persistent `Blocking Failed`. A measurement-only or unauthorized profile shows `Blocking Not Guaranteed` instead of `Blocking Failed`.

### AC-22: Notification mute independence
Muting blocking-failure notifications does not stop blocking attempts or measurement.

### AC-23: Manual reset warning
Manual usage reset requires confirmation explicitly stating that carrier-side usage is unaffected.

### AC-24: Limit lowered below usage
If current usage is 3.80 GB and the limit is changed from 4.50 GB to 3.50 GB, the application immediately enters the limit-reached state.

### AC-25: Localization
All normal UI, warnings, dialogs, and notifications are available in Korean and English.

### AC-26: Independent profiles
If profile A reaches its limit, profile B remains measurable and usable according to profile B's own state. If their interface-and-SSID pair is shared, neither profile receives a strong-blocking promise or HBF-owned preference mutation, but validly resolved measurement remains independent.

### AC-27: Profile activation
A new profile remains inactive until its alias, network identity, limit, and reset day are complete; once complete, it starts at 0 bytes in the current cycle. Administrator authorization is requested separately only when the completed profile is eligible for strong blocking, and denial leaves the profile visibly unprotected without preventing valid measurement or prompting again automatically.

### AC-28: Unknown network
Traffic on a network that does not match a registered profile does not increase any profile's usage and does not trigger blocking.

### AC-29: Unique profile matching
When exactly one registered profile matches the current SSID, interface, and confirmed BSSID, that profile becomes active automatically.

### AC-30: Ambiguous profile matching
When the current interface and SSID match no profile, the network is `Unknown Network` and HBF does not measure or block until the user creates a profile or leaves it unmanaged. When exactly one profile has the interface-and-SSID pair but a new BSSID is observed, HBF shows `Needs BSSID Confirmation` and requires an explicit append confirmation. When multiple profiles have the pair and a new BSSID is observed, the user must choose one candidate and confirm the append. A selected disconnected profile remains available for management and does not resolve an unknown or ambiguous connection or cause automatic reconnection.

### AC-31: BSSID re-confirmation
When a confirmed profile connects with a new BSSID, no traffic is added until the user confirms it; confirmation adds the BSSID to that profile's confirmed set.

### AC-32: Network identity immutability
Changing an existing profile's SSID or interface, or silently replacing/removing a confirmed BSSID, is not allowed. An explicit BSSID reconfirmation may append a new BSSID; monitoring another SIM or hotspot requires a new profile.

### AC-33: Profile deletion
Deleting a profile requires that it be disconnected, have no pending enforcement or preference transaction, the exact alias be entered, and an irreversible confirmation be accepted. The active store, last-known-good copy, profile transactions, and all profile-scoped events are purged. A global deletion audit event may remain without the deleted profile identifier, and a tombstone prevents recovery from resurrecting the profile.

### AC-34: Interface-only measurement
When the target Wi-Fi interface and another interface are active together, only the target Wi-Fi interface's RX/TX counters increase the active profile's usage.

### AC-35: Measurement gap
Traffic generated while HBF is closed, asleep, disconnected from the measurement interface, recovering from a counter failure, or between samples that straddle a reset boundary is not added after the next baseline is established.

### AC-36: Sampling boundary
While the Mac is awake, the connected profile's counters are sampled on a nominal 5-second cadence, actual sample times are recorded, and missed samples are not fabricated. The reset cycle is evaluated before each valid delta and the limit after it. The UI/help text discloses possible overrun before detection.

### AC-37: Persistence cadence
Measured usage is durably persisted after every successful awake measurement transition on the nominal 5-second cadence. When a valid sample observes at least 10 MB of newly measured traffic since the previous durable snapshot, that transition is persisted immediately. The 10 MB trigger applies only to observed deltas, not to unobserved physical traffic, and lifecycle and state transitions are persisted immediately.

### AC-38: Persisted-state failure
If an existing profile's persisted state is corrupt, missing, or unreadable, or if `CommitJournalV1` is incomplete, required but missing, mismatched, or reveals an unexplained multi-file transition, HBF does not replace it with zero usage, stops measuring and blocking, preserves all candidate files, displays persistent `Recovery Required`, and offers explicit recovery choices. It does not guess which current network to disconnect, select a lower or merely newer copy automatically, or perform another network action while recovery is unresolved.

### AC-39: Blocking authorization
Enabling blocking for an eligible profile requests administrator authorization before enforcement begins; if authorization is denied or unavailable, measurement continues but the profile visibly reports `Blocking Not Guaranteed`, no automatic authorization prompt is retried, and the user has an explicit action to try authorization again. Authorization availability is process-local: a persisted prior success cannot authorize a later process, and after relaunch HBF may only attempt a non-interactive check before requiring another explicit user action. Replaying the same idempotency key returns the durable historical command result without a second prompt or side effect, but the current response separately reports `authorizationRequired` when no usable authorization exists.

### AC-40: Profile-specific blocking
Blocking eligible profile A must not intentionally disable or disconnect profile B or unrelated Wi-Fi networks. A shared interface-and-SSID pair is never strong-blocking eligible, so HBF makes no preference change that could affect both profiles. Because `disassociate()` acts on the interface's current network without an atomic target guard, the exact candidate and release gates must prove the residual target-switch boundary for every supported build before HBF can claim this protection; until then the profile remains `Blocking Not Guaranteed`.

### AC-41: Blocking retry and restoration
After a failed blocking attempt for an eligible authorized profile, HBF retries after 5 seconds, 15 seconds, 30 seconds, 1 minute, and then every 5 minutes while the exact target remains connected. It restores only its own temporary Wi-Fi preference changes when enforcement ends, observes the full 30-second awake restoration window, detects restoration conflicts without overwriting user changes, marks incomplete observation `Unverified`, and never automatically reconnects the hotspot.

### AC-42: Notification fallback
If notification permission is denied or an alert cannot be displayed, the menu and settings interface continue to show the blocking-failure state and provide permission guidance.

### AC-43: Notification deduplication
A successful limit notification is sent once per profile and cycle; blocking-failure notifications may recur only when the failure state begins or a temporary mute expires, with no more than one failure notification per five-minute retry interval, and never stop enforcement.

### AC-44: Reset-day change
Changing a profile's reset day requires confirmation; cancelling preserves the old setting, while confirming a setting whose effective cycle differs from the current trusted cycle resets that profile immediately. If the effective cycle does not change, usage and cycle state are preserved, a new baseline is required, and the change is recorded.

### AC-45: Limit increase confirmation
Cancelling a limit increase preserves the old limit and state. Confirming an increase clears limit-reached only when usage is below the new limit and does not automatically reconnect the hotspot.

### AC-46: Manual reset scope
Manual reset sets only the selected profile's local usage to zero, establishes a new baseline, reevaluates the limit, stops retry enforcement when the limit clears, and restores only HBF-owned preference changes for an eligible profile with ownership checks. It does not change its cycle, Pause Blocking, notification suppression state, or actual Wi-Fi connection, and it never reconnects a disconnected hotspot.

### AC-47: Quit cleanup
Before a confirmed voluntary quit, HBF restores its own temporary Wi-Fi preference changes, completes the read-back and observation checks, and warns that usage and blocking cannot be guaranteed while the application is closed. If restoration is pending, failed, or unverified, HBF does not claim cleanup is complete and offers retry; Force Quit follows the recovery path.

### AC-48: Display and setup state
The menu bar displays the exact active profile's usage as a two-decimal, half-up-rounded decimal-GB value with no space before `GB` during normal operation, and `—` when no connected profile is resolved, the current network is unregistered, identity is ambiguous, permission is missing, measurement is unavailable, recovery is required, or multiple target profiles are connected. It never presents an unmeasured network as 0 usage.

### AC-49: Profile-local cycle
Each profile can use a different reset day and its own cycle state; profile A's reset does not reset profile B.

### AC-50: Time and sleep transitions
After sleep, a system time-zone identifier change, a wall-clock movement backward, a divergence greater than 60 seconds from monotonic elapsed time, or multiple missed reset boundaries, HBF evaluates the current profile cycle before adding traffic and does not duplicate or import gap usage. A forward jump advances directly to the current cycle; a backward or otherwise uncertain change never rolls back usage and requires explicit acknowledgement in a persistent `Time Adjustment Required` state. While that state is unresolved, HBF performs no measurement, enforcement, suppression, disconnect, or new preference write. It may perform only an ownership-proven restoration of an already open HBF preference transaction under the normal archive, fingerprint, authorization, read-back, and persistence guards; if those guards fail, the current system value remains unchanged and the restoration result remains pending, conflicted, or unverified.

### AC-51: Local diagnostics
The event history retains the current cycle and preceding 90 days, contains no packet contents or URLs, and sends no remote diagnostic telemetry.

### AC-52: Language and launch settings
The user can choose System Default, Korean, or English; automatic login launch is enabled by default after setup and can be disabled. The UI shows whether login launch is approved, awaiting approval, disabled, or failed.

### AC-53: VPN traffic accounting
When VPN traffic is transported through the monitored Wi-Fi interface, its underlying RX/TX bytes are included once in the profile's usage. HBF does not separately add the VPN or virtual interface counters.

### AC-54: Blocking target revalidation
If the current SSID, interface, or BSSID changes between profile matching and a blocking action, HBF does not disconnect or modify the network and records a local revalidation failure. A disconnect attempt is successful only after a follow-up query confirms that the exact target is no longer connected; an API call returning without an error is insufficient.

### AC-55: Preference ownership conflict
If the current automatic-connection preference differs from the last value written by HBF when restoration is due, HBF leaves the current value unchanged, records a restoration conflict, and shows a persistent warning.

### AC-56: Reset-boundary delta
If two trusted samples fall on opposite sides of an effective reset boundary, HBF discards the interval delta, applies the new cycle state, and establishes a new baseline instead of assigning pre-reset traffic to the new cycle.

### AC-57: Clock rollback
If a backward wall-clock movement is detected, or a time-zone/clock change calculates a cycle earlier than the persisted trusted cycle, HBF preserves the trusted state, does not restore older usage, pauses measurement and blocking, and requires explicit user acknowledgement before resuming either.

### AC-58: Limit precision and validation
`0.01 GB` is stored as exactly `10,000,000` bytes, `1,000 GB` is accepted as exactly `1,000,000,000,000` bytes, and malformed, grouping-separator, unsupported-decimal-separator, fractional-step, out-of-range, signed, exponent, non-finite, or overflowing limit input is rejected without changing the saved limit.

### AC-59: Offline manual reset
If a selected profile is disconnected when manual reset is confirmed, HBF resets its saved usage, marks a baseline pending, and does not add traffic until the next exact profile connection establishes that baseline.

### AC-60: Notification mute expiry
The 10-minute and 1-hour suppression states expire according to their persisted wall-clock expiry times, including after sleep, while cycle-scoped suppression clears only when the persisted cycle identity changes.

### AC-61: Resuming blocking
When Pause Blocking is turned off for a selected profile whose usage is already at or above its limit, HBF resumes blocking immediately only if the profile is strong-blocking eligible, authorized, covered by a strong-blocking build, and the exact target is connected. It does not automatically reconnect a disconnected hotspot; an ineligible profile remains `Blocking Not Guaranteed`.

### AC-62: Profile alias and identity validation
Profile aliases are normalized to trimmed Unicode NFC and duplicate normalized aliases are rejected. A completed profile or BSSID append that would duplicate another profile's complete interface/SSID/BSSID identity is rejected without changing either existing profile.

### AC-63: Blocking release gate outcome
The GitHub validation candidate may exercise blocking only inside the explicit operator-only gate workflow and never reports `Strong Blocking Ready`. Every destructive case requires a matching process-local `OperatorValidationContextV1` containing the run id, exact candidate digest set, gate/case identifier, and fresh confirmation; missing, stale, or mismatched context rejects the action and cannot be reconstructed from persisted state, a mutable report, or a user preference. If its real-Mac strong-blocking release gate fails while the identity and 64-bit counter capability gates pass, the project may distribute only a separately built artifact whose immutable mode is `measurementOnly`; that artifact performs no blocking action or HBF-owned preference mutation, and every completed profile visibly reports `Blocking Not Guaranteed`. If the identity or counter capability gate fails, HBF does not claim measurement-only operation; v1 is postponed or the artifact is diagnostic-only. A passing release report is valid only for the exact unchanged GitHub candidate artifact, app-bundle digest, executable digest, and asset digest recorded by the gate.

### AC-64: Preference restoration observation
After HBF restores a temporary Wi-Fi preference, it verifies the complete configuration by read-back and records that transaction result separately from the full 30-second awake network-observation result. A target reconnection is recorded as an observed macOS or unclassified association and does not invalidate a configuration restoration whose read-back succeeded. If the observation window cannot complete, the configuration may remain `Restored`, but the observation is `Unverified` and HBF does not claim complete post-restoration observation.

### AC-65: Shared interface-and-SSID capability boundary
Completing or appending a profile that shares a canonical interface name and SSID bytes with another completed profile requires an explicit warning and confirmation. Every affected profile remains measurable when its exact BSSID is resolved but reports `Blocking Not Guaranteed`; HBF never calls `disassociate()` or mutates automatic-connection preferences for either profile, and an existing strong-blocking profile is never silently downgraded.

### AC-66: Multiple resolved target profiles
If two or more completed profiles are simultaneously resolved across different Wi-Fi interfaces, HBF enters the application-global `Multiple Profiles Connected` safety state, displays `—` for the affected target set, and performs no measurement or blocking for those profiles until only one target profile remains resolved. Profile management and settings remain available, and an unrelated unregistered network on another interface does not trigger this state.

### AC-67: Identity permission boundary
If Location Services authorization is denied, restricted, revoked, or unavailable when SSID/BSSID identity is needed, HBF shows `Location Permission Required`, does not save an incomplete profile or guess a match, and pauses identity-dependent measurement and blocking. It provides system-settings guidance, does not store geographic coordinates, and permits documented manual identity entry where the user can supply the required bytes and canonical values; manual entry does not bypass the runtime permission boundary for later identity resolution.

### AC-68: Counter source and width
The v1 counter adapter retrieves interface counters through `sysctl(CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0)`, parses `if_msghdr2.ifm_data` as `if_data64`, returns checked `UInt64` RX/TX values, and rejects parse, overflow, or interface-index mismatch. It validates a common prefix containing `ifm_msglen` and `ifm_type` for every mixed record, skips shorter non-target records only after those bounds pass, and requires the full SDK-derived `if_msghdr2` header and `if_data64` region for `RTM_IFINFO2`. It uses bounds-checked byte copies for fields and accepts exactly one non-truncated matching record whose interface name and index agree. Missing, duplicate, zero-length, unknown-layout, truncated, or unaligned input rejects the sample. A transient counter or interface failure shows `Measurement Unavailable` and establishes a new baseline after recovery. A `getifaddrs()` path based on 32-bit `struct if_data` is not accepted as the v1 source, and the exact GitHub candidate artifact that cannot use the selected path enters global `Recovery Required` rather than claiming exact measurement or downgrading to measurement-only.

### AC-69: Compositional profile state
The UI exposes measurement/connection state separately from protection state. Selecting a disconnected profile permits management actions without making it connected, measurable, or automatically reconnected; a currently enforced profile continues to be evaluated even when another profile is selected in the UI.

### AC-70: Preference transaction safety
Before every HBF-owned Wi-Fi preference write, a flushed `Prepared` transaction contains reversible original and intended public-configuration snapshots, their fingerprints, and the fingerprint algorithm/schema version. The transaction becomes `Applied` only after write and read-back success. Restoration writes only when the current value still equals HBF's last written value; otherwise HBF leaves the value unchanged and shows persistent `Restoration Conflict`. An uncertain write, read-back, or archive decode makes the transaction `Unverified` and is not silently retried with a new value; a fingerprint without a reversible snapshot is insufficient for a restoration transaction. An interrupted post-restoration network observation changes only the separate observation result to `Unverified` when the configuration read-back already proved restoration.

### AC-71: Time-adjustment acknowledgement
After a backward or otherwise uncertain time adjustment, acknowledging the state accepts the current time zone and wall clock, preserves trusted usage unless a forward cycle transition is required, marks the measurement baseline pending, records the acknowledgement, and never imports the uncertain interval or restores older usage.

### AC-72: Release-mode traceability
The non-sandboxed GitHub release artifact and release record identify whether it is a validation candidate, strong-blocking build, or measurement-only build, together with the exact supported macOS build list, architecture, actual code-signature/Hardened Runtime/notarization status, source revision, GitHub asset SHA-256, tested app-bundle SHA-256 and executable SHA-256, with canonical post-signing values when local signing is part of the tested path, and applicable real-Mac proof reports. A mutable local store cannot promote the artifact's capability mode. A strong-blocking claim is absent unless all required gates pass for every supported OS build and the distributed artifact is byte-identical to the tested candidate. A counter capability failure prevents a measurement-capable release; measurement-only mode is permitted only for a separately built immutable `measurementOnly` artifact when the identity and counter gates pass and only the strong-blocking gate fails.

### AC-73: Blocking reconnection observation
After a strong-blocking preference write is accepted and read back and the exact target is disconnected or confirmed absent, HBF observes the target for the full 30-second awake suppression window. A valid one-shot manual-reconnection intent for the exact profile and interface is the only positive evidence that a reconnection during this suppression window was user-initiated. A reconnection without that token fails the blocking result or remains `Unverified`, starts the documented retry or recovery contract, and is never classified from the absence of an HBF association call. If the window cannot complete, the result is `Unverified` and HBF does not claim automatic reconnection suppression. This intent classification does not apply after enforcement ends and the original preference has been restored.

### AC-74: Lossless preference recovery
HBF does not enter strong blocking unless the selected macOS public configuration can be serialized, decoded, compared, and replayed losslessly for the target interface. After a crash or restart with an open preference transaction, HBF restores the archived original configuration only when the current configuration still matches the last HBF-written fingerprint; if the archive or comparison is unavailable, it leaves the current value unchanged and reports `Unverified` or `Restoration Conflict`.

### AC-75: Preference mutation scope
In target-present, target-absent, duplicate-security-profile, and unrelated-preference cases, HBF's intended configuration removes only preferred-network entries whose raw SSID bytes equal the target SSID, preserves their remaining order and every other public configuration value, and restores the exact original public configuration. If that scope cannot be represented or round-tripped losslessly, HBF performs no preference write and reports `Blocking Not Guaranteed`.

### AC-76: Arithmetic overflow safety
If adding a valid counter delta to accumulated usage or converting usage to the required decimal presentation would overflow, HBF preserves the last safe persisted state, never wraps, saturates, or silently resets the value, stops measurement and blocking, records the failure, and shows `Recovery Required`.

### AC-77: Persistence failure and migration safety
If a required durable write or flush fails, HBF stops adding usage and stops blocking, preserves the last-known-good store, records the failure, and shows `Recovery Required`; it does not recreate the profile with zero usage. A schema migration must complete and validate before resuming, an installation marker is repaired only after a valid completed store is verified, and an unknown schema, failed migration, non-complete or required-but-missing journal, or unexplained cross-file cut point remains in recovery.

### AC-78: Lifecycle clock boundaries
Sleep/wake, application restart, logout/login, and reboot close the preceding sampling interval and never import its lifecycle gap or compare monotonic timestamps across processes. A current earlier wall clock or changed time-zone cycle enters `Time Adjustment Required`; a forward transition advances or resets the cycle exactly once, discards the gap, and establishes a new baseline.

### AC-79: Eligibility and build-mode transitions
If authorization, profile eligibility, or the build mode changes while an HBF-owned preference transaction is open, HBF reconciles the transaction before applying the new mode and restores the original value when ownership can be proven. If ownership or restoration is uncertain, it leaves the current system value untouched and records `Conflict` or `Unverified`; measurement-only mode creates no new preference transaction.

### AC-80: Manual identity grammar
Manual identity registration accepts an SSID of 1–32 raw octets represented as even-length hex with no separators, a nonempty canonical BSD interface name, and a lowercase-normalized six-octet colon-separated BSSID; malformed, odd-length, separated, or out-of-range values are rejected without saving a partial profile. Later SSID/BSSID resolution still requires the runtime permission described in Section 17.

### AC-81: State scope and counter-gate precedence
`Recovery Required` and `Time Adjustment Required` are global states, `Multiple Profiles Connected` is an application-global safety state whose effect is limited to the current multi-interface target resolution, and `Measurement Unavailable` is local to the affected target interface/profile. A deterministic counter-capability failure in the exact GitHub candidate artifact always takes global precedence over measurement-only mode, while an isolated profile-local blocking failure does not stop unrelated valid profiles from measuring.

---

## 21. Initial Project Identity

Recommended initial identifiers:

- Product display name: `Hotspot Byte Fence`
- Project/directory name: `HotspotByteFence`
- Short name: `HBF`
- Bundle identifier: `com.copylawbot.hotspotbytefence`

The v1 bundle identifier is resolved as `com.copylawbot.hotspotbytefence`; it is not a remaining implementation or release input.

The v1 implementation and distribution baseline is an `arm64` application with a macOS 13.0 deployment floor. The compatibility validation target is macOS 13.0 or later on `arm64`, covering Ventura 13, Sonoma 14, Sequoia 15, and Tahoe 26. This target range is not itself a support claim: only exact macOS build rows listed in the support matrix receive support status after the applicable gates pass. Universal `arm64`/`x86_64` distribution is outside v1 unless the same counter, CoreWLAN, blocking, and restoration proof is repeated for `x86_64`. The v1 distribution target is a directly distributed GitHub Copy App. The published package is an unsigned ZIP containing the `.app` and a `SHA-256SUMS` manifest. Before supported use, the user must locally ad hoc-sign the extracted `.app`; this is an installation prerequisite for the supported path, not Developer ID signing or notarization. The release package must include the exact unsigned asset SHA-256, the canonical local signing instructions, and first-launch/Gatekeeper instructions. The unsigned asset digest must be verified before signing; the locally signed app is a derived artifact and must not silently inherit exact-candidate evidence from the unsigned package. When the signed app is tested, its post-signing app-bundle digest (`hbf-app-bundle-v1-sha256`) and executable digest are recorded separately. Mac App Store distribution is not a v1 requirement.

Apple documents `Copy App` as a macOS distribution option that does not require code signing, while its standard outside-App-Store workflow separately recommends notarization. HBF intentionally selects the Copy App path for GitHub distribution, so a user may encounter quarantine or Gatekeeper approval at first launch. That user-visible outcome is a release-evidence field and must be covered by the published launch instructions; it is not silently treated as a trusted signed distribution.

The resolved v1 bundle identifier is `com.copylawbot.hotspotbytefence`. A development team, Developer ID identity, and notarization account are not release prerequisites for the GitHub path and do not change product behavior.

The distributed v1 build must be a non-sandboxed GitHub artifact, use only public APIs, carry `NSLocationUsageDescription` with Korean and English purpose strings, and pass the candidate counter and CoreWLAN capability checks. The published GitHub asset is unsigned, and supported user setup requires a local ad hoc signature before first launch. Developer ID signing, notarization, and Hardened Runtime are not distribution prerequisites. The release record must state whether the published or tested artifact is unsigned, ad hoc signed, or Developer ID signed, and whether Hardened Runtime and notarization are actually present. It must record the unsigned asset digest separately from the post-signing app-bundle digest and executable digest; the app-bundle value uses `hbf-app-bundle-v1-sha256`, and a locally signed derived app does not inherit exact-candidate gate evidence unless that exact signed artifact is the one tested. An unsigned artifact must not claim absent signature/runtime properties or entitlement-backed behavior. `SMAppService` login launch is available only after the app is signed and the user approves the login item; otherwise the application must disclose the gap and remain usable while open when possible. The application must request administrator authorization explicitly and only when a strong-blocking configuration write is required, keep the authorization object in memory only, and invalidate it when no longer needed. The application stores private state under its application-support directory with owner-only file permissions and does not install a privileged helper or daemon. If the counter or identity capability fails under this posture, the project must postpone a measurement-capable v1 release; if those capabilities pass but the strong-blocking behavior fails, the project may produce a separately built artifact with immutable `measurementOnly` mode. It must not weaken the safety promise through an undocumented entitlement or private API.

The initial exact validation matrix is deliberately narrower than the macOS 13.0 compatibility validation target:

| macOS version | Build | Architecture | Validation status | Permitted claim |
|---|---|---|---|---|
| 26.6.2 | 25G83 | `arm64` | GitHub-candidate feasibility, identity, counter, and strong-blocking gates pending | No distributed measurement or strong-blocking support until the applicable gates pass |

The compatibility target families awaiting exact build rows are:

| macOS family | Architecture | Target status |
|---|---|---|
| Ventura 13 | `arm64` | Exact build row and applicable gates pending |
| Sonoma 14 | `arm64` | Exact build row and applicable gates pending |
| Sequoia 15 | `arm64` | Exact build row and applicable gates pending |
| Tahoe 26 | `arm64` | Exact build row and applicable gates pending |

Before release, update the exact support matrix with each selected build's candidate version, source revision, GitHub release asset SHA-256, post-signing app-bundle and executable SHA-256 values when applicable, actual code-signature/Hardened Runtime/notarization status, Gatekeeper/quarantine result, and each gate verdict rather than relying only on `macOS 13 or later`. Every additional macOS build or architecture requires its own applicable capability and strong-blocking release proof before it receives a support claim. A build absent from the matrix must not receive a measurement or strong-blocking claim. Updating the development machine or its OS does not silently replace an existing entry; it creates a new pending entry. A supported measurement-only row may be recorded when identity and counter capability pass but the strong-blocking gate fails; strong-blocking remains unavailable for that row.

---

## 22. Implementation Guidance

This PRD specifies required behavior and fixes the v1 technical baseline below. An alternative API or implementation is acceptable only after it demonstrates the same observable behavior, permission boundaries, 64-bit counter guarantees, and real-Mac proof, and the implementation record is updated.

### 22.1 Technical baseline

The v1 implementation must use the following public system boundaries:

- Wi-Fi identity and link state: obtain interface objects through the app-provided `CWWiFiClient`, and resolve the current interface name, SSID bytes, BSSID, and service state. SSID/BSSID access must honor the Location Services state in Section 17. In Swift, use the current SDK mappings such as `ssidData()`, `bssid()`, and `CWConfiguration()` rather than copying Objective-C convenience-factory names verbatim. Do not use a display name as the identity key.
- Interface counters: use `sysctl(CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0)` and parse [`if_msghdr2.ifm_data`](https://developer.apple.com/documentation/kernel/if_msghdr2/1563988-ifm_data) as [`if_data64`](https://developer.apple.com/documentation/kernel/if_data64); expose checked `UInt64` RX/TX values to the measurement domain. The v1 adapter must not fall back to 32-bit `struct if_data` counters. The exact GitHub candidate artifact must pass the counter probe before this path is treated as measurement-capable; the result is independent of whether the artifact is unsigned or ad hoc signed.
- Target disconnect: use the public current-interface disconnect operation represented by `CWInterface.disassociate()`, after exact interface/SSID/BSSID revalidation and with the administrator authorization behavior specified in Section 7.3. Because the Swift operation has no authorization parameter or success result, authorization availability and post-action state must be verified separately; a returned API call is not proof of disconnection.
- Automatic reconnection suppression: use only the public preferred-network configuration model represented by `CWConfiguration.networkProfiles` and `commitConfiguration`. The v1 intended configuration removes all preferred-network entries with the target SSID bytes while preserving order and every other public configuration value. This model is scoped to the interface/SSID preference boundary, not a BSSID-specific block list; therefore shared interface-and-SSID profiles are measurement-only.
- Preference safety: apply the `Prepared`/`Applied`/restoration transaction contract in Section 10.1. Persist a reversible original and intended configuration representation, not only fingerprints. No write may occur without a flushed transaction and no restoration may overwrite a value changed after HBF's write.
- Lifecycle and UI: use the system lifecycle and sleep/wake notifications, SwiftUI `MenuBarExtra`/`Settings`, `SMAppService` for login launch on macOS 13+ after the required local ad hoc signing and user approval, `UNUserNotificationCenter` for notifications, and String Catalogs for localized strings. Each selected API must be verified in the exact GitHub candidate artifact, with its actual unsigned, ad hoc-signed, or Developer ID-signed posture recorded.

The technical design must not depend on private framework symbols, undocumented BSSID-specific preference controls, or an API return value without post-action observation.

The technical design must explicitly record the GitHub-candidate feasibility result for each selected macOS build, the exact Swift API mappings used by the implementation, the preference mutation and lossless restoration algorithm, the counter/usage overflow behavior, the startup and sleep clock rules, and the user-intent rule used to classify reconnections. “Manual reconnection” must not be defined solely by the absence of an HBF association call.

During technical design, verify the current macOS APIs and permissions for:

- determining the active Wi-Fi network
- measuring interface RX/TX bytes reliably
- disconnecting only the target Wi-Fi network
- detecting network changes
- sleep/wake handling
- login launch
- user notifications and notification actions
- persistence
- menu bar presentation
- localization

For Wi-Fi discovery and events, use the [CoreWLAN](https://developer.apple.com/documentation/CoreWLAN) interfaces provided by `CWWiFiClient`, including SSID, BSSID, interface, and link-change events. [`CWInterface.disassociate()`](https://developer.apple.com/documentation/corewlan/cwinterface/disassociate%28%29) operates on the current network and may require administrator authorization. Changing the preferred network configuration through [`commitConfiguration`](https://developer.apple.com/documentation/corewlan/cwinterface/commitconfiguration%28_%3Aauthorization%3A%29) requires root or administrator authorization. The technical design must validate the temporary preference-change and restoration flow on every supported macOS version before treating it as strong blocking.

For the menu bar and settings, evaluate SwiftUI [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra) and [`Settings`](https://developer.apple.com/documentation/swiftui/settings). For login launch, evaluate [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice) on macOS 13 or later. For notifications, use `UNUserNotificationCenter` and handle denied authorization with the persistent in-app state required above. Use [String Catalogs](https://developer.apple.com/documentation/Xcode/localizing-and-varying-text-with-a-string-catalog) for all Korean and English strings.

The measurement implementation must use a 64-bit or equivalently wrap-safe interface counter source and must be testable with injected clock, Wi-Fi state, counter, persistence, disconnector, and notification components.

### 22.2 Required design artifacts

The technical design must include:

- a state-transition table for connected, selected, enforced, paused, failed, recovery, and time-adjustment states;
- a persistence schema with versioning, migration and installation-marker rules, last-known-good recovery behavior, deletion-tombstone behavior, reversible preference snapshots, transaction ordering for HBF-owned Wi-Fi preference changes, and the maximum unpersisted measurement interval;
- a permission and privilege-boundary matrix covering the non-sandboxed distribution posture, CoreWLAN operations, administrator authorization, login launch, local storage permissions, and notifications;
- the exact `CWConfigurationArchiveV1` schema, canonical fingerprint serializer, replay/equality oracle, `WiFiObservationV1` source-quality contract, and immutable `BuildManifestV1`/external `ReleaseManifestV1` binding rules;
- an explicit support matrix and GitHub-candidate feasibility report for every supported macOS build;
- the real-Mac operator runbook defining test topology, destructive-action confirmation, abort conditions, evidence paths, and redaction rules;
- a blocking proof report from a real Mac that records the exact target identity, post-disconnect verification, reconnection classification, restoration conflicts, preference snapshots/fingerprints, and the behavior of unrelated Wi-Fi networks.

The canonical v1 technical design is [`HotspotByteFence_TechnicalDesign.md`](HotspotByteFence_TechnicalDesign.md). The environment snapshot, current proof status, pending GitHub-candidate cases, and release support matrix are maintained in [`HotspotByteFence_CapabilityGates.md`](HotspotByteFence_CapabilityGates.md). A `PENDING` gate in that record is not implementation or release evidence.

The complete state-transition and command contract is maintained in [`HotspotByteFence_StateModel.md`](HotspotByteFence_StateModel.md). The concrete persistence schema and recovery contract is maintained in [`HotspotByteFence_PersistenceSchema.md`](HotspotByteFence_PersistenceSchema.md). The AC-to-test/gate traceability matrix is maintained in [`HotspotByteFence_VerificationTraceability.md`](HotspotByteFence_VerificationTraceability.md). Product and release inputs that cannot be inferred from this document are tracked in [`HotspotByteFence_DecisionsNeeded.md`](HotspotByteFence_DecisionsNeeded.md).

The state machine must keep these dimensions separate:

| Dimension | Required states | Key rule |
|---|---|---|
| Measurement/connection | `Monitoring`, `Disconnected`, `Unknown Network`, `Needs BSSID Confirmation`, `Multiple Profiles Connected`, `Location Permission Required`, `Measurement Unavailable`, `Recovery Required`, `Time Adjustment Required` | Only one exactly resolved completed profile may accumulate usage. |
| Selection | no selected profile, selected disconnected profile, selected connected profile | Selection changes management context only; it never resolves, measures, blocks, or reconnects a network. |
| Protection | `Strong Blocking Ready`, `Limit Reached`, `Blocking Failed`, `Blocking Paused`, `Blocking Not Guaranteed`, `Restoration Conflict` | Protection is strong only for an eligible, authorized profile in a strong-blocking build. |
| Preference transaction | `Prepared`, `Applied`, `RestorationPending`, `Restored`, `Conflict`, `Unverified` | Every write is persisted before application and verified after application/restoration. |
| Post-restoration observation | `Pending`, `Verified`, `Unverified` | Link observation is recorded separately and cannot reverse a configuration restoration already proven by read-back. |

The minimum permission matrix is:

| Capability | Required condition | Denied or failed behavior |
|---|---|---|
| SSID/BSSID identity | Location Services authorization when macOS requires it | `Location Permission Required`; no guessed match or incomplete automatic setup |
| 64-bit RX/TX counters | Selected sysctl path works in the exact non-sandboxed GitHub candidate artifact | Transient failure: `Measurement Unavailable`; deterministic candidate-capability failure: global `Recovery Required`; no measurement-only claim |
| Target disconnect | Administrator authorization, exact target revalidation, and independent post-action observation | Continue measurement when possible; `Blocking Not Guaranteed` and no automatic authorization retry |
| Preferred-network mutation | Administrator authorization, eligible unique interface/SSID profile, lossless public configuration round-trip, and strong-blocking build | No preference write; measurement may continue with `Blocking Not Guaranteed` |
| Login launch | Locally ad hoc-signed app, `SMAppService` registration, and user approval | If signing or approval is unavailable, run only while open and disclose the measurement/blocking gap |
| User notifications | `UNUserNotificationCenter` authorization | Persistent in-app state and permission guidance remain available |
| Distribution posture | GitHub direct Copy App; unsigned package with mandatory user-side local ad hoc signing before supported use; App Sandbox disabled; public APIs only; actual signature/Hardened Runtime/notarization status recorded but not required; no privileged helper; owner-only application-support state; passing identity and counter capability gates | Measurement-only build only when identity and counter capability gates pass but strong blocking fails; otherwise release postponed |

The blocking proof report must record at least the application version, full commit or source revision, GitHub release tag, unsigned asset SHA-256, post-signing app-bundle digest using `hbf-app-bundle-v1-sha256` and executable digest when local signing is part of the tested path, architecture, exact macOS build, actual signature/Hardened Runtime/notarization status, Gatekeeper/quarantine result, permission outcomes, target interface/SSID/BSSID, disconnect result, post-disconnect query, preference mutation algorithm, reversible preference snapshots and fingerprints before/after, automatic-reconnection observation for the full 30-second awake window, reconnection intent classification, unrelated Wi-Fi result, restoration result, and any `Conflict`/`Unverified` state. A report that only exercises a mock disconnector, an artifact different from the exact tested release path, or an unobservable user-action assumption is not a strong-blocking release proof.

Do not assume a proposed API is suitable merely because it existed in an earlier macOS release. Validate behavior on the target macOS version before relying on it for safety-critical blocking.

### 22.3 Verification plan

Before implementation is accepted, declare the exact support matrix and verify the following on a real Mac running every selected supported macOS build. Include each selected build from the macOS 13+ arm64 compatibility target, including the current development build macOS 26.6.2 (25G83) when it remains in the support matrix, and repeat the applicable gate after any OS update:

- administrator authorization and denial during blocking setup
- automatic reconnection suppression for one profile without disabling another Wi-Fi network
- BSSID changes, ambiguous profile matches, and profile A/profile B switching across two SIMs
- shared interface-and-SSID profile creation warning, measurement-only behavior, and duplicate complete-tuple rejection
- two simultaneously resolved target profiles on different Wi-Fi interfaces entering `Multiple Profiles Connected`
- 5-second RX/TX sampling, 64-bit counter continuity, counter rebaselines, and excluded downtime traffic
- transient counter failure entering `Measurement Unavailable` and GitHub-candidate counter failure entering `Recovery Required`
- a counter capability failure in the exact GitHub candidate artifact is not represented as a measurement-only release
- usage accumulation and decimal presentation overflow enter `Recovery Required` without wrapping or saturation
- sleep/wake across reset boundaries, reset day changes, time-zone changes, and substantial clock changes
- application restart/reboot clock handling uses no cross-process monotonic comparison and never imports the lifecycle gap
- persistence across restart, logout/login, reboot, forced termination, and storage corruption recovery
- persistence write failure, schema migration failure, installation-marker repair, and deletion-tombstone recovery
- notification authorization denial, mute expiry, persistent in-app failure state, Korean/English UI, and Light/Dark Mode
- VPN traffic transported over the target Wi-Fi interface is counted once, while VPN/virtual interface counters are not separately added
- counter samples that cross a reset boundary discard the interval, and backward clock/time-zone changes enter the required recovery state
- selected disconnected profiles remain manageable, including enabling Pause Blocking before a manual reconnect
- blocking suppression observation and preference restoration observation each complete their full 30-second awake window
- preference restoration conflicts leave user changes untouched and remain visible
- target-present, target-absent, duplicate-security-profile, and unrelated-preference preservation cases round-trip safely
- during the strong-blocking suppression window, explicit manual-reconnection intent is the only positive evidence used to classify a user reconnection; after restoration, a reconnection is recorded without invalidating a verified configuration restoration
- candidate and release reports contain the immutable build-manifest and external release-manifest bindings defined by the verification contract

The PRD itself must be checked for requirement traceability: every acceptance criterion must map to a section above, and no removed single-target or multiple-quota assumption may remain in the document.

---

## 23. v1.0 Non-Goals

Unless required by implementation constraints, v1.0 does not need:

- carrier account/API integration
- iPhone-side cellular usage measurement
- synchronization between Macs
- historical charts or analytics
- cloud accounts
- automatic purchasing of additional data
- global Wi-Fi disabling
- iOS companion application
- carrier-side exact usage reconciliation or a guarantee that HBF's local count equals the carrier's billing meter
- remote diagnostic telemetry
- strong blocking for profiles that share a canonical interface-and-SSID pair
- simultaneous measurement or blocking of two or more resolved target profiles on different Wi-Fi interfaces
- distinguishing two SIMs or hotspot states that expose the same interface, SSID, and BSSID tuple
- Universal `x86_64` distribution without repeating the v1 counter and blocking proof
- any private or undocumented macOS API used solely to make a stronger blocking claim

These may be considered in later versions.
