import AppKit
import CryptoKit
import Security

@MainActor final class HelperClient {
  private struct Request: Encodable {
    let id: Int
    let command: String
    let duration: Int
  }
  private struct Response: Decodable {
    let id: Int
    let status: HelperStatus?
  }
  private var process: Process?
  private var input: FileHandle?
  private var pending: [Int: (HelperStatus?) -> Void] = [:]
  private var sequence = 0
  private var buffer = Data()

  func disconnect() {
    input?.closeFile()
    input = nil
    if process?.isRunning == true { process?.terminate() }
    process = nil
    buffer = Data()
    let callbacks = Array(pending.values)
    pending.removeAll()
    for callback in callbacks { callback(nil) }
  }
  func request(_ command: String, duration: Int = 0, completion: @escaping (HelperStatus?) -> Void)
  {
    if process == nil {
      guard let binary = Bundle.main.url(forResource: "PeachPocketBridge", withExtension: nil)
      else {
        completion(nil)
        return
      }
      let task = Process()
      let stdin = Pipe()
      let stdout = Pipe()
      task.executableURL = binary
      task.standardInput = stdin
      task.standardOutput = stdout
      task.standardError = FileHandle.nullDevice
      stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
        let data = handle.availableData
        if data.isEmpty { handle.readabilityHandler = nil }
        Task { @MainActor in self?.received(data) }
      }
      task.terminationHandler = { [weak self] _ in
        Task { @MainActor in
          guard self?.process === task else { return }
          self?.disconnect()
        }
      }
      do {
        try task.run()
        process = task
        input = stdin.fileHandleForWriting
      } catch {
        completion(nil)
        return
      }
    }
    sequence += 1
    let id = sequence
    pending[id] = completion
    do {
      var data = try JSONEncoder().encode(Request(id: id, command: command, duration: duration))
      data.append(10)
      try input?.write(contentsOf: data)
    } catch { pending.removeValue(forKey: id)?(nil) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.pending.removeValue(forKey: id)?(nil)
    }
  }
  private func received(_ data: Data) {
    buffer.append(data)
    var unavailable = false
    while let end = buffer.firstIndex(of: 10) {
      let line = Data(buffer[..<end])
      buffer.removeSubrange(...end)
      guard let response = try? JSONDecoder().decode(Response.self, from: line) else { continue }
      if response.status == nil { unavailable = true }
      pending.removeValue(forKey: response.id)?(response.status)
    }
    if unavailable { disconnect() }
  }
}

@MainActor enum HelperInstaller {
  static let binary = "/Library/PrivilegedHelperTools/local.lidlight.helper"
  static let plist = "/Library/LaunchDaemons/local.lidlight.helper.plist"
  static var installed: Bool { FileManager.default.fileExists(atPath: binary) }

  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
  static func appleQuote(_ value: String) -> String {
    "\""
      + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"", with: "\\\""
      ).replacingOccurrences(of: "\n", with: "\\n") + "\""
  }
  private static var package: URL?
  private static var builder: Process?

  private static func bridgeHash() throws -> String {
    var code: SecStaticCode?
    guard let bridge = Bundle.main.url(forResource: "PeachPocketBridge", withExtension: nil),
      SecStaticCodeCreateWithPath(bridge as CFURL, [], &code) == errSecSuccess, let code
    else { throw InstallerError.signature }
    var info: CFDictionary?
    guard
      SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        == errSecSuccess,
      let values = info as? [String: Any], let hash = values[kSecCodeInfoUnique as String] as? Data
    else { throw InstallerError.signature }
    let result = hash.map { String(format: "%02x", $0) }.joined()
    guard result.count == 40 else { throw InstallerError.signature }
    return result
  }
  static var isCurrentInstall: Bool {
    guard let digestURL = Bundle.main.url(forResource: "HelperSHA256", withExtension: "txt"),
      let expected = try? String(contentsOf: digestURL, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines),
      let binaryData = try? Data(contentsOf: URL(fileURLWithPath: binary)),
      let plistData = try? Data(contentsOf: URL(fileURLWithPath: plist)),
      let values = try? PropertyListSerialization.propertyList(from: plistData, format: nil)
        as? [String: Any],
      let args = values["ProgramArguments"] as? [String], args.count == 3,
      let hash = try? bridgeHash()
    else { return false }
    return SHA256.hash(data: binaryData).map { String(format: "%02x", $0) }.joined() == expected
      && args[1] == String(getuid()) && args[2] == hash
  }
  static func reopenSetup() {
    if let package { NSWorkspace.shared.open(package) }
  }
  static func install(scriptDestination: URL? = nil, completion: @escaping (String?) -> Void) {
    do {
      guard let helper = Bundle.main.url(forResource: "PeachPocketHelper", withExtension: nil),
        let digestURL = Bundle.main.url(forResource: "HelperSHA256", withExtension: "txt")
      else { throw InstallerError.missing }
      let digest = try String(contentsOf: digestURL, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else {
        throw InstallerError.missing
      }
      let hash = try bridgeHash()
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "PeachPocketSetup-" + UUID().uuidString)
      let root = folder.appendingPathComponent("payload")
      let tools = root.appendingPathComponent("Library/PrivilegedHelperTools")
      let daemons = root.appendingPathComponent("Library/LaunchDaemons")
      let scripts = folder.appendingPathComponent("scripts")
      for directory in [tools, daemons, scripts] {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
      }
      try FileManager.default.copyItem(
        at: helper, to: tools.appendingPathComponent("local.lidlight.helper"))
      let values: [String: Any] = [
        "Label": "local.lidlight.helper",
        "ProgramArguments": [binary, String(getuid()), hash],
        "MachServices": ["local.lidlight.helper": true],
        "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 2,
      ]
      try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(
        to: daemons.appendingPathComponent("local.lidlight.helper.plist"))
      let preinstall =
        "#!/bin/sh\nset -eu\n/bin/launchctl bootout system/local.lidlight.helper 2>/dev/null || true\n"
      let postinstall = """
        #!/bin/sh
        set -eu
        actual=$(/usr/bin/shasum -a 256 \(quote(binary)) | /usr/bin/awk '{print $1}')
        [ "$actual" = \(quote(digest)) ] || exit 1
        /usr/sbin/chown root:wheel \(quote(binary)) \(quote(plist))
        /bin/chmod 755 \(quote(binary))
        /bin/chmod 644 \(quote(plist))
        /usr/bin/codesign --verify --strict \(quote(binary))
        /bin/launchctl bootstrap system \(quote(plist))

        """
      try preinstall.write(
        to: scripts.appendingPathComponent("preinstall"), atomically: true, encoding: .utf8)
      try postinstall.write(
        to: scripts.appendingPathComponent("postinstall"), atomically: true, encoding: .utf8)
      for name in ["preinstall", "postinstall"] {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: scripts.appendingPathComponent(name).path)
      }
      if let scriptDestination {
        try postinstall.write(to: scriptDestination, atomically: true, encoding: .utf8)
      }
      let package =
        scriptDestination?.deletingLastPathComponent().appendingPathComponent(
          "PeachPocketSetup.pkg")
        ?? folder.appendingPathComponent("PeachPocketSetup.pkg")
      let task = Process()
      let errors = Pipe()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/pkgbuild")
      task.arguments = [
        "--root", root.path, "--scripts", scripts.path, "--identifier", "local.lidlight.helper",
        "--version", "0.4.0", "--install-location", "/", "--ownership", "recommended", package.path,
      ]
      task.standardOutput = FileHandle.nullDevice
      task.standardError = errors
      task.terminationHandler = { task in
        let error = String(
          decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        Task { @MainActor in
          builder = nil
          guard task.terminationStatus == 0 else {
            completion("Could not prepare installer: " + error)
            return
          }
          self.package = package
          if scriptDestination != nil {
            completion(nil)
          } else {
            completion(NSWorkspace.shared.open(package) ? nil : "Could not open macOS Installer.")
          }
        }
      }
      builder = task
      try task.run()
    } catch {
      builder = nil
      completion(error.localizedDescription)
    }
  }

  static func uninstall(completion: @escaping (String?) -> Void) {
    let command = """
      set -eu
      /bin/launchctl bootout system/local.lidlight.helper 2>/dev/null || true
      if [ -e /Library/PrivilegedHelperTools/local.lidlight.session ]; then
          /usr/bin/pmset -a disablesleep 0
          /bin/rm -f /Library/PrivilegedHelperTools/local.lidlight.session
      fi
      /bin/rm -f \(quote(binary)) \(quote(plist))
      """
    authorize(command, completion: completion)
  }

  private static func authorize(_ command: String, completion: @escaping (String?) -> Void) {
    let task = Process()
    let errors = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = [
      "-e", "with timeout of 300 seconds", "-e",
      "do shell script \(appleQuote(command)) with administrator privileges", "-e", "end timeout",
    ]
    task.standardError = errors
    task.standardOutput = FileHandle.nullDevice
    task.terminationHandler = { task in
      let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      Task { @MainActor in
        completion(
          task.terminationStatus == 0
            ? nil
            : error.contains("-128")
              ? "Setup cancelled. Nothing was enabled."
              : "Helper setup failed: " + error.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }
    do { try task.run() } catch { completion(error.localizedDescription) }
  }
  private enum InstallerError: LocalizedError {
    case missing, signature
    var errorDescription: String? {
      switch self {
      case .missing: return "Helper is missing or damaged. Rebuild PeachPocket."
      case .signature: return "Could not verify this build’s signature. Rebuild PeachPocket."
      }
    }
  }
}
