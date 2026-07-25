import Foundation
import ServiceManagement

enum LoginItemRegistrationStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }

    var title: String {
        switch self {
        case .disabled:
            return "未开启"
        case .enabled:
            return "已开启"
        case .requiresApproval:
            return "等待系统批准"
        case .unavailable:
            return "当前安装不可用"
        }
    }

    var diagnosticCode: String {
        switch self {
        case .disabled:
            return "disabled"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requiresApproval"
        case .unavailable:
            return "unavailable"
        }
    }
}

@MainActor
protocol LoginItemServicing {
    var registrationStatus: LoginItemRegistrationStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
struct SystemLoginItemService: LoginItemServicing {
    var registrationStatus: LoginItemRegistrationStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginItemSettings: ObservableObject {
    @Published private(set) var status: LoginItemRegistrationStatus
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let service: any LoginItemServicing

    init(service: any LoginItemServicing = SystemLoginItemService()) {
        self.service = service
        status = service.registrationStatus
    }

    var isRequested: Bool {
        status.isRequested
    }

    func refresh() {
        status = service.registrationStatus
        if status == .enabled || status == .disabled {
            errorMessage = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }

        refresh()
        guard enabled != status.isRequested else { return }

        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            status = service.registrationStatus
        } catch {
            status = service.registrationStatus
            errorMessage = Self.userFacingError(for: error, enabling: enabled)
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    private static func userFacingError(for error: Error, enabling: Bool) -> String {
        let action = enabling ? "开启" : "关闭"
        let detail = (error as NSError).localizedDescription
        return "无法\(action)登录时自动启动：\(detail)"
    }
}
