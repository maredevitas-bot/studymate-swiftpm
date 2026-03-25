import SwiftUI
import SwiftData

@main
struct StudyMateApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([
            School.self, Subject.self, Material.self,
            QuizSession.self, Question.self, PlanEntry.self,
            NoteBook.self, NotePage.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 스키마 변경으로 마이그레이션 실패 시 기존 스토어 삭제 후 재생성
            if let url = config.url {
                try? FileManager.default.removeItem(at: url)
                let walURL = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + "-wal")
                let shmURL = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + "-shm")
                try? FileManager.default.removeItem(at: walURL)
                try? FileManager.default.removeItem(at: shmURL)
            }
            container = try! ModelContainer(for: schema, configurations: [config])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
