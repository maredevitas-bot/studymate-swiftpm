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
    /// 텍스트로만 요약 + 키워드 추출 (PDF OCR 결과 처리용, 이미지 없음)
    func summarizeText(_ text: String) async throws -> AnalysisResult
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
