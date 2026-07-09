import Foundation

final class QishuiMediaRemoteClientController {
    private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    private let qishuiBundleIdentifier = "com.soda.music"
    private let callbackQueue = DispatchQueue(label: "MacBookIsland.QishuiMediaRemoteClient", qos: .userInitiated)
    private let fetchTimeout: DispatchTimeInterval = .seconds(1)

    private var handle: UnsafeMutableRawPointer?
    private var didRegisterNotifications = false

    private typealias ClientsCallback = @convention(block) (CFArray?) -> Void
    private typealias GetNowPlayingClients = @convention(c) (DispatchQueue, @escaping ClientsCallback) -> Void
    private typealias RegisterForNowPlayingNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias SetWantsNowPlayingNotifications = @convention(c) (Bool) -> Void
    private typealias GetLocalOrigin = @convention(c) () -> UnsafeRawPointer?
    private typealias ClientGetString = @convention(c) (UnsafeRawPointer?) -> Unmanaged<CFString>?
    private typealias SendCommandCallback = @convention(block) (CFDictionary?) -> Void
    private typealias SendCommandToClient = @convention(c) (
        UInt32,
        CFDictionary?,
        UnsafeRawPointer?,
        UnsafeRawPointer?,
        DispatchQueue,
        @escaping SendCommandCallback
    ) -> Void

    @discardableResult
    func post(_ command: MusicControlCommand) -> Bool {
        guard loadFramework() else { return false }
        registerForMediaRemoteNotificationsIfNeeded()

        guard let origin = localOrigin(),
              let sendCommand = symbol("MRMediaRemoteSendCommandToClient", as: SendCommandToClient.self) else {
            return false
        }

        guard let clientPointer = qishuiNowPlayingClientPointer() else {
            return false
        }

        sendCommand(command.mediaRemoteCommandID, nil, origin, clientPointer, callbackQueue) { _ in }
        return true
    }

    func clientDiagnostics() -> [String] {
        guard loadFramework() else { return ["mediaRemoteClients=unavailable"] }
        registerForMediaRemoteNotificationsIfNeeded()

        guard let getClients = symbol("MRMediaRemoteGetNowPlayingClients", as: GetNowPlayingClients.self) else {
            return ["mediaRemoteClients=unavailable"]
        }

        let semaphore = DispatchSemaphore(value: 0)
        var clients: [Any] = []
        getClients(callbackQueue) { result in
            clients = (result as? [Any]) ?? []
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + fetchTimeout) == .success else {
            return ["mediaRemoteClients=timeout"]
        }

        var lines = ["mediaRemoteClients=\(clients.count)"]
        for (index, client) in clients.enumerated() {
            let clientObject = client as AnyObject
            let pointer = Unmanaged.passUnretained(clientObject).toOpaque()
            let bundle = string(from: "MRNowPlayingClientGetBundleIdentifier", pointer: pointer) ?? ""
            let parent = string(from: "MRNowPlayingClientGetParentAppBundleIdentifier", pointer: pointer) ?? ""
            let displayName = string(from: "MRNowPlayingClientGetDisplayName", pointer: pointer) ?? ""
            lines.append("client[\(index)] bundle=\(bundle) parent=\(parent) name=\(displayName)")
        }
        return lines
    }

    private func qishuiNowPlayingClientPointer() -> UnsafeRawPointer? {
        registerForMediaRemoteNotificationsIfNeeded()

        guard let getClients = symbol("MRMediaRemoteGetNowPlayingClients", as: GetNowPlayingClients.self) else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var clients: [Any] = []
        getClients(callbackQueue) { result in
            clients = (result as? [Any]) ?? []
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + fetchTimeout) == .success else {
            return nil
        }

        for client in clients {
            let clientObject = client as AnyObject
            let pointer = Unmanaged.passUnretained(clientObject).toOpaque()
            if string(from: "MRNowPlayingClientGetBundleIdentifier", pointer: pointer) == qishuiBundleIdentifier
                || string(from: "MRNowPlayingClientGetParentAppBundleIdentifier", pointer: pointer) == qishuiBundleIdentifier {
                return UnsafeRawPointer(pointer)
            }
        }
        return nil
    }

    private func localOrigin() -> UnsafeRawPointer? {
        guard let getOrigin = symbol("MRMediaRemoteGetLocalOrigin", as: GetLocalOrigin.self) else {
            return nil
        }
        return getOrigin()
    }

    private func registerForMediaRemoteNotificationsIfNeeded() {
        guard !didRegisterNotifications else { return }
        symbol(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            as: RegisterForNowPlayingNotifications.self
        )?(callbackQueue)
        symbol("MRMediaRemoteSetWantsNowPlayingNotifications", as: SetWantsNowPlayingNotifications.self)?(true)
        didRegisterNotifications = true
    }

    private func string(from symbolName: String, pointer: UnsafeRawPointer?) -> String? {
        guard let getter = symbol(symbolName, as: ClientGetString.self),
              let value = getter(pointer)?.takeUnretainedValue() else {
            return nil
        }
        return (value as String).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFramework() -> Bool {
        if handle != nil { return true }
        handle = dlopen(frameworkPath, RTLD_NOW)
        return handle != nil
    }

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle,
              let rawSymbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(rawSymbol, to: T.self)
    }
}
