import Foundation
import UIKit

// MARK: - Errors
enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 설정되지 않았습니다. 설정 탭에서 키를 입력해주세요."
        case .networkError(let e):
            return "네트워크 오류: \(e.localizedDescription)"
        case .invalidResponse(let code, let body):
            return "API 오류 (\(code)): \(body.prefix(200))"
        case .parseError(let s):
            return "응답 파싱 오류: \(s)"
        }
    }
}

// MARK: - Client
actor GeminiAPIClient: AIClient {
    static let shared = GeminiAPIClient()
    private let keychain = KeychainProvider()
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let model = "gemini-2.0-flash"

    // MARK: Image analysis
    func analyzeImages(_ images: [UIImage], type: MaterialType) async throws -> AnalysisResult {
        let isNote = type == .note
        let prompt = """
        이 \(isNote ? "손필기 노트" : "수업 PPT 슬라이드들")의 핵심 내용을 분석해주세요.
        다음 JSON 형식으로만 응답해주세요 (마크다운 코드블록 없이 순수 JSON만):
        {
          "extractedText": "전체 텍스트 내용",
          "summary": "핵심 내용 요약 (3~5문장)",
          "highlights": ["핵심 키워드1", "핵심 키워드2", "핵심 키워드3", "키워드4", "키워드5"]
        }
        """
        let quality = isNote ? 0.9 : 0.7
        var parts: [[String: Any]] = []
        for image in images.prefix(10) {
            guard let base64 = image.jpegData(compressionQuality: quality)?.base64EncodedString() else { continue }
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": base64]])
        }
        parts.append(["text": prompt])

        let responseText = try await callGemini(parts: parts, maxTokens: 2000)
        return try parseJSON(responseText, as: AnalysisResult.self)
    }

    // MARK: Quiz generation
    func generateQuiz(from text: String,
                      count: Int = 3,
                      difficulty: String = "보통") async throws -> [GeneratedQuestion] {
        let prompt = """
        다음 수업 내용을 바탕으로 \(count)개의 서술형 문제를 만들어주세요.
        난이도: \(difficulty) / 언어: 한국어

        수업 내용:
        \(text.prefix(3000))

        다음 JSON 배열 형식으로만 응답해주세요 (마크다운 코드블록 없이):
        [
          {
            "body": "문제 내용",
            "scoringCriteria": "채점 기준 (핵심 키워드, 내용 요소)",
            "modelAnswer": "모범 답안"
          }
        ]
        """
        let responseText = try await callGemini(parts: [["text": prompt]], maxTokens: 3000)
        return try parseJSON(responseText, as: [GeneratedQuestion].self)
    }

    // MARK: Study plan generation
    func generateStudyPlan(
        subjects: [(name: String, avgScore: Double?, materialCount: Int)],
        examDate: Date
    ) async throws -> [StudyPlanItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let examStr = formatter.string(from: examDate)
        let today = formatter.string(from: Date())
        let subjectInfo = subjects.map { s in
            "- \(s.name): 평균점수 \(s.avgScore.map { String(format: "%.0f", $0) } ?? "없음"), 자료 \(s.materialCount)개"
        }.joined(separator: "\n")

        let prompt = """
        오늘(\(today))부터 시험일(\(examStr))까지의 복습 일정을 만들어주세요.
        취약한 과목(점수 낮음)을 우선 배치해주세요. 주말 제외.

        과목 현황:
        \(subjectInfo)

        다음 JSON 배열로만 응답해주세요 (마크다운 코드블록 없이):
        [{"date": "yyyy-MM-dd", "subjectName": "과목명", "topic": "복습 내용"}]
        """
        let responseText = try await callGemini(parts: [["text": prompt]], maxTokens: 2000)
        return try parseJSON(responseText, as: [StudyPlanItem].self)
    }

    // MARK: Summarize
    func summarize(text: String) async throws -> String {
        let prompt = "다음 내용을 3문장으로 간결하게 요약해주세요:\n\(text.prefix(2000))"
        return try await callGemini(parts: [["text": prompt]], maxTokens: 500)
    }

    // MARK: - Private HTTP layer
    private func callGemini(parts: [[String: Any]], maxTokens: Int) async throws -> String {
        guard let apiKey = keychain.loadGeminiKey() else {
            throw GeminiError.missingAPIKey
        }
        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.parseError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.7
            ]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GeminiError.networkError(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.parseError("Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw GeminiError.invalidResponse(http.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw GeminiError.parseError("Unexpected Gemini response structure")
        }
        return text
    }

    private func parseJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        let cleaned = text
            .replacingOccurrences(of: #"```json\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw GeminiError.parseError("UTF-8 conversion failed")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GeminiError.parseError("JSON decode failed: \(error)")
        }
    }
}
