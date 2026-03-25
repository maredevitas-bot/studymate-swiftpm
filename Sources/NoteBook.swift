import SwiftData
import Foundation

@Model
final class NoteBook {
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var subject: Subject?
    @Relationship(deleteRule: .cascade, inverse: \NotePage.notebook)
    var pages: [NotePage] = []

    init(title: String, subject: Subject? = nil) {
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.subject = subject
    }

    var sortedPages: [NotePage] {
        pages.sorted { $0.pageIndex < $1.pageIndex }
    }
}

@Model
final class NotePage {
    var pageIndex: Int
    /// PKDrawing.dataRepresentation() 로 직렬화된 필기 데이터
    @Attribute(.externalStorage) var drawingData: Data
    var notebook: NoteBook?

    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        self.drawingData = Data()
    }
}
