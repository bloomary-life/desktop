import Foundation

struct Draft: Identifiable, Codable, Equatable {
    let id: UUID
    var body: String
    var imageData: Data?
    var imageFilename: String?
    var imageMimeType: String?
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), body: String, imageData: Data? = nil, imageFilename: String? = nil, imageMimeType: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.body = body
        self.imageData = imageData
        self.imageFilename = imageFilename
        self.imageMimeType = imageMimeType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var title: String {
        body
            .split(separator: "\n")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(72)
            .description
        ?? "Untitled draft"
    }
}
