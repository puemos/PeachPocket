import Foundation
import Security
import Darwin

private let serviceName = "local.lidlight.helper"
private let journal = "/Library/PrivilegedHelperTools/local.lidlight.session"

final class Peer: NSObject, LidlightHelperProtocol {
    weak var daemon: Daemon?
    let id = UUID()
    func request(_ command: String, duration: Int, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let daemon = self.daemon else { reply(Data()); return }
            reply(daemon.request(command, duration: duration, owner: self.id))
        }
    }
}

final class Daemon: NSObject, NSXPCListenerDelegate {
    let uid: uid_t
    let requirement: SecRequirement
    var policy = SessionPolicy()
    var owner: UUID?
    var message = "Normal sleep"
    var timer: DispatchSourceTimer?
    var retryRestore = false
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(uid: uid_t, requirement: SecRequirement) {
        self.uid = uid
        self.requirement = requirement
        super.init()
        if FileManager.default.fileExists(atPath: journal) { stop("Recovered interrupted session. Normal sleep restored.") }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        if retryRestore { timer.schedule(deadline: .now(), repeating: .seconds(1)) } else { timer.schedule(deadline: .distantFuture) }
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.retryRestore { self.stop("Normal sleep restored.") }
            if let reason = self.policy.stopReason(now: self.now, lidClosed: PowerSensors.lidClosed) { self.stop(reason) }
        }
        timer.resume()
        self.timer = timer
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { [weak self] in
            guard let self else { exit(0) }
            if self.policy.active || self.retryRestore { self.stop("Helper stopped") }
            exit(0)
        }
        termination.resume()
        terminationSource = termination
    }
    var terminationSource: DispatchSourceSignal?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == uid else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        let peer = Peer()
        peer.daemon = self
        connection.exportedInterface = NSXPCInterface(with: LidlightHelperProtocol.self)
        connection.exportedObject = peer
        let id = peer.id
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.owner == id else { return }
                self.stop("App closed. Normal sleep restored.")
            }
        }
        connection.resume()
        return true
    }

    func setSleepDisabled(_ value: Bool) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-a", "disablesleep", value ? "1" : "0"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit(); return task.terminationStatus == 0 }
        catch { return false }
    }

    func stop(_ reason: String) {
        if setSleepDisabled(false) {
            policy.end()
            owner = nil
            retryRestore = false
            timer?.schedule(deadline: .distantFuture)
            try? FileManager.default.removeItem(atPath: journal)
            message = reason
        } else {
            retryRestore = true
            timer?.schedule(deadline: .now() + 1, repeating: .seconds(1))
            message = "Could not restore sleep; retrying. Recovery: sudo pmset -a disablesleep 0"
        }
    }

    func request(_ command: String, duration: Int, owner: UUID) -> Data {
        switch command {
        case "start":
            if self.owner != nil { message = "A session is already running." }
            else if duration < 0 || duration > 86400 { message = "Invalid timer." }
            else if PowerSensors.lidClosed != false { message = "Open the lid before starting." }
            else if PowerSensors.sleepDisabled != false { message = "Restore normal sleep before starting." }
            else {
                do {
                    try Data("active".utf8).write(to: URL(fileURLWithPath: journal), options: [.atomic])
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal)
                    if setSleepDisabled(true) {
                        _ = policy.begin(now: now, duration: duration)
                        self.owner = owner
                        timer?.schedule(deadline: .now(), repeating: .milliseconds(200))
                        message = "Keep awake is on"
                    } else { stop("Could not enable keep awake.") }
                } catch { message = "Could not create recovery record. Sleep was not changed." }
            }
        case "stop":
            if self.owner == owner { stop("Normal sleep restored.") }
        case "restore":
            if self.owner == nil || self.owner == owner { stop("Normal sleep restored.") }
        case "ping":
            if self.owner == owner { policy.heartbeat(now: now) }
        default: message = "Unsupported request."
        }
        let snapshot = HelperStatus(active: policy.active, disabled: PowerSensors.sleepDisabled, lidClosed: PowerSensors.lidClosed, remaining: policy.remaining(now: now), message: message)
        return (try? JSONEncoder().encode(snapshot)) ?? Data()
    }
}

let args = CommandLine.arguments
if args.count != 3 || getuid() != 0 { exit(1) }
guard let uid = UInt32(args[1]), args[2].count == 40, args[2].allSatisfy({ $0.isHexDigit }) else { exit(1) }
var requirement: SecRequirement?
guard SecRequirementCreateWithString("cdhash H\"\(args[2])\"" as CFString, [], &requirement) == errSecSuccess,
      let requirement else { exit(1) }
let daemon = Daemon(uid: uid, requirement: requirement)
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = daemon
listener.resume()
RunLoop.main.run()
