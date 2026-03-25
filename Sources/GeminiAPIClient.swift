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

    /// 마지막 요청 시각 — RPM 제어용
    private var lastRequestDate: Date = .distantPast
    /// 요청 간 최소 간격 (6초 = 분당 10회 이하로 안전 마진 확보)
    private let minRequestInterval: TimeInterval = 6.0
    /// 이미지 리사이즈 최대 변 길이 (px) — 토큰 사용량 직결
    private let maxImageEdge: CGFloat = 768

    // MARK: Image analysis (배치 분할 + RPM 제어)
    func analyzeImages(_ images: [UIImage], type: MaterialType) async throws -> AnalysisResult {
        let isNote = type == .note
        let quality: CGFloat = 0.6
        // 리사이즈 후 배치 구성 (최대 3장/배치, 최대 9장)
        let resized = images.prefix(9).map { resized($0, maxEdge: maxImageEdge) }
        let batches = resized.chunked(into: 3)

        // 배치마다 순차 요청 (callGemini 내부에서 간격 보장)
        var batchResults: [AnalysisResult] = []
        for (i, batch) in batches.enumerated() {
            let label = batches.count > 1 ? " (파트 \(i + 1)/\(batches.count))" : ""
            let prompt = """
            이 \(isNote ? "손필기 노트" : "수업 PPT 슬라이드들")\(label)의 핵심 내용을 분석해주세요.
            JSON 형식으로만 응답 (마크다운 없이):
            {"extractedText": "전체 텍스트", "summary": "요약 2~3문장", "highlights": ["키워드1","키워드2","키워드3"]}
            """
            var parts: [[String: Any]] = batch.compactMap { (image: UIImage) -> [String: Any]? in
                guard let base64 = image.jpegData(compressionQuality: quality)?.base64EncodedString() else { return nil }
                return ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
            }
            parts.append(["text": prompt])

            let responseText = try await callGemini(parts: parts, maxTokens: 1500)
            batchResults.append(try parseJSON(responseText, as: AnalysisResult.self))
        }

        // 배치 1개: 그대로 반환 (추가 요청 없음)
        if batchResults.count == 1 { return batchResults[0] }

        // 배치 여러 개: 텍스트 합산 후 최종 요약 1회 요청
        let combinedText = batchResults.map(\.extractedText).joined(separator: "\n\n")
        let allHighlights = batchResults.flatMap(\.highlights)

        let summaryPrompt = """
        다음 텍스트를 3~5문장으로 요약하고 핵심 키워드 5개를 추출해주세요.
        JSON 형식으로만 응답 (마크다운 없이):
        {"summary": "요약", "highlights": ["키워드1","키워드2","키워드3","키워드4","키워드5"]}

        텍스트:
        \(combinedText.prefix(3000))
        """
        let summaryText = try await callGemini(parts: [["text": summaryPrompt]], maxTokens: 600)

        struct SummaryOnly: Decodable { let summary: String; let highlights: [String] }
        let summary = try parseJSON(summaryText, as: SummaryOnly.self)

        return AnalysisResult(
            extractedText: combinedText,
            summary: summary.summary,
            highlights: Array((summary.highlights.isEmpty ? allHighlights : summary.highlights).prefix(5))
        )
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

    // MARK: Summarize (텍스트 → AnalysisResult, 이미지 없음)
    func summarizeText(_ text: String) async throws -> AnalysisResult {
        let prompt = """
        다음 수업 자료 내용을 분석해주세요.
        JSON 형식으로만 응답 (마크다운 없이):
        {"extractedText": \(jsonEscape(String(text.prefix(6000)))), "summary": "핵심 내용 요약 3~5문장", "highlights": ["키워드1","키워드2","키워드3","키워드4","키워드5"]}
        """
        let responseText = try await callGemini(parts: [["text": prompt]], maxTokens: 1000)
        return try parseJSON(responseText, as: AnalysisResult.self)
    }

    func summarize(text: String) async throws -> String {
        let prompt = "다음 내용을 3문장으로 간결하게 요약해주세요:\n\(text.prefix(2000))"
        return try await callGemini(parts: [["text": prompt]], maxTokens: 500)
    }

    private func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
    }

    // MARK: - Private HTTP layer
    private func callGemini(parts: [[String: Any]], maxTokens: Int) async throws -> String {
        // RPM 제어: 마지막 요청으로부터 최소 간격 보장
        let elapsed = Date().timeIntervalSince(lastRequestDate)
        if elapsed < minRequestInterval {
            let wait = UInt64((minRequestInterval - elapsed) * 1_000_000_000)
            try await Task.sleep(nanoseconds: wait)
        }
        lastRequestDate = Date()

        guard let apiKey = keychain.loadGeminiKey() else {
            throw GeminiError.missingAPIKey
        }
        guard let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)") else {
            throw GeminiError.parseError("Invalid URL")
        }

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.7
            ]
        ]
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw GeminiError.networkError(error)
        }

        // 429 시 최대 3회 재시도 — Retry-After 헤더 우선, 없으면 30s→60s→120s
        var lastError: Error = GeminiError.parseError("Unknown")
        for attempt in 0..<3 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                lastError = GeminiError.networkError(error)
                break   // 네트워크 오류는 재시도 의미 없음
            }

            guard let http = response as? HTTPURLResponse else {
                lastError = GeminiError.parseError("Non-HTTP response")
                break
            }

            if http.statusCode == 429 {
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = GeminiError.invalidResponse(http.statusCode, body)
                guard attempt < 2 else { break }

                // Retry-After 헤더 확인 (초 단위)
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Double($0) } ?? Double([30, 60, 120][attempt])
                let waitNs = UInt64(retryAfter * 1_000_000_000)
                try await Task.sleep(nanoseconds: waitNs)
                continue
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
        throw lastError
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

/// MARK: - Collection 배치 분할 헬퍼
private extension Collection {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(dropFirst($0).prefix(size))
        }
    }
}

// MARK: - 이미지 리사이즈 헬퍼
private func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
    let size = image.size
    let longer = max(size.width, size.height)
    guard longer > maxEdge else { return image }
    let scale = maxEdge / longer
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
}
