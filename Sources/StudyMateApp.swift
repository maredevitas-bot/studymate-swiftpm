import SwiftUI
import SwiftData

@main
struct StudyMateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            School.self,
            Subject.self,
            Material.self,
            QuizSession.self,
            Question.self,
            PlanEntry.self
        ])
    }
}
