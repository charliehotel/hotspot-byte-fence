# Hotspot Byte Fence (HBF) — State Model and Command Contract

**Version:** 0.3
**Date:** 2026-09-01  
**Normative source:** [`HotspotByteFence_PRD.md`](HotspotByteFence_PRD.md)  
**Implementation status:** Initial domain value types, profile resolution, measurement reducer, safety eligibility evaluator, and cycle calculation are implemented under `Sources/HotspotByteFenceCore`. The full runtime coordinator, command ledger, UI, and network side-effect paths remain pending.

This document closes the v1 state-transition gap identified in the review evidence under `.omo/evidence`. It is a required companion to [`HotspotByteFence_TechnicalDesign.md`](HotspotByteFence_TechnicalDesign.md) and [`HotspotByteFence_OperatorRunbook.md`](HotspotByteFence_OperatorRunbook.md). If this document and the PRD conflict, the PRD wins and this document must be corrected before implementation continues.

---

## 1. State Identifiers

Internal enum names use stable ASCII identifiers. User-facing labels are localized through String Catalogs and must not be used as persistence keys.

| Dimension | Persisted enum | User-facing label key | Scope | Blocking effect |
|---|---|---|---|---|
| Global safety | `normal` | `state.global.normal` | Application | No global stop |
| Global safety | `recoveryRequired` | `state.global.recoveryRequired` | Application | Stop measurement and every network action |
| Global safety | `timeAdjustmentRequired` | `state.global.timeAdjustmentRequired` | Application | Stop measurement, enforcement, suppression, disconnect, and new preference writes; ownership-proven cleanup restoration may run |
| Global safety | `multipleProfilesConnected` | `state.global.multipleProfilesConnected` | Application; effect limited to current resolution | Stop measurement and blocking for target profiles |
| Connection | `monitoring` | `state.connection.monitoring` | Connected profile | Measurement may run |
| Connection | `disconnected` | `state.connection.disconnected` | Selected or candidate profile | No measurement or blocking action |
| Connection | `unknownNetwork` | `state.connection.unknownNetwork` | Current interface | No measurement or blocking action |
| Connection | `needsBSSIDConfirmation` | `state.connection.needsBSSIDConfirmation` | Current interface/profile candidates | No measurement or blocking action |
| Connection | `locationPermissionRequired` | `state.connection.locationPermissionRequired` | Identity-dependent resolution | No identity-dependent measurement or blocking |
| Connection | `measurementUnavailable` | `state.connection.measurementUnavailable` | Affected target interface/profile | Add no delta, retry with new baseline |
| Selection | `none` | `state.selection.none` | UI | No profile management context |
| Selection | `selectedDisconnected` | `state.selection.selectedDisconnected` | UI | Management only |
| Selection | `selectedConnected` | `state.selection.selectedConnected` | UI | Management context follows connected profile |
| Protection | `strongBlockingReady` | `state.protection.strongBlockingReady` | Profile | Strong blocking may run when all guards hold |
| Protection | `limitReached` | `state.protection.limitReached` | Profile/cycle | Enforce only if eligible, authorized, unpaused, and approved |
| Protection | `blockingFailed` | `state.protection.blockingFailed` | Profile/cycle | Retry according to schedule |
| Protection | `blockingPaused` | `state.protection.blockingPaused` | Profile/cycle | Measurement continues; no blocking action |
| Protection | `blockingNotGuaranteed` | `state.protection.blockingNotGuaranteed` | Profile | Measurement may continue; no protection claim |
| Protection | `restorationConflict` | `state.protection.restorationConflict` | Profile/interface transaction | Persistent warning; do not overwrite user change |
| Preference transaction | `none` | not shown | Interface/profile | No open HBF-owned preference write |
| Preference transaction | `prepared` | `state.transaction.prepared` | Interface/profile | System write may be pending or crashed before write |
| Preference transaction | `applied` | `state.transaction.applied` | Interface/profile | HBF owns a temporary system preference change |
| Preference transaction | `restorationPending` | `state.transaction.restorationPending` | Interface/profile | Requires reconciliation before new enforcement |
| Preference transaction | `restored` | `state.transaction.restored` | Interface/profile | Configuration read-back succeeded |
| Preference transaction | `conflict` | `state.transaction.conflict` | Interface/profile | Current system value differs from HBF last write |
| Preference transaction | `unverified` | `state.transaction.unverified` | Interface/profile | Ownership or write result is uncertain |
| Restoration observation | `none` | not shown | Transaction | No observation required |
| Restoration observation | `pending` | `state.restorationObservation.pending` | Transaction | Observation window has not completed |
| Restoration observation | `verified` | `state.restorationObservation.verified` | Transaction | Full awake observation completed |
| Restoration observation | `unverified` | `state.restorationObservation.unverified` | Transaction | Observation interrupted or inconclusive |

Unknown persisted enum values are schema errors unless a version-specific migration names and maps them. Without a migration, HBF enters `recoveryRequired` and must not synthesize a default state.

`Candidate lifecycle=OperatorValidation` is a process-local safety overlay, not a persisted enum. While it is active, a profile may show the validation result and `blockingNotGuaranteed`, but it must never project `strongBlockingReady` or expose a protected-user status. A destructive candidate case is valid only when the current process has a runner-issued `OperatorValidationContextV1` whose run id, candidate digest set, gate/case id, and fresh confirmation match the case. The context is never reconstructed from persisted state, a mutable report, or a user preference; absent, stale, or mismatched context rejects the network action.

---

## 2. Event Priority

At a single scheduling point, `RuntimeEngine` processes events in this order:

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

A lower-priority event cannot make a successful state externally visible until all higher-priority required durable writes and reconciliation steps have succeeded. Persistence failure while committing a transition changes the outcome to `recoveryRequired` and suppresses any side effect that has not already occurred.

A deterministic forward cycle transition is not a `timeAdjustmentRequired` state. If an open HBF preference transaction exists, HBF reconciles that transaction before applying the one permitted cycle reset. A backward or otherwise uncertain time adjustment stops measurement, enforcement, suppression, disconnect, and new preference writes until the user acknowledges it. HBF may perform only an ownership-proven cleanup restoration of an already open transaction, using the normal archive, fingerprint, current-process authorization, read-back, and durable-persistence guards. A voluntary quit remains pending when acknowledgement or a required restoration is unresolved. Build-mode or eligibility changes use the same reconciliation-before-state-change rule.

---

## 3. Complete Transition Table

The table uses these terms:

- **Durable mutation:** The store update that must be flushed before the UI can report success.
- **Side effect:** A system action outside HBF's store.
- **Fail-closed result:** The state when a guard is absent or uncertain.

| Event or command | Entry condition | Required durable mutation | Permitted side effect | Exit condition | Resulting state |
|---|---|---|---|---|---|
| First launch with no store | No canonical store, no LKG, no completed-profile marker | Create empty v1 store with `hasCompletedProfile=false` | None | Store validates | `normal`, no selected profile |
| Launch with valid store | Canonical store decodes, integrity passes, schema supported, and the journal is `complete` or validly absent because no cross-file transition is in progress | Mark launch event, clear process-local authorization availability | Non-interactive authorization check only if guaranteed prompt-free | Snapshot emitted | Prior profile states, authorization unavailable unless check succeeds |
| Launch with missing/corrupt store after completed profile | Marker, LKG, or valid completed store proves prior completion | Preserve failed file path and recovery event | None | Recovery UI available | Global `recoveryRequired` |
| Launch with unknown future schema | Store schema exceeds supported version | Preserve store and recovery event | None | No migration available | Global `recoveryRequired` |
| Launch with non-complete or mismatched commit journal | `CommitJournalV1` (`commit-journal.json`) is non-complete, missing where a cross-file transition requires it, its revision/digest does not match a destination, or a cross-file cut point is unexplained | Preserve all candidate files and recovery event | None | Explicit recovery UI available | Global `recoveryRequired` |
| Version migration | Supported older schema and valid canonical or LKG | Atomic migrated `state.json`, updated LKG, migration event | None | New schema validates | Resume with migrated states |
| Migration failure | Migration decode/write/validation fails | Preserve source and failed migration event if possible | None | Failure recorded or write unavailable | Global `recoveryRequired` |
| Store write/flush failure | Any required durable write fails | Preserve LKG; record failure when possible | No new network side effect | Failure detected | Global `recoveryRequired` |
| Arithmetic overflow | RX+TX, delta, accumulated usage, revision, or presentation conversion overflows | Preserve last safe persisted state; record overflow | None | Last safe state remains valid | Global `recoveryRequired` |
| Sleep begins | Process is awake | Close sample interval, mark baseline pending for connected profile, flush lifecycle event | None | Sleep notification handled | Measurement suspended |
| Wake | Previous interval closed | Wake event, baseline pending | None | Identity must be re-resolved | Resolution state based on current identity |
| Relaunch/logout/reboot gap | New process with prior valid store | Baseline pending, downtime gap event | Non-interactive authorization check only if prompt-free | Snapshot emitted | No cross-process monotonic comparison |
| Time zone changes forward to later cycle | Current calculation is later than trusted cycle | Apply one cycle reset, baseline pending, time event | If an open HBF transaction exists, reconcile it first; restore only when ownership and authorization guards hold | Reset and any restoration outcome are persisted | `normal` when reconciliation succeeds; otherwise `restorationPending`, `conflict`, or `unverified` |
| Time zone or clock calculates earlier cycle | Current calculation is earlier than trusted cycle | Preserve trusted cycle/usage, baseline pending, time event | Ownership-proven cleanup restoration of an already open transaction only; no new preference write | Acknowledgement required | Global `timeAdjustmentRequired` |
| Wall clock moves backward | Trusted process-local monotonic comparison detects backward movement | Preserve usage/cycle, baseline pending, event | Ownership-proven cleanup restoration of an already open transaction only; no new preference write | Acknowledgement required | Global `timeAdjustmentRequired` |
| Wall/monotonic divergence over 60 seconds | Same awake process, no sleep boundary | Preserve usage/cycle, baseline pending, event | Ownership-proven cleanup restoration of an already open transaction only; no new preference write | Acknowledgement required unless a single forward cycle boundary was deterministically crossed | `timeAdjustmentRequired`; a deterministic forward boundary becomes `normal` only after the one reset is durably persisted |
| Acknowledge time adjustment | Global `timeAdjustmentRequired` and user confirms | Current zone/wall observation accepted, baseline pending, acknowledgement event | None | No earlier-cycle rollback; if current cycle is later, apply exactly one reset before acknowledgement succeeds | `normal` after persistence, or a new-cycle normal state |
| Identity permission granted | Location permission becomes usable | Permission event, baseline pending for affected target | None | Identity can be read | Current resolution applies |
| Identity permission denied/revoked/restricted | SSID/BSSID needed and unavailable | Permission event, baseline pending | None | State emitted | `locationPermissionRequired`, no measurement/blocking |
| Exact profile resolved | One completed profile matches interface, SSID bytes, confirmed BSSID | Connected-profile id and resolution event; baseline pending if identity changed | None | No global stop and no open blocking conflict | `monitoring` after baseline, protection evaluated separately |
| Unknown network resolved | No profile matches current interface/SSID | Resolution event, no profile usage mutation | None | User may create profile | `unknownNetwork` |
| New BSSID for one candidate | Interface/SSID matches one profile, BSSID unconfirmed | Candidate event, baseline pending | None | Await confirmation | `needsBSSIDConfirmation` |
| New BSSID for multiple candidates | Interface/SSID matches multiple profiles, BSSID unconfirmed | Candidate event, baseline pending | None | Await user selection and confirmation | `needsBSSIDConfirmation` |
| Multiple completed profiles resolved | Two or more target profiles resolved on different Wi-Fi interfaces | Multi-target event, baselines pending | None | User disconnects/resolves all but one | Application-global `multipleProfilesConnected`; settings and profile management remain available |
| Confirm BSSID append | Candidate profile selected and append would not duplicate full tuple | Append canonical BSSID, event, baseline pending | None | Store validates | Resolution can become `monitoring` |
| Duplicate BSSID tuple append | Append would duplicate interface/SSID/BSSID tuple | Rejection event only | None | Rejection shown | Prior state preserved |
| Shared interface/SSID confirmation | Completing/appending profile shares interface+SSID | Store shared-pair eligibility result and warning acceptance | None | Confirmation persisted | Affected profiles `blockingNotGuaranteed` |
| Valid counter sample with no baseline | Exact target resolved, counter read valid, baseline pending | Persist RX/TX baseline, identity, sample time | None | Baseline flushed | `monitoring`, no usage delta |
| Valid counter sample with baseline | Exact identity unchanged, same cycle, counters nondecreasing | Checked usage delta, baseline, sample time, possible limit transition | None before durable write | Usage flushed | `monitoring` or `limitReached` |
| Counter regression/reset | Current RX/TX lower than trusted baseline | Baseline pending and rebaseline event | None | New baseline required | `monitoring`, no delta |
| Counter transient failure | Exact candidate counter path previously proven, current read/parse/interface temporarily fails | Failure event, baseline pending | None | Retry later | Local `measurementUnavailable` |
| Exact candidate counter deterministic failure | Startup or candidate verification proves selected path unusable | Capability failure event | None | Failure recorded | Global `recoveryRequired` |
| Sample crosses reset boundary | Two trusted samples span effective reset boundary | Apply new cycle, zero usage, clear cycle-bound states, baseline pending | Restore open transaction if enforcement ends | Reset flushed | `normal`, no interval delta |
| Limit reached by sample or lower limit | Usage >= configured limit | Persist `limitReached`, retry state initialized when eligible | Blocking action only after durable limit transition | Limit transition flushed | `limitReached`; then enforcement event may run |
| Profile ineligible at limit | Shared interface/SSID, measurement-only build, pending gates, auth unavailable, or global stop | Persist protection reason | None | Snapshot emitted | `blockingNotGuaranteed`; use `blockingPaused` only when the profile's pause flag is true |
| Explicit authorization request | User invokes authorization action for eligible profile | Authorization attempt event | `SFAuthorization` prompt with required right/flags only | Authorization object usable in this process | `strongBlockingReady` if `Candidate lifecycle=Production` and all other guards hold; otherwise `blockingNotGuaranteed` with validation result |
| Authorization denied/unavailable | Prompt denied, cancelled, or non-interactive check unavailable | Authorization failure event | No automatic reprompt | Failure recorded | `blockingNotGuaranteed` |
| Authorization invalidated | Quit, relaunch, timeout, explicit invalidation, or provider failure | Audit event, process-local capability cleared | None | Snapshot emitted | `blockingNotGuaranteed` until explicit retry |
| Prepare preference suppression | Limit reached, eligible, authorized, unique interface/SSID, target identity exact | Persist `prepared` with original/intended archives and fingerprints | None | Flush succeeds | `prepared` |
| Crash/relaunch after `prepared`, current equals original | Open `prepared` transaction and current configuration fingerprint equals `originalFingerprint` | Reconciliation event; close the transaction as a verified no-op with `phase=restored` and `observation=none` | None | Original system value still present and no HBF write is owned | `restored` |
| Crash/relaunch after `prepared`, current equals intended | Open `prepared` transaction and current fingerprint equals `intendedFingerprint`, but no durable `Applied` proof exists | Reconciliation event; mark `phase=unverified` with `lastError=preparedWriteOutcomeUnknown` | None | No automatic restoration or new preference value | `unverified` |
| Crash/relaunch after `prepared`, current differs from both | Open `prepared` transaction and current fingerprint differs from both original and intended | Reconciliation event; mark `phase=conflict` with `lastError=externalPreferenceChange` | None | User warned; ownership remains unproven | `conflict` |
| Crash/relaunch after `prepared`, current unreadable | Open `prepared` transaction and current configuration or archive cannot be read | Reconciliation event; mark `phase=unverified` with `lastError=readBackUnavailable` | None | No automatic preference write | `unverified` |
| Commit preference suppression | `prepared`, authorization usable, exact target revalidated | None until read-back; then mark `applied` with last-written archive/fingerprint | `commitConfiguration(intended, authorization)` | Read-back equals intended | `applied` |
| Commit write/read-back uncertain | Commit throws, read-back fails, or intended mismatch | Mark `unverified` when store writable | No new value retry | Uncertainty recorded | `unverified`, no success claim |
| Target absent before preference write | Limit reached but target preferred-network entry already absent | Persist verified no-op event, no applied transaction | None | Read-back confirms target absent | No open transaction; continue disconnect verification |
| Exact-target disconnect | Identity re-read immediately before call equals target | Disconnect attempt event | `CWInterface.disassociate()` on current interface | Post-query confirms target absent | Suppression observation `pending` |
| Identity changed before disconnect | Immediate pre-call identity unavailable, ambiguous, or not target | Revalidation failure event | None | Failure recorded | `blockingFailed` or `blockingNotGuaranteed` based on capability |
| Disconnect unverified | API returns but post-query cannot confirm absence within bounded attempts | Failure event, retry state advanced | None | Retry scheduled | `blockingFailed` |
| Suppression observation completes | Target absent for full 30 awake seconds, `eventBacked` observations, no awake gap over two seconds, no unclassified reconnect | Observation event and summary | None | Awake window complete | Blocking success notification eligible |
| Suppression observation uses polling only | Candidate lacks usable event-backed observation | Observation event and summary | None | Polling window may be retained as diagnostic evidence | Strong-blocking result `unverified`; candidate strong-blocking gate fails |
| Suppression interrupted | Sleep/quit/relaunch or observation gap over two seconds before full awake window | Observation event | None | Window incomplete | Blocking result `unverified`; retry/reconcile as applicable |
| Reconnect without manual intent during suppression | Link event for exact target and no valid one-shot token | Failure event, retry state reset | None | Reconnection classified automatic/unverified | `blockingFailed` |
| One-shot manual reconnect intent | User invokes exact profile/interface action during suppression | Process-local token event with 60-second expiry | None | Token valid until next relevant link event or expiry | Reconnect may be classified user-intended |
| Manual intent consumed | Relevant link event occurs while token valid | Consume token event | None | Token cannot be reused | Normal enforcement still applies if limit reached |
| Enforcement retry tick | `blockingFailed`, target exact and connected, retry due | Retry attempt event | Preference/disconnect sequence if guards hold | Attempt completes or fails | Verified suppression returns to `limitReached` with observation `verified`; otherwise `blockingFailed` or `blockingNotGuaranteed` |
| Pause Blocking on | Selected eligible profile, user confirms if needed | Persist pause flag, stop retry, begin transaction restoration if owned | Restoration write only after ownership and authorization guards | Pause saved; restoration reconciled or pending | `blockingPaused`; measurement continues |
| Pause Blocking off | Selected profile paused | Clear pause flag, event | Enforcement may start immediately if exact target connected and all guards hold | Pause cleared | `strongBlockingReady` or immediate `limitReached` enforcement |
| Manual usage reset | Selected profile, confirmation accepted | Usage zero, baseline pending, limit reevaluated, reset event | Restore owned transaction if limit clears | Store flushed | Usage 0; no reconnection |
| Manual reset cancelled | Confirmation cancelled | None or cancellation event | None | Prior state retained | Prior state |
| Limit lowered below usage | Valid limit save | Persist new limit and `limitReached` | Enforcement may start after durable write | Limit flushed | `limitReached` |
| Limit increased above usage | Separate confirmation accepted | Persist new limit, clear limit reached, stop retry, baseline pending, event | Restore owned transaction; never reconnect | Store flushed | `strongBlockingReady` or `blockingNotGuaranteed` |
| Limit increase cancelled | Confirmation cancelled | None or cancellation event | None | Prior state retained | Prior state |
| Reset-day change accepted with new cycle | Confirmation accepted and effective cycle changes | Persist reset day, new cycle, usage zero, clear cycle-bound states, baseline pending | Restore owned transaction if enforcement ends | Store flushed | New cycle normal state |
| Reset-day change accepted same cycle | Confirmation accepted and cycle unchanged | Persist reset day, baseline pending, event | None | Store flushed | Prior usage/cycle preserved |
| Notification mute | Failure notification currently available | Persist mute kind, expiry or cycle id | None | Snapshot emitted | Notifications muted only |
| Mute expiry | Wall-clock expiry reached or cycle changes | Clear mute and event | Notification may be sent subject to throttle | Store flushed | Enforcement unchanged |
| User changes Wi-Fi preferences externally | Current fingerprint differs from HBF last-written fingerprint when restoration due | Conflict event | None | User warning shown | `restorationConflict` and transaction `conflict` |
| Restore owned preference | Open `applied`/`restorationPending`, current fingerprint equals HBF last-written, authorization usable | Mark restoration attempt; after read-back mark `restored`, observation `pending` | `commitConfiguration(original, authorization)` | Read-back equals original | Transaction `restored` |
| Restoration needs authorization after relaunch | Open transaction needs write and no usable process-local authorization | Persist `restorationPending` and authorization-needed event | No automatic prompt | User must invoke explicit restore/authorization action | `restorationPending`, `blockingNotGuaranteed`, no new enforcement |
| Restoration read-back fails | Write or read-back uncertain | Mark `unverified` when possible | No overwrite retry with new value | Warning shown | Transaction `unverified` |
| Post-restoration observation completes | `restored`, observation pending, 30 awake seconds processed with no gap over two seconds | Mark observation `verified` and its source | None | Window complete | `restored`; retain the transaction as audit data until the normal event/transaction retention rule purges it |
| Post-restoration observation interrupted | Sleep/quit/relaunch or observation gap over two seconds before full window | Mark observation `unverified` and its source | None | Window incomplete | Config may remain `restored`; observation `unverified` |
| Voluntary quit | User confirms quit | Save lifecycle event; reconcile/restore owned transaction first | Quit only after no pending/failed/unverified restoration | Cleanup verified or no transaction | Process exits |
| Voluntary quit with pending restoration failure | Cleanup cannot complete safely | Persist failure/unverified state | Do not quit normally | Retry offered | App remains running |
| Force quit/crash | Process terminates without cleanup | None during crash | None | Next launch reconciles open transaction | Launch recovery path |
| Profile deletion | Profile inactive, exact alias entered, irreversible confirmation accepted | Tombstone first, then purge active/LKG records/transactions/profile-scoped events; append a global deletion event with `profileID=null` only after purge validates | None | Purge and global audit event validate | Profile absent and cannot resurrect from LKG |
| Deletion interrupted | Tombstone exists but purge incomplete | Resume purge or enter deletion recovery | None | Purge completes or recovery shown | No profile resurrection |
| Selection change | User selects profile or clears selection | Persist selected profile id or nil | None | Store flushed | Selection state only |
| Language change | User selects System Default/Korean/English | Persist override or nil | None | Store flushed | UI relocalized; domain unchanged |
| Build mode change or release manifest mismatch | Runtime artifact/report differs from stored audit or support matrix | Audit event; clear blocking capability pending reconciliation | None | Manifest checked | `blockingNotGuaranteed`; reconcile open transactions |

---

## 4. Command Contract

Every UI command carries a generated idempotency key, the selected profile id when applicable, the store revision observed by the UI, and a confirmation token when a destructive or safety-sensitive action is confirmed. Commands whose observed revision is stale must be revalidated against the current snapshot before any mutation.

An idempotency key is scoped to the command name and installation id. If the
same key is received again, HBF returns the previously persisted command
result and performs no second mutation or system side effect. A stale store
revision returns `staleSnapshot` after a fresh snapshot is emitted; it never
implicitly retries the command with new state. A command result is persisted
before it is reported as successful.

The persisted command result is a durable historical command result, not a
restoration of a process-local effect. For `requestBlockingAuthorization`, a replay after a
process restart returns the historical result without prompting again and
reports the current effect as `authorizationRequired` when no usable
authorization exists. For `recordManualReconnectIntent`, a replay after a
restart or token expiry returns the historical result without recreating a
token and reports the current effect as `intentExpired` or
`intentUnavailable`. These current-effect values are runtime response state
and are never persisted as usable capabilities.

| Command | Payload | Confirmation | Success contract | Failure contract |
|---|---|---|---|---|
| `createProfileFromCurrentNetwork` | alias, limit, reset day | Required only for shared interface/SSID warning | Saves complete profile only when identity, limit, and alias validate | Saves no partial identity; shows permission/identity error |
| `createProfileManualIdentity` | alias, SSID hex, interface name, BSSID, limit, reset day | Required for shared interface/SSID warning | Stores canonical bytes/name/BSSID and complete profile | Rejects malformed input without partial profile |
| `appendBSSID` | profile id, observed interface/SSID/BSSID | Explicit append confirmation | Adds canonical BSSID if duplicate tuple is not created | Leaves existing BSSID set unchanged |
| `selectProfile` | profile id or nil | None | Changes management context only | Never reconnects, measures, or blocks by selection alone |
| `togglePauseBlocking` | profile id, desired boolean | Confirmation optional for enabling during active enforcement | Persists pause flag and reconciles owned transaction when enforcement stops | Leaves state unchanged on restoration conflict; warning persists |
| `manualResetUsage` | profile id | Required | Usage zero, baseline pending, limit reevaluated, owned transaction restored if limit clears | Prior usage preserved if confirmation cancelled or store write fails |
| `changeLimit` | profile id, parsed hundredth-GB integer | Required only when increasing above current usage | Persists exact bytes, reevaluates limit and enforcement | Old limit/state preserved on cancellation or validation failure |
| `changeResetDay` | profile id, day 1-31 | Required | Persists day and applies cycle effect before next delta | Old reset day preserved on cancellation |
| `requestBlockingAuthorization` | profile id, operation purpose (`preferenceSuppression` or `preferenceRestoration`) | macOS authorization prompt | In-memory authorization available only in current process | No automatic retry; profile `blockingNotGuaranteed` |
| `recordManualReconnectIntent` | profile id, interface name, transaction id | Explicit user action during suppression only | Creates process-local one-shot token, persisted event only | No token if suppression window is absent or target differs |
| `retryRestoration` | transaction id | May require explicit authorization prompt | Restores only when ownership fingerprint matches | Keeps `restorationPending`, `conflict`, or `unverified` without overwrite |
| `muteFailureNotification` | profile id, mute kind (`tenMinutes`, `oneHour`, or `untilCycleEnds`) | None | Persists notification mute only | Enforcement and measurement unchanged |
| `deleteProfile` | profile id, exact alias | Exact alias plus irreversible confirmation | Writes tombstone first, then purges active/LKG/profile-scoped events/transactions and appends a global deletion event with `profileID=null` only after validation | Profile remains if purge cannot validate |
| `quitApplication` | none | Required warning | Exits only after owned restoration completes or no transaction exists | App remains open on pending/failed/unverified restoration |

---

## 5. CoreWLAN Disassociate Safety Contract

`CWInterface.disassociate()` operates on the interface's current association. HBF cannot make that call atomically conditional on SSID/BSSID through the public API. Therefore v1 uses a conservative fail-closed contract rather than claiming a stronger guarantee than the API provides.

### 5.1 Stable identity snapshot

Every identity-dependent transition uses one `IdentitySnapshotV1` with the fields `interfaceName`, `interfaceIndex`, `linkState`, raw `ssidBytes`, and `bssid`. CoreWLAN exposes these values through separate getters, so the adapter must enumerate the interfaces once and serialize two consecutive reads of all required fields from that same pass. It accepts the snapshot only when every required field is byte-for-byte equal across both reads and no interface-change observation occurs between them. A missing value, getter failure, enumeration change, callback/getter race, or mismatch rejects the snapshot. The rejected snapshot cannot produce a measurement delta, preference write, disconnect, or suppression observation. The same procedure is required immediately before a preference write and immediately before `disassociate()`.

The algorithm is:

1. Obtain a stable `IdentitySnapshotV1` immediately before any preference write. If interface name, interface index, SSID bytes, or BSSID is unavailable or not equal to the target tuple, stop.
2. Commit a suppression preference only after a flushed `prepared` transaction and a fresh stable identity snapshot.
3. Obtain another stable `IdentitySnapshotV1` immediately before `disassociate()`.
4. Call `disassociate()` only when that final read still matches the exact target tuple.
5. Immediately query the interface at most five times over a two-second monotonic deadline. Success requires the target tuple to be absent. A returned API call without post-query absence is not success.
6. If the interface changes to an unrelated network between the final read and the call, public CoreWLAN does not expose an atomic guard that can prove the call did not affect that unrelated network. This residual TOCTOU window is classified as an unproven safety boundary in the release gate. Until R-05 and R-04 prove no unrelated disconnect on every supported macOS build, the artifact cannot make a strong-blocking distribution claim.

This contract satisfies the product's safety rule by failing closed before the call whenever HBF can observe uncertainty. It does not claim mathematical atomicity or a universal "never unrelated" proof that the public API cannot provide. The release report must state this residual boundary and the exact evidence observed on each supported macOS build.

---

### 5.2 Network Observation Contract

The runtime represents every suppression and restoration sample as a `WiFiObservationV1` value containing the canonical interface name, link state, optional raw SSID bytes, optional BSSID, observation source, process lifecycle identifier, and monotonic timestamp. A display name, wall-clock duration, or absence of an HBF association call is not sufficient evidence.

The observation source is one of:

- `eventBacked`: a `CWWiFiClient` link, SSID, or BSSID callback was received and followed by an immediate current-state read.
- `pollBacked`: a current-state read from the one-second awake polling cadence or an immediate read after a public lifecycle notification.
- `lifecycleOnly`: only a lifecycle boundary was received; it proves neither network presence nor network absence.

An active window must not contain an observation gap greater than two monotonic seconds. A strong-blocking suppression result is verified only with at least 30 awake seconds, `eventBacked` observations, a final target-absent observation, and no unclassified reconnection. Polling-only evidence is retained as diagnostic evidence but makes the suppression result `unverified` and fails the strong-blocking feasibility gate. A restoration observation may be verified with `pollBacked` coverage because it does not claim automatic-reconnection suppression. Sleep, quit, relaunch, or an excessive observation gap ends the current window as `unverified`.

The persisted `ObservationSummaryRecord` uses the fixed fields `result`, `source`, `awakeSecondsObserved`, `maxGapSeconds`, and `targetAbsentAtEnd`. The source and coverage values in this summary must be derived from the typed observations rather than inferred from a timer or lifecycle event.

---

## 6. SFAuthorization Operation Boundary

The authorization right is the CoreWLAN configuration commit right required by `CWInterface.commitConfiguration(_:authorization:)`. The initial v1 candidate must request only the right needed for that operation. If the SDK or OS does not publish a stable symbolic right name for the CoreWLAN commit path, the GitHub-candidate feasibility gate must record the exact right string accepted by the OS before strong-blocking integration continues.

Required flags:

| Context | Flags | Prompt allowed | Persistence |
|---|---|---|---|
| Explicit user authorization action | `interactionAllowed`, `extendRights`, `preAuthorize` when supported by the selected right | Yes | Authorization object remains memory-only |
| Enforcement retry | Existing in-memory authorization only | No | No persisted authorization object |
| Launch/relaunch check | Non-interactive check only, no prompt-producing flags | No | Result is process-local only |
| Restoration retry chosen by user | Same explicit authorization action boundary as blocking authorization | Yes | Authorization object remains memory-only |

Lifecycle rules:

- Authorization is scoped to the current process and current operation family.
- HBF invalidates it on quit, relaunch, logout, reboot, explicit authorization failure, or when the provider reports it unusable.
- Persisted authorization success is audit history only.
- `disassociate()` receives no authorization parameter, so authorization success is never evidence that disconnect succeeded.
- Automatic retries never display an authorization prompt. If restoration needs authorization after relaunch, the transaction remains `restorationPending` until the user invokes an explicit authorization/restoration action.

---

## 7. UI, Accessibility, and Localization Mapping

All visible states and commands must have stable identifiers before UI implementation begins.

| Runtime item | Accessibility identifier | String key prefix | Notes |
|---|---|---|---|
| Menu bar usage value | `MenuBar.UsageValue` | `menu.usage` | Displays `—` outside normal measured usage |
| Connected profile row | `Menu.Profile.Connected` | `profile.connected` | Shows identity status, not raw private identifiers |
| Selected profile row | `Menu.Profile.Selected` | `profile.selected` | Selection cannot imply measurement |
| Measurement state label | `Status.Measurement` | `state.connection.*` | Must not rely on color alone |
| Protection state label | `Status.Protection` | `state.protection.*` | Multiple protection flags may be visible |
| Pause Blocking toggle | `Command.PauseBlocking` | `command.pauseBlocking` | Disabled for measurement-only/shared profiles |
| Manual reset button | `Command.ResetUsage` | `command.resetUsage` | Requires confirmation |
| Authorization button | `Command.RequestAuthorization` | `command.requestAuthorization` | Only explicit user action may prompt |
| Manual reconnect intent button | `Command.ManualReconnectIntent` | `command.manualReconnectIntent` | Visible only during suppression observation |
| Mute menu | `Command.MuteFailureNotification` | `command.muteFailureNotification` | Notification-only effect |
| Delete profile action | `Command.DeleteProfile` | `command.deleteProfile` | Requires exact alias entry |
| Quit action | `Command.Quit` | `command.quit` | Cleanup must finish before normal quit |
| Recovery banner | `Banner.RecoveryRequired` | `banner.recoveryRequired` | Persistent and actionable |
| Restoration warning | `Banner.RestorationConflict` | `banner.restorationConflict` | Persistent until resolved |

String Catalog coverage must include Korean and English values for every key used by these identifiers, plus notification titles/bodies and confirmation dialogs. UI tests must assert identifiers and semantic state, not localized prose alone.
