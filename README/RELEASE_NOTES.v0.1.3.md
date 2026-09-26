# Hotspot Byte Fence v0.1.3

## 한국어

무제한 사용량으로 설정한 프로필이 내부 sentinel인 1,000GB를 넘은 뒤 Wi-Fi 연결을 차단하던 문제를 수정했습니다.

- 무제한 프로필은 사용량이 sentinel보다 커져도 한도 도달이나 연결 해제 대상으로 처리하지 않습니다.
- 기존 프로필 저장 형식을 유지하므로 설정과 사용량을 변환할 필요가 없습니다.
- 이전 버전에 저장된 무제한 한도 도달 상태도 차단 상태로 표시하거나 연결 해제를 재시도하지 않습니다.

**검증 범위:** 전체 자동화 테스트 138개, 1,000GB sentinel 초과 샘플·이전 차단 상태·지연된 한도 이벤트를 포함한 reducer 회귀 검사, 릴리스 빌드와 앱 패키지를 확인했습니다. ad hoc 서명, ZIP 무결성, DMG 검사와 DMG 안의 앱 버전·서명도 확인했습니다. 실제 Wi-Fi 차단·복원 게이트는 실행하지 않았으므로 실제 네트워크 동작은 이번 검증에 포함되지 않습니다.

**설치:** Apple Silicon(arm64), macOS 13 이상을 대상으로 합니다. ZIP과 DMG의 SHA-256은 릴리스의 `SHA256SUMS.txt`에서 확인할 수 있습니다. ZIP 안의 앱은 서명되지 않았으며, 설치 안내에 따라 로컬 ad hoc 서명을 적용해야 합니다. DMG에는 ad hoc 서명된 앱과 응용 프로그램 폴더 바로가기가 들어 있습니다. Developer ID 서명과 Apple 공증은 제공하지 않습니다.

## English

Fixed an issue that could block Wi-Fi after an unlimited profile’s usage passed its internal 1,000 GB sentinel.

- Unlimited profiles no longer count as reaching a quota or trigger disconnection when usage exceeds the sentinel.
- Existing profile storage is unchanged; settings and usage do not need conversion.
- A stale limit-reached state saved by an earlier version no longer appears as an active limit or retries disconnection for an unlimited profile.

**Verification:** All 138 automated tests passed. This includes the reducer regression covering counter samples above the 1,000 GB sentinel, a previously saved blocking state, and a delayed limit event. The release build, ad hoc signature, ZIP integrity, DMG integrity, and the mounted DMG app’s version and signature were checked. The real Wi-Fi blocking and restoration gates were not run, so live network behavior is not included in this verification.

**Installation:** Targets Apple Silicon (arm64) and macOS 13 or later. Check `SHA256SUMS.txt` for the ZIP and DMG hashes. The app inside the ZIP is unsigned; apply the local ad hoc signature described in the installation guide. The DMG contains an ad hoc signed app and an Applications shortcut. Developer ID signing and Apple notarization are not provided.
