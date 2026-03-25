import Foundation
import UIKit

// MARK: - AI Provider Selection
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case claude = "Claude"
    var id: String { rawValue }

    var description: String {
        switch self {
        case .gemini: return "Gemini 2.0 Flash (무료)"
        case .claude: return "Claude Sonnet (유료)"
        }
    }
}

// MARK: - Protocol
protocol AIClient {
    func analyzeImages(_ images: [UIImage], type: MaterialType) async throws -> AnalysisResult
    func generateQuiz(from text: String, count: Int, difficulty: String) async throws -> [GeneratedQuestion]
    func generateStudyPlan(subjects: [(name: String, avgScore: Double?, materialCount: Int)],
                           examDate: Date) async throws -> [StudyPlanItem]
    func summarize(text: String) async throws -> String
}

// MARK: - Factory
struct AIClientFactory {
    static func current() -> AIClient {
        let raw = UserDefaults.standard.string(forKey: "aiProvider") ?? AIProvider.gemini.rawValue
        switch AIProvider(rawValue: raw) ?? .gemini {
        case .claude: return ClaudeAPIClient.shared
        case .gemini: return GeminiAPIClient.shared
        }
    }
}
