import Foundation

struct Request: Decodable {
    let id: Int
    let command: String
    let duration: Int
}
struct Response: Encodable {
    let id: Int
    let status: HelperStatus?
}
let connection = NSXPCConnection(machServiceName: "local.lidlight.helper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: LidlightHelperProtocol.self)
connection.resume()
func respond(_ id: Int, _ status: HelperStatus?) {
    guard var data = try? JSONEncoder().encode(Response(id: id, status: status)) else { return }
    data.append(10)
    try? FileHandle.standardOutput.write(contentsOf: data)
}
var buffer = Data()
FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    DispatchQueue.main.async {
        if data.isEmpty { connection.invalidate(); exit(0) }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            guard let request = try? JSONDecoder().decode(Request.self, from: line) else { continue }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                DispatchQueue.main.async { respond(request.id, nil) }
            } as? LidlightHelperProtocol
            guard let proxy else { respond(request.id, nil); continue }
            proxy.request(request.command, duration: request.duration) { data in
                let status = try? JSONDecoder().decode(HelperStatus.self, from: data)
                DispatchQueue.main.async { respond(request.id, status) }
            }
        }
    }
}
RunLoop.main.run()
