# Hotspot Byte Fence

Hotspot Byte Fence (HBF)은 macOS 메뉴 막대용 데이터 사용량 측정 및 Wi-Fi 보호 도구입니다.

[GitHub Releases](https://github.com/charliehotel/hotspot-byte-fence/releases)

현재 v1 배포 기준은 다음과 같습니다.

- GitHub Release에는 Developer ID 서명이나 notarization이 없는 unsigned ZIP을 게시합니다.
- 지원되는 사용자 설치 절차에서는 압축을 푼 `.app`에 사용자가 자신의 Mac에서 ad hoc 서명을 해야 합니다.
- ad hoc 서명은 Developer ID 서명이나 notarization을 대신하지 않습니다.
- 지원 OS와 strong-blocking 여부는 GitHub Release 페이지와 게이트 보고서에 명시된 범위만 따릅니다.

## 설치

### 1. ZIP 무결성 확인

서명이나 실행 전에 GitHub Release에서 받은 ZIP의 SHA-256을 확인합니다.

```sh
shasum -a 256 HotspotByteFence-VERSION.zip
```

결과가 같은 Release에 게시된 `SHA-256SUMS`와 일치하는지 확인합니다. 일치하지 않으면 앱을 실행하거나 서명하지 말고 해당 Release를 사용하지 않습니다.

### 2. 앱 압축 해제

ZIP을 압축 해제한 뒤 앱을 원하는 위치에 둡니다. 아래 예시는 `/Applications`에 설치한 경우입니다.

```sh
APP="/Applications/HotspotByteFence.app"
```

### 3. 로컬 ad hoc 서명

압축을 푼 앱에 ad hoc 서명을 적용합니다. `-`는 signing identity를 사용하지 않는 ad hoc 서명을 뜻합니다.

```sh
codesign --force --sign - "$APP"
```

릴리스에 중첩된 실행 코드가 포함되어 릴리스 페이지가 별도의 서명 순서를 안내하면 그 안내를 우선합니다. Apple은 복잡한 bundle을 서명할 때 무조건 `--deep`를 사용하는 방식을 권장하지 않습니다.

### 4. 서명 확인

```sh
codesign --verify --deep --strict --verbose=2 "$APP"
```

검증이 실패하면 앱을 실행하지 말고, 해당 Release의 서명 절차와 앱 경로를 다시 확인합니다.

### 5. 첫 실행과 로그인 항목

Finder에서 앱을 열고 macOS가 표시하는 첫 실행 및 로그인 항목 승인 안내를 따릅니다. ad hoc 서명은 Developer ID 신뢰나 notarization을 제공하지 않으므로, macOS가 추가 승인을 요구할 수 있습니다.

`SMAppService` 로그인 실행은 앱이 서명되고 사용자가 승인한 뒤에만 사용할 수 있습니다. 서명 또는 승인이 되지 않으면 앱은 로그인 시 자동으로 시작되지 않을 수 있으며, 앱이 실행 중인 동안에만 측정 또는 보호 상태를 유지할 수 있습니다.

## 해시와 검증 범위

Release의 SHA-256은 서명 전 unsigned ZIP을 확인하는 값입니다. 로컬 ad hoc 서명 뒤에는 앱 bundle과 실행 파일의 서명 상태 및 digest가 달라질 수 있으므로, 서명 후 값을 Release의 원본 asset SHA-256과 비교하지 않습니다.

사용자가 로컬에서 서명한 앱은 원본 GitHub asset에서 파생된 artifact입니다. 해당 앱이 strong-blocking 또는 measurement-capable release 검증을 통과했다고 주장하려면, 같은 서명 절차와 같은 post-signing digest를 사용한 게이트 보고서가 별도로 있어야 합니다.

## 현재 안전성 고지

문서와 SDK의 API 확인만으로는 실제 Wi-Fi 차단, 자동 재연결 억제, preference 복원, 권한 동작, 또는 장시간 counter 연속성이 입증되지 않습니다. 관련 게이트가 통과되기 전에는 strong-blocking을 보장하지 않습니다.

자세한 요구사항과 검증 기준은 [PRD](docs/HotspotByteFence_PRD.md), [기술설계](docs/HotspotByteFence_TechnicalDesign.md), [capability gates](docs/HotspotByteFence_CapabilityGates.md), [검증 추적표](docs/HotspotByteFence_VerificationTraceability.md)를 확인합니다.
