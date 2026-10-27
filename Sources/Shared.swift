import Foundation
import IOKit

@objc protocol LidlightHelperProtocol {
    func request(_ command: String, duration: Int, reply: @escaping (Data) -> Void)
}

struct HelperStatus: Codable {
    var active = false
    var disabled: Bool?
    var lidClosed: Bool?
    var remaining: Int?
    var message = "Normal sleep"
    var version = 2
}

enum PowerSensors {
    static func property(_ name: String) -> Bool? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }
    static var lidClosed: Bool? { property("AppleClamshellState") }
    static var sleepDisabled: Bool? { property("SleepDisabled") }
}
