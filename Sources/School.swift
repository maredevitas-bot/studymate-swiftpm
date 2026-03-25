import SwiftData
import Foundation

@Model
final class School {
    @Attribute(.unique) var code: String   // 컴시간 학교 코드 (중복 삽입 방지)
    var name: String
    var grade: Int
    var classNum: Int

    init(name: String, code: String, grade: Int, classNum: Int) {
        self.name = name
        self.code = code
        self.grade = grade
        self.classNum = classNum
    }
}
