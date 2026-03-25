import SwiftData
import Foundation

@Model
final class PlanEntry {
    var date: Date
    // Subject 삭제 시에도 보존되도록 이름을 복사. Subject.name 변경 시 이 값은 갱신되지 않음 (의도적 설계).
    var subjectName: String
    var topic: String
    var isCompleted: Bool
    var isAIGenerated: Bool
    var note: String

    init(date: Date, subjectName: String, topic: String, isAIGenerated: Bool = false) {
        self.date = date
        self.subjectName = subjectName
        self.topic = topic
        self.isCompleted = false
        self.isAIGenerated = isAIGenerated
        self.note = ""
    }
}
