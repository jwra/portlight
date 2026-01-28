import Foundation

struct DBConnection: Codable, Identifiable, Equatable {
    let name: String
    let instanceConnectionName: String
    let port: Int
    var autoConnect: Bool = false

    var id: String { name }

    var displayPort: String {
        "localhost:\(port)"
    }
}
