# Hotspot Byte Fence v0.1.2

## 한국어

앱 내 업데이트 후 설치 폴더에 백업 앱이 계속 쌓이는 문제를 수정했습니다.

- 교체 중에는 기존 앱을 복구용으로 보관하고, 새 앱의 실행 요청이 성공하면 macOS 휴지통으로 옮깁니다.
- 교체에 실패하면 기존 앱을 복원합니다. 실행 요청이나 휴지통 이동에 실패하면 백업을 보존합니다.
- 설치 확인 창과 사용 안내를 새 동작에 맞게 수정했습니다. 기존 프로필과 사용량은 유지됩니다.

**적용 시점:** 이 변경은 v0.1.2에서 이후 버전으로 앱 내 업데이트할 때 적용됩니다. 이전 버전에서 v0.1.2를 설치하는 과정은 이전 업데이터가 처리하므로 백업이 남을 수 있습니다. 이미 쌓인 백업은 자동 정리하지 않습니다.

**설치:** Apple Silicon(arm64), macOS 13 이상을 지원합니다. DMG는 직접 설치용이며 ZIP은 직접 설치와 앱 내 업데이트에 사용합니다. 다운로드 파일은 `SHA256SUMS.txt`로 검증할 수 있습니다. Developer ID 서명과 Apple 공증은 제공하지 않습니다. [한국어 설치 안내](https://github.com/charliehotel/hotspot-byte-fence/blob/v0.1.2/README.md)를 참고하세요.

**검증 범위:** 릴리스 빌드, 전체 자동화 테스트, 앱 버전과 ad hoc 서명, ZIP·DMG 무결성을 확인했습니다. 임시 파일로 macOS 휴지통 이동도 확인했습니다. 실제 설치된 앱의 업데이트 전체 과정과 Wi-Fi 차단 동작은 이번 검증에 포함하지 않습니다. 실행 요청의 성공이 앱의 지속적인 정상 동작을 보장하지는 않습니다.

## English

Fixed backup apps accumulating in the installation folder after in-app updates.

- The previous app is retained for recovery during replacement, then moved to macOS Trash after the new app’s launch request succeeds.
- If replacement fails, the previous app is restored. If the launch request or Trash operation fails, the backup is preserved.
- Updated the installation confirmation and user guides to describe this behavior. Existing profiles and usage are preserved.

**When it takes effect:** This change applies to in-app updates from v0.1.2 to a later version. Updating an older version to v0.1.2 still uses the older updater and may leave a backup. Previously accumulated backups are not cleaned up automatically.

**Installation:** Requires Apple Silicon (arm64) and macOS 13 or later. Use the DMG for manual installation or the ZIP for manual installation and in-app updates. Verify downloads with `SHA256SUMS.txt`. Developer ID signing and Apple notarization are not provided. See the [English installation guide](https://github.com/charliehotel/hotspot-byte-fence/blob/v0.1.2/README/README.en.md).

**Verification:** Checked the release build, full automated test suite, app version and ad hoc signature, and ZIP/DMG integrity. Also verified macOS Trash operations using a temporary file. End-to-end updates of the installed app and actual Wi-Fi blocking were not tested for this release. A successful launch request does not guarantee continued app health.
