# Hotspot Byte Fence v0.1.3

## 한국어

무제한 프로필의 사용량이 1,000GB를 넘으면 한도에 도달한 것으로 오인해 Wi-Fi 연결을 차단하던 문제를 수정했습니다.

- 무제한과 유한 데이터 한도를 별도 상태로 표현하며, 무제한 프로필은 사용량 비교 대상에서 제외합니다.
- 이전 버전에서 저장한 무제한 프로필도 기존 설정을 다시 만들지 않고 무제한으로 읽습니다.
- 이전 버전에 저장된 무제한 한도 도달 상태도 차단 상태로 표시하거나 연결 해제를 재시도하지 않습니다.
- **기존 동작 확인:** 이전 버전 실기기에서 정량 한도 도달 후 대상 Wi-Fi만 연결 해제되고, 다른 네트워크 설정은 덮어쓰지 않으며, 자동·수동 재연결 시 다시 차단되고, 앱 재실행 후 프로필을 다시 인식해 차단하는 것을 확인했습니다. 이번 수정은 이 유한 한도 차단·복원 경로를 변경하지 않습니다.

**이번 버전 검증:** 자동화 테스트 139개가 통과했습니다. 실기기에서 사용량이 1,000GB를 넘은 무제한 프로필의 Wi-Fi 연결이 유지되는 것을 확인했습니다. 위의 유한 한도 차단·복원 동작은 이전 버전에서 확인한 결과를 유지하며, 이번 버전에서 별도로 반복하지 않았습니다.

**설치:** Apple Silicon(arm64), macOS 13 이상을 대상으로 합니다. ZIP과 DMG의 SHA-256은 릴리스의 `SHA256SUMS.txt`에서 확인할 수 있습니다. ZIP 안의 앱은 서명되지 않았으며, 설치 안내에 따라 로컬 ad hoc 서명을 적용해야 합니다. DMG에는 ad hoc 서명된 앱과 응용 프로그램 폴더 바로가기가 들어 있습니다. Developer ID 서명과 Apple 공증은 제공하지 않습니다.

## English

Fixed an issue that could mistake usage above 1,000 GB for a reached quota and block Wi-Fi on an unlimited profile.

- Unlimited and finite quotas are represented separately, and unlimited profiles are excluded from quota comparisons.
- Unlimited profiles saved by earlier versions are still read as unlimited; users do not need to recreate them.
- A stale limit-reached state saved by an earlier version no longer appears as an active limit or retries disconnection for an unlimited profile.
- **Previously verified behavior:** On an earlier version, the user confirmed on a real Mac that reaching a finite quota disconnects only the target Wi-Fi, preserves other network settings, blocks automatic and manual reconnection, and blocks again after the app relaunches and recognizes the profile. This change leaves the finite-quota blocking and restoration path unchanged.

**This version:** All 139 automated tests passed. Regression coverage includes usage above 1,000 GB, unlimited profiles in the previous storage format, the finite quota boundary, a previously saved blocking state, and a delayed limit event. A real-Mac check with an unlimited profile above 1,000 GB confirmed that Wi-Fi stayed connected. The finite-quota blocking and restoration behavior above carries forward from the previous-version check and was not repeated on this version.

**Installation:** Targets Apple Silicon (arm64) and macOS 13 or later. Check `SHA256SUMS.txt` for the ZIP and DMG hashes. The app inside the ZIP is unsigned; apply the local ad hoc signature described in the installation guide. The DMG contains an ad hoc signed app and an Applications shortcut. Developer ID signing and Apple notarization are not provided.
