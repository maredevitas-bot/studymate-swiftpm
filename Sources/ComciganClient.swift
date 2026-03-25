import Foundation

struct SchoolResult: Identifiable {
    let id = UUID()
    let name: String
    let code: String
    let region: String
}

enum ComciganError: Error, LocalizedError {
    case networkError(Error)
    case parseError(String)
    case schoolNotFound

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
        case .parseError(let s):   return "파싱 오류: \(s)"
        case .schoolNotFound:      return "학교를 찾을 수 없어요."
        }
    }
}

actor ComciganClient {
    static let shared = ComciganClient()

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "Accept": "*/*"
        ]
        return URLSession(configuration: cfg)
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ComciganError.parseError("인코딩 실패")
        }

        // 응답이 왔던 URL부터 시도
        let urlStrings = [
            "https://comcigan.com/st/sch?q=\(encoded)",
            "http://comcigan.com/st/sch?q=\(encoded)",
            "https://comcigan.com/st/sc5?q=\(encoded)",
            "http://comcigan.com/st/sc5?q=\(encoded)",
        ]

        var lastError: String = "모든 경로 연결 실패"

        for urlStr in urlStrings {
            guard let url = URL(string: urlStr) else { continue }

            let data: Data
            do {
                (data, _) = try await makeSession().data(from: url)
            } catch {
                lastError = "네트워크: \(error.localizedDescription)"
                continue
            }

            guard !data.isEmpty else { continue }

            // 항상 raw 저장 (마지막 시도용 디버그)
            let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .isoLatin1)
                   ?? "(binary)"
            lastError = String(raw.prefix(500))

            if let results = parseResponse(data: data, raw: raw), !results.isEmpty {
                return results
            }
        }

        throw ComciganError.parseError(lastError)
    }

    // MARK: - 파싱 (딕셔너리 / 배열 모두 지원)

    private func parseResponse(data: Data, raw: String) -> [SchoolResult]? {
        // UTF-8 실패 시 EUC-KR(isoLatin1)으로 재시도
        func toData(_ str: String) -> Data? { str.data(using: .utf8) }
        let parseData = (String(data: data, encoding: .utf8) != nil)
                      ? data
                      : (toData(raw) ?? data)

        guard let obj = try? JSONSerialization.jsonObject(with: parseData) else { return nil }

        // 형식 1: 최상위가 딕셔너리 {"학교": [[...]]}
        if let dict = obj as? [String: Any] {
            let keys = ["학교", "학교검색", "학교목록", "result", "data", "list"]
            for key in keys {
                if let rows = dict[key] as? [[Any]], let r = mapRows(rows) { return r }
            }
            // 키를 모르면 첫 번째 배열 값 시도
            for val in dict.values {
                if let rows = val as? [[Any]], let r = mapRows(rows) { return r }
            }
        }

        // 형식 2: 최상위가 배열 [[...]]
        if let rows = obj as? [[Any]], let r = mapRows(rows) { return r }

        return nil
    }

    private func mapRows(_ rows: [[Any]]) -> [SchoolResult]? {
        let results = rows.compactMap { row -> SchoolResult? in
            guard row.count >= 2 else { return nil }

            // [Int코드, String이름] 또는 [Int코드, String이름, String지역]
            if let code = (row[0] as? Int).map(String.init),
               let name = row[1] as? String {
                let region = row.count > 2 ? (row[2] as? String ?? "") : ""
                return SchoolResult(name: name, code: code, region: region)
            }
            // [Int교육청, Int코드, String이름, String지역]
            if row.count >= 3, row[0] is Int,
               let code = (row[1] as? Int).map(String.init),
               let name = row[2] as? String {
                let region = row.count > 3 ? (row[3] as? String ?? "") : ""
                return SchoolResult(name: name, code: code, region: region)
            }
            // [String이름, String코드]
            if let name = row[0] as? String, let code = row[1] as? String {
                return SchoolResult(name: name, code: code, region: "")
            }
            return nil
        }
        return results.isEmpty ? nil : results
    }

    // MARK: - 시간표

    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        let urlStrings = [
            "https://comcigan.com/st/tt?s=\(schoolCode)&g=\(grade)&c=\(classNum)",
            "http://comcigan.com/st/tt?s=\(schoolCode)&g=\(grade)&c=\(classNum)",
        ]
        for urlStr in urlStrings {
            guard let url = URL(string: urlStr),
                  let (data, _) = try? await makeSession().data(from: url),
                  !data.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for key in ["시간표", "timetable", "result", "data"] {
                if let table = json[key] as? [[String]] { return table }
            }
        }
        throw ComciganError.parseError("시간표를 불러올 수 없어요.")
    }
}
