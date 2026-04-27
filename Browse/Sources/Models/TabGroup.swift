import Foundation

struct TabGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCollapsed: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Folder",
        isCollapsed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }
}
