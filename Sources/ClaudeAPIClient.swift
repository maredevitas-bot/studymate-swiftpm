import Foundation
import UIKit

// MARK: - Response Types

struct AnalysisResult: Decodable {
    let extractedText: String
    let summary: String
    let highlights: [String]
}

struct GeneratedQuestion: Decodable {
    let body: String
    let scoringCriteria: String
    let modelAnswer: String
}

struct StudyPlanItem: Decodable {
    let date: String          // "yyyy-MM-dd"
    let subjectName: String
    let topic: String
}

// MARK: - Errors

enum ClaudeError: Error, LocalizedError {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API 키가 설정되지 않았습니다. 설정 탭에서 키를 입력해주세요."
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

actor ClaudeAPIClient: AIClient {
    static let shared = ClaudeAPIClient()
    private let keychain = KeychainProvider()
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: Image analysis (PPT slides or handwritten notes)
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
        let imageContent: [[String: Any]] = images.prefix(10).compactMap { image in
            guard let base64 = image.jpegData(compressionQuality: quality)?
                .base64EncodedString() else { return nil }
            return ["type": "image",
                    "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
        }
        var content = imageContent
        content.append(["type": "text", "text": prompt])

        let responseText = try await callClaude(model: "claude-sonnet-4-6",
                                                content: content, maxTokens: 2000)
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
        let responseText = try await callClaude(
            model: "claude-sonnet-4-6",
            content: [["type": "text", "text": prompt]],
            maxTokens: 3000)
        return try parseJSON(responseText, as: [GeneratedQuestion].self)
    }

    // MARK: Study plan generation
    func generateStudyPlan(
        subjects: [(name: String, avgScore: Double?, materialCount: Int)],
        examDate: Date
    ) async throws -> [StudyPlanItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
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
        let responseText = try await callClaude(
            model: "claude-sonnet-4-6",
            content: [["type": "text", "text": prompt]],
            maxTokens: 2000)
        return try parseJSON(responseText, as: [StudyPlanItem].self)
    }

    // MARK: Summarize (cheap model)
    func summarize(text: String) async throws -> String {
        let prompt = "다음 내용을 3문장으로 간결하게 요약해주세요:\n\(text.prefix(2000))"
        return try await callClaude(
            model: "claude-haiku-4-5-20251001",
            content: [["type": "text", "text": prompt]],
            maxTokens: 500)
    }

    // MARK: - Private HTTP layer

    private func callClaude(model: String,
                             content: [[String: Any]],
                             maxTokens: Int) async throws -> String {
        guard let apiKey = keychain.loadAPIKey() else {
            throw ClaudeError.missingAPIKey
        }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": content]]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw ClaudeError.networkError(error)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.parseError("Non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeError.invalidResponse(http.statusCode, body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]],
              let text = contentArr.first?["text"] as? String else {
            throw ClaudeError.parseError("Unexpected response structure")
        }
        return text
    }

    private func parseJSON<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        // Strip markdown code fences if present
        let cleaned = text
            .replacingOccurrences(of: #"```json\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeError.parseError("UTF-8 conversion failed")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClaudeError.parseError("JSON decode failed: \(error)")
        }
    }
}
