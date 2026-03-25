import SwiftData
import Foundation

@Model
final class Subject {
    var name: String
    var teacher: String
    var colorHex: String
    @Relationship(deleteRule: .cascade, inverse: \Material.subject)
    var materials: [Material] = []
    @Relationship(deleteRule: .cascade, inverse: \QuizSession.subject)
    var quizSessions: [QuizSession] = []
    @Relationship(deleteRule: .cascade, inverse: \NoteBook.subject)
    var notebooks: [NoteBook] = []

    init(name: String, teacher: String, colorHex: String = "#4A90D9") {
        self.name = name
        self.teacher = teacher
        self.colorHex = colorHex
    }

    var displayTitle: String { "\(name) — \(teacher)" }
    var averageScore: Double? {
        let scores = quizSessions.compactMap(\.scorePercent)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
