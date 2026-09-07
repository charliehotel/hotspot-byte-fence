import SwiftUI
import HotspotByteFenceCore

@MainActor
final class ProfileManagementState: ObservableObject {
    @Published var profiles: [ProfileRecord] = []
    @Published var connectedID: UUID?
    @Published var selection: UUID?
    @Published var tab = 0
    @Published var busy = false
    @Published var errorMessage: String?
    var engine: RuntimeEngine?

    func update(store: StoreEnvelopeV1, snapshot: RuntimeSnapshotV1) {
        profiles = store.profiles
        connectedID = snapshot.connectedProfileID
        if let selection, !profiles.contains(where: { $0.profileID == selection }) { self.selection = nil }
    }

    func move(from offsets: IndexSet, to destination: Int, localization: Localization) {
        guard !busy, let engine else { return }
        var reordered = profiles
        reordered.move(fromOffsets: offsets, toOffset: destination)
        let ids = reordered.map(\.profileID)
        perform(localization: localization) { try await engine.reorderProfiles(ids: ids) }
    }

    func delete(id: UUID, localization: Localization) {
        guard !busy, let engine else { return }
        perform(localization: localization) { try await engine.deleteProfile(id: id) }
    }

    private func perform(localization: Localization, operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await operation()
            } catch {
                let korean = localization.effectiveLanguage == .korean
                switch error as? ProfileManagementError {
                case .restorationPending:
                    errorMessage = korean ? "Wi-Fi 설정 복원 작업이 남아 있어 삭제할 수 없습니다. 복원을 완료한 뒤 다시 시도해 주세요." : "This profile has pending Wi-Fi restoration work. Complete restoration before deleting it."
                case .staleProfileList:
                    errorMessage = korean ? "프로필 목록이 변경되었습니다. 갱신된 목록에서 다시 시도해 주세요." : "The profile list changed. Try again using the refreshed list."
                case .recoveryRequired:
                    errorMessage = korean ? "저장 데이터 복구 또는 시간 조정 확인이 필요합니다. 문제를 해결한 뒤 다시 시도해 주세요." : "Resolve the data recovery or time adjustment issue before trying again."
                default:
                    errorMessage = korean ? "변경 내용을 저장하지 못했습니다. 저장 상태를 확인해 주세요." : "Changes could not be saved. Check the storage status."
                }
            }
            if let engine {
                let store = await engine.currentStore()
                let snapshot = await engine.currentSnapshot()
                update(store: store, snapshot: snapshot)
            }
        }
    }
}

struct ProfileManagementView: View {
    @ObservedObject var state: ProfileManagementState
    let localization: Localization
    let edit: (UUID) -> Void
    let register: () -> Void
    @State private var deletingProfile: ProfileRecord?
    private var korean: Bool { localization.effectiveLanguage == .korean }
    private var selectedIndex: Int? { state.profiles.firstIndex { $0.profileID == state.selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(korean ? "프로필 관리" : "Manage Profiles").font(.title2.bold())
            Text(korean ? "드래그하거나 위·아래 버튼으로 순서를 바꾸세요. 메뉴에도 같은 순서로 표시됩니다." : "Drag profiles or use the arrow buttons to reorder them. The menu uses the same order.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(selection: $state.selection) {
                ForEach(state.profiles, id: \.profileID) { profile in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.aliasNFC).fontWeight(.semibold)
                                if profile.profileID == state.connectedID {
                                    Text(korean ? "연결됨" : "Connected").font(.caption).foregroundStyle(.green)
                                }
                            }
                            Text(networkName(profile)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(profile.limitBytes.rawValue >= ProfileRecord.maximumLimitBytes
                             ? localization.unlimitedLabel : UsageFormatter.formatGB(profile.limitBytes))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .tag(profile.profileID)
                }
                .onMove { state.move(from: $0, to: $1, localization: localization) }
            }
            .listStyle(.inset)
            .overlay {
                if state.profiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2").font(.largeTitle).foregroundStyle(.secondary)
                        Text(localization.menuNoProfilesRegistered).foregroundStyle(.secondary)
                        Button(localization.menuRegisterProfileTitle, action: register)
                    }
                }
            }
            .disabled(state.busy)
            HStack(spacing: 10) {
                Button { moveSelection(up: true) } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel(korean ? "위로 이동" : "Move Up")
                    .disabled(state.busy || selectedIndex == nil || selectedIndex == 0)
                Button { moveSelection(up: false) } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel(korean ? "아래로 이동" : "Move Down")
                    .disabled(state.busy || selectedIndex == nil || selectedIndex == state.profiles.count - 1)
                Spacer()
                if state.busy { ProgressView().controlSize(.small) }
                Button(korean ? "편집…" : "Edit…") { if let id = state.selection { edit(id) } }
                    .disabled(state.busy || selectedIndex == nil)
                Button(korean ? "삭제…" : "Delete…", role: .destructive) {
                    if let index = selectedIndex { deletingProfile = state.profiles[index] }
                }
                .disabled(state.busy || selectedIndex == nil)
            }
        }
        .padding(24)
        .alert(korean ? "프로필을 삭제하시겠습니까?" : "Delete this profile?", isPresented: Binding(
            get: { deletingProfile != nil }, set: { if !$0 { deletingProfile = nil } }
        ), presenting: deletingProfile) { profile in
            Button(localization.cancel, role: .cancel) { deletingProfile = nil }.keyboardShortcut(.defaultAction)
            Button(korean ? "삭제" : "Delete", role: .destructive) {
                state.delete(id: profile.profileID, localization: localization)
                deletingProfile = nil
            }
        } message: { profile in
            Text(korean
                 ? "‘\(profile.aliasNFC)’ 프로필의 설정과 측정된 사용량을 삭제합니다. 되돌릴 수 없습니다. 이 프로필의 모니터링과 자동 차단도 중단됩니다. Mac에 저장된 Wi-Fi 설정은 유지됩니다."
                 : "The settings and measured usage for ‘\(profile.aliasNFC)’ will be deleted. This cannot be undone. Monitoring and automatic blocking for this profile will stop. Saved macOS Wi-Fi settings will remain unchanged.")
        }
        .alert(korean ? "프로필 변경 실패" : "Profile Change Failed", isPresented: Binding(
            get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button(korean ? "확인" : "OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
    }

    private func moveSelection(up: Bool) {
        guard let index = selectedIndex else { return }
        state.move(from: IndexSet(integer: index), to: up ? index - 1 : index + 2, localization: localization)
    }

    private func networkName(_ profile: ProfileRecord) -> String {
        guard let hex = profile.ssidHex, let ssid = try? SSID(hex: hex) else {
            return korean ? "등록된 네트워크 없음" : "No registered network"
        }
        return String(bytes: ssid.bytes, encoding: .utf8) ?? hex
    }
}
