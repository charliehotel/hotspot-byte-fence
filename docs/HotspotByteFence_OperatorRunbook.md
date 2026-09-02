# Hotspot Byte Fence (HBF) — Real-Mac Operator Runbook

**Version:** 0.3
**Date:** 2026-09-01  
**Status:** Procedure contract only. No candidate gate has been run.

This runbook is the mandatory procedure for F-06 through F-12 and R-01 through R-15. It prevents destructive Wi-Fi actions from being mistaken for ordinary automated tests and defines the evidence needed for a candidate or release verdict. The v1 compatibility validation target is macOS 13.0 or later on `arm64`, but each supported claim requires an exact macOS build row and an independent candidate/release evidence binding.

For this v1 policy, the operator verifies the published unsigned asset SHA-256 before extracting or signing it, applies the exact local ad hoc-signing procedure published in `README.md`, and records the resulting app-bundle and executable SHA-256 values and actual signature state separately. The post-signing artifact is the exact candidate only when the gate record binds those digests; an arbitrary user-resigned copy cannot inherit a candidate or release verdict.

## 1. Safety rules

- Run only on the operator-approved Mac and test networks. Do not use a production hotspot, a network whose interruption could cause data loss, or a machine with unsaved network-dependent work.
- Confirm the target, unrelated network, interface, and current BSSID immediately before every destructive case. A mismatch aborts the case.
- Show a fresh warning and receive an explicit confirmation immediately before each case that may disconnect Wi-Fi, change a preferred-network list, or request administrator authorization.
- Never record passwords, authorization objects, packet contents, URLs, geographic coordinates, or full user-identifying network names in shared evidence.
- Abort on an unexpected disconnect of an unrelated network, a preference read-back mismatch, an unexpected authorization prompt, sleep, loss of the evidence directory, or an observation gap over two seconds.
- After an abort, do not retry with a new preference value. Preserve the local evidence and reconcile the open transaction through the application recovery path.

## 2. Required topology

The operator assigns local values to these roles and records only hashes or approved labels in a shared report.

| Role | Required setup | Purpose |
|---|---|---|
| `T1` | One controlled target hotspot with a known SSID byte sequence and BSSID | Identity, counter, disconnect, and suppression cases |
| `T2` | One unrelated preferred network on the same Wi-Fi interface | Preservation and external-change cases |
| `T3` | A second Wi-Fi interface with a second completed target profile, if the hardware is available | Multiple-profile resolution case |
| `T4` | A VPN or virtual interface carrying traffic over `T1`, if the fixture is available | Interface-counter accounting case |

`T1` and `T2` are required for the strong-blocking gate. `T3` and `T4` are required before claiming the corresponding acceptance criteria; their absence leaves those cases pending rather than passing them by assumption.

## 3. Evidence layout

Every run receives a unique `runID` and writes to:

```text
QA/Evidence/<applicationVersion>/<macOSBuild>/<runID>/
  preflight.json
  local/
  report-redacted.json
```

`local/` contains the complete owner-only evidence, including local-sensitive identifiers and configuration archives when permitted by the persistence schema. `report-redacted.json` is generated from local evidence and must fail validation if it contains a prohibited field. The report must include the candidate and embedded-manifest digests before any functional gate is credited.

The implementation must provide one deterministic runner with this interface:

```text
Scripts/hbf-gate-run preflight --candidate <path> --output <run-directory>
Scripts/hbf-gate-run run --gate <F-01..F-11|F-12|R-01..R-15> [--phase preflight|classification] [--case <case-id>] --run <run-directory>
Scripts/hbf-gate-run report --run <run-directory>
```

`--phase` is valid only with `--gate F-12`: `preflight` records observation capability and instrumentation before destructive cases, while `classification` consumes the applicable R-case observation records after the run. Every other gate uses a single phase.

For every destructive gate case, `--case` is required and identifies the fixed case in the fixture/oracle matrix. The runner creates a process-local `OperatorValidationContextV1` for that case containing `schemaVersion=1`, `runID`, the exact unsigned-asset/app-bundle/executable/embedded-manifest digest set, `gateID`, `caseID`, and a fresh operator-confirmation record. The context is a test-workflow binding, not an authorization credential; the application still displays its warning and requires the operator's confirmation immediately before the action. The candidate must reject a destructive action when the context is absent, stale, or mismatched, and must not reconstruct it from persisted state, a mutable report, or a user preference. The context is never persisted; only its validation result and redacted identifiers are recorded in evidence.

The runner may delegate destructive confirmation to the application UI, but it must not silently approve a case, synthesize an observation, or treat a mock adapter as candidate evidence. A candidate launched outside this context is not a strong-blocking or protected-user run.

## 4. Preflight sequence

1. Record the application version, full source revision, exact GitHub asset SHA-256, canonical post-signing app-bundle SHA-256 using `hbf-app-bundle-v1-sha256` when applicable, executable SHA-256, embedded `BuildManifestV1` SHA-256, bundle identifier, architecture, macOS version/build, signature/runtime/notarization status, quarantine state, Gatekeeper result, and available topology roles.
2. Validate that the application is non-sandboxed, has the required `NSLocationUsageDescription`, and does not install a privileged helper or daemon.
3. Record Location Services, notification authorization, and process-local administrator-authorization state without requesting an unapproved prompt.
4. Record the canonical `T1` and `T2` identity hashes from coherent `IdentitySnapshotV1` reads and confirm that the Mac is awake and no unrelated network operation is in progress.
5. Create the local evidence directory and verify that the application can write its owner-only state and evidence files.

If any preflight value is unavailable, the affected gate remains `PENDING` or becomes `BLOCKED`; the operator must not fill it with an inferred value.

## 5. Gate execution order

Run non-destructive and permission cases first, then run destructive cases one at a time:

1. F-01 through F-05: artifact, identity, permission, counter, and continuity checks.
2. F-11: relaunch and process-local authorization boundary.
3. F-12-preflight: event entitlement visibility, callback delivery, one-second polling fallback, timing instrumentation, and evidence-schema readiness. Do not credit suppression/restoration classification yet.
4. F-06: explicit administrator authorization success, denial, cancellation, exact right string, and flags.
5. F-07: target-present, target-absent, duplicate-security-profile, and unrelated-preference configuration archive cases.
6. F-08: exact-target revalidation, disconnect, bounded post-query, and residual target-switch observation.
7. F-09 and F-10: ownership-based restoration and preservation of unrelated configuration.
8. R-01 through R-15: repeat the applicable candidate cases on the exact unchanged artifact and exact support-matrix row.
9. F-12-classification: finalize F-12 from the applicable R-06/R-07/R-08 and R-10 observation records, including source, awake duration, maximum gap, and final target state.

The F-12 preflight must pass with an event-backed path before R-06 or R-07 can be reported as a strong-blocking pass. Polling-only evidence may validate measurement or restoration observation behavior, but it cannot validate suppression of automatic reconnection. The preflight result is sufficient for gated candidate integration; the release verdict remains `PENDING` until `F-12-classification` evidence from the applicable R cases is bound to the same candidate. The resulting `ObservationGateReportV1` is the single canonical F-12 report, and its aggregate verdict is `PASS` only when both phase verdicts are `PASS`.

If the runner cannot create or validate the current `OperatorValidationContextV1`, if the candidate presents `StrongBlockingReady` during operator validation, or if a destructive action is attempted without fresh confirmation, abort the run and mark the case `FAIL` or `BLOCKED` with the reason. Do not credit any partial side effect as a passing observation.

## 6. Required per-case record

Each gate record must contain:

- gate id, run id, start/end time, and operator confirmation time
- exact unsigned-asset, app-bundle, executable, and manifest digests, with `hbf-app-bundle-v1-sha256` recorded when applicable
- gate/case id and the `OperatorValidationContextV1` validation result; never the context itself
- exact macOS version/build and architecture
- topology role and redacted target identities
- precondition and action result
- observation source, awake duration, maximum gap, and final target state
- original, intended, last-written, and restored configuration fingerprints where applicable
- authorization outcome, exact right string, flags, prompt count, and cancellation/denial result where applicable
- expected oracle, observed result, final verdict, and unresolved risk

The expected oracle comes from the fixture contract in `HotspotByteFence_VerificationTraceability.md`. A case is `PASS` only when the observed result satisfies that oracle and the evidence is complete.

## 7. Verdict rules

- `PASS`: the exact expected oracle is observed and the evidence is complete.
- `FAIL`: the product or public API behavior contradicts the required oracle.
- `PENDING`: the case has not been run or the evidence is not bound to the exact candidate.
- `BLOCKED`: a required operator resource or permission is unavailable and the case cannot be run safely.

One failed mandatory F gate prevents normal-runtime strong-blocking integration. A failed strong-blocking R gate permits a measurement-only release only when identity and counter capability gates pass. A missing topology role never counts as a pass.
