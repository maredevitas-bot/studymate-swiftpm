import SwiftData
import Foundation

@Model
final class QuizSession {
    var createdAt: Date
    var completedAt: Date?
    var scorePercent: Double?   // 사용자 자가 평가 (0~100)
    var totalSeconds: Int = 0   // 전체 퀴즈 소요 시간 (초)
    @Relationship(deleteRule: .cascade, inverse: \Question.session)
    var questions: [Question] = []
    var subject: Subject?   // inverse declared on Subject.quizSessions

    init(subject: Subject? = nil) {
        self.createdAt = Date()
        self.subject = subject
    }
}

@Model
final class Question {
    var body: String
    var userAnswer: String
    var scoringCriteria: String
    var modelAnswer: String
    var displayOrder: Int
    var elapsedSeconds: Int = 0  // 해당 문제 풀이 소요 시간 (초)
    var session: QuizSession?   // inverse declared on QuizSession.questions

    init(body: String, scoringCriteria: String, modelAnswer: String, displayOrder: Int) {
        self.body = body
        self.userAnswer = ""
        self.scoringCriteria = scoringCriteria
        self.modelAnswer = modelAnswer
        self.displayOrder = displayOrder
    }
}
