# Hotspot Byte Fence v0.1.3

## 한국어

무제한 프로필의 사용량이 1,000GB를 넘으면 한도에 도달한 것으로 오인해 Wi-Fi 연결을 차단하던 문제를 수정했습니다.

- 무제한과 유한 데이터 한도를 별도 상태로 표현하며, 무제한 프로필은 사용량 비교 대상에서 제외합니다.
- 이전 버전에서 저장한 무제한 프로필도 기존 설정을 다시 만들지 않고 무제한으로 읽습니다.
- 이전 버전에 저장된 무제한 한도 도달 상태도 차단 상태로 표시하거나 연결 해제를 재시도하지 않습니다.

**검증 범위:** 자동화 테스트 139개가 통과했습니다. 실기기에서 사용량이 1,000GB를 넘은 무제한 프로필을 실행해 Wi-Fi 연결이 유지되는 것도 확인했습니다. 차단·복원·재연결의 나머지 실기기 게이트는 실행하지 않았습니다.

**설치:** Apple Silicon(arm64), macOS 13 이상을 대상으로 합니다. ZIP과 DMG의 SHA-256은 릴리스의 `SHA256SUMS.txt`에서 확인할 수 있습니다. ZIP 안의 앱은 서명되지 않았으며, 설치 안내에 따라 로컬 ad hoc 서명을 적용해야 합니다. DMG에는 ad hoc 서명된 앱과 응용 프로그램 폴더 바로가기가 들어 있습니다. Developer ID 서명과 Apple 공증은 제공하지 않습니다.

## English

Fixed an issue that could mistake usage above 1,000 GB for a reached quota and block Wi-Fi on an unlimited profile.

- Unlimited and finite quotas are represented separately, and unlimited profiles are excluded from quota comparisons.
- Unlimited profiles saved by earlier versions are still read as unlimited; users do not need to recreate them.
- A stale limit-reached state saved by an earlier version no longer appears as an active limit or retries disconnection for an unlimited profile.

**Verification:** All 139 automated tests passed. Regression coverage includes usage above 1,000 GB, unlimited profiles in the previous storage format, the finite quota boundary, a previously saved blocking state, and a delayed limit event. A real-Mac check with an unlimited profile above 1,000 GB confirmed that Wi-Fi stayed connected. The remaining real-device blocking, restoration, and reconnection gates were not run.

**Installation:** Targets Apple Silicon (arm64) and macOS 13 or later. Check `SHA256SUMS.txt` for the ZIP and DMG hashes. The app inside the ZIP is unsigned; apply the local ad hoc signature described in the installation guide. The DMG contains an ad hoc signed app and an Applications shortcut. Developer ID signing and Apple notarization are not provided.
