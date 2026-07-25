import Foundation
import Testing
@testable import MacBookIsland

@MainActor
private final class LoginItemServiceStub: LoginItemServicing {
    var registrationStatus: LoginItemRegistrationStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: LoginItemRegistrationStatus) {
        registrationStatus = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        registrationStatus = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        registrationStatus = .disabled
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

@Test("登录项状态以系统服务为唯一事实来源")
@MainActor
func loginItemStatusComesFromSystemService() {
    let service = LoginItemServiceStub(status: .requiresApproval)
    let settings = LoginItemSettings(service: service)

    #expect(settings.status == .requiresApproval)
    #expect(settings.isRequested)

    service.registrationStatus = .enabled
    settings.refresh()

    #expect(settings.status == .enabled)
    #expect(settings.isRequested)
    #expect(settings.status.diagnosticCode == "enabled")
}

@Test("登录时启动开关注册并注销主 App")
@MainActor
func loginItemToggleRegistersAndUnregisters() {
    let service = LoginItemServiceStub(status: .disabled)
    let settings = LoginItemSettings(service: service)

    settings.setEnabled(true)
    #expect(service.registerCallCount == 1)
    #expect(settings.status == .enabled)

    settings.setEnabled(false)
    #expect(service.unregisterCallCount == 1)
    #expect(settings.status == .disabled)
}

@Test("登录项操作失败后恢复真实系统状态并显示错误")
@MainActor
func loginItemFailureRestoresSystemStatus() {
    let service = LoginItemServiceStub(status: .disabled)
    service.registerError = NSError(
        domain: "TopIsletTests.LoginItem",
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "测试注册失败"]
    )
    let settings = LoginItemSettings(service: service)

    settings.setEnabled(true)

    #expect(settings.status == .disabled)
    #expect(!settings.isRequested)
    #expect(settings.errorMessage?.contains("测试注册失败") == true)
}

@Test("等待系统批准的登录项可以由用户关闭")
@MainActor
func pendingLoginItemCanBeDisabled() {
    let service = LoginItemServiceStub(status: .requiresApproval)
    let settings = LoginItemSettings(service: service)

    settings.setEnabled(false)

    #expect(service.unregisterCallCount == 1)
    #expect(settings.status == .disabled)
}

@Test("登录项设置可打开 macOS 登录项面板")
@MainActor
func loginItemCanOpenSystemSettings() {
    let service = LoginItemServiceStub(status: .requiresApproval)
    let settings = LoginItemSettings(service: service)

    settings.openSystemSettings()

    #expect(service.openSystemSettingsCallCount == 1)
}
