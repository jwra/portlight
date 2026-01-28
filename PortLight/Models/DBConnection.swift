import Foundation

struct DBConnection: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let name: String
    let instanceConnectionName: String
    let port: Int
    var autoConnect: Bool = false

    var displayPort: String {
        "localhost:\(port)"
    }
}
