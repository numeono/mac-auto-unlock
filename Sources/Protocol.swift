import Foundation
import CoreFoundation

let maximumRequestBytes = 4096

func validatedRequest(_ data: Data) -> [String: Any]? {
    guard data.count <= maximumRequestBytes, data.contains(10),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let command = request["command"] as? String else { return nil }
    let simple: Set<String> = ["status", "setup", "request-permissions", "lock", "pause", "test-cycle", "wake-check"]
    let allowed: Set<String>
    switch command {
    case "begin": allowed = ["command", "seconds"]
    case "renew": allowed = ["command", "seconds", "lease"]
    case "end": allowed = ["command", "lease"]
    default:
        guard simple.contains(command) else { return nil }
        allowed = ["command"]
    }
    guard Set(request.keys).isSubset(of: allowed) else { return nil }
    if let seconds = request["seconds"] {
        guard let n = seconds as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,
              n.doubleValue >= 30, n.doubleValue <= LeaseBook.maximumTTL else { return nil }
    }
    if command == "renew" || command == "end" {
        guard let lease = request["lease"] as? String,
              UUID(uuidString: lease) != nil else { return nil }
    }
    return request
}
