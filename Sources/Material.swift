import SwiftData
import Foundation

enum MaterialType: String, Codable {
    case ppt, note
}

@Model
final class Material {
    var type: MaterialType
    var title: String
    // File paths stored in Documents/materials/UUID.jpg — not inline Data
    @Attribute(.externalStorage) var imagePaths: [String]
    var extractedText: String
    var summary: String
    @Attribute(.externalStorage) var highlights: [String]
    @Attribute(.externalStorage) var drawingData: Data?
    var createdAt: Date
    var subject: Subject?   // inverse declared on Subject.materials

    init(type: MaterialType, title: String) {
        self.type = type
        self.title = title
        self.imagePaths = []
        self.extractedText = ""
        self.summary = ""
        self.highlights = []
        self.drawingData = nil
        self.createdAt = Date()
    }
}
