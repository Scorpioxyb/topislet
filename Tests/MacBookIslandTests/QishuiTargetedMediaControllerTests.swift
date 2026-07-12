import Foundation
import Testing
@testable import MacBookIsland

@Test("定向控制只构造 Perl send-client 参数")
func targetedControlUsesPerlClientCommand() {
    let arguments = QishuiTargetedMediaController.commandArguments(
        script: URL(fileURLWithPath: "/tmp/mediaremote-adapter.pl"),
        framework: URL(fileURLWithPath: "/tmp/MediaRemoteAdapter.framework"),
        bundleIdentifier: "com.soda.music",
        command: .nextTrack
    )

    #expect(QishuiTargetedMediaController.perlExecutablePath == "/usr/bin/perl")
    #expect(arguments == [
        "/tmp/mediaremote-adapter.pl",
        "/tmp/MediaRemoteAdapter.framework",
        "send-client",
        "com.soda.music",
        "4"
    ])
    #expect(arguments.allSatisfy { !$0.contains("python") && !$0.hasSuffix(".py") })
}

@Test("外层超时覆盖 client 查找与命令确认预算")
func targetedControlTimeoutCoversAdapterBudget() {
    #expect(QishuiTargetedMediaController.processTimeout > 1.5)
}

@Test("定向控制仅接受成功退出和明确回执")
func targetedControlRequiresExplicitSuccessReceipt() {
    #expect(QishuiTargetedMediaController.didSend(
        terminationStatus: 0,
        standardOutput: "targetedControlSent=true\n"
    ))
    #expect(!QishuiTargetedMediaController.didSend(
        terminationStatus: 0,
        standardOutput: ""
    ))
    #expect(!QishuiTargetedMediaController.didSend(
        terminationStatus: 1,
        standardOutput: "targetedControlSent=true\n"
    ))
}
