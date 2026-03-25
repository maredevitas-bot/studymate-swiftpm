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

    private let baseURL = "http://comcigan.com"
    private var resolvedSearchPath: String?

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }

    // MARK: - 메인 페이지에서 실제 검색 경로 추출

    private func resolveSearchPath() async -> String? {
        guard let url = URL(string: "\(baseURL)/st"),
              let (data, _) = try? await makeSession().data(from: url) else { return nil }

        let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) ?? ""

        // JS 코드 예: getJSON("st/sc5?q="+encodeURIComponent(nm)
        // 숫자 붙은 경로(sc2~sc9)나 sch를 찾는다
        let pattern = #"["']((?:st/|/)sc\w*)[?]["']"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 1), in: html) {
            var path = String(html[r])
            if !path.hasPrefix("/") { path = "/" + path }
            return path
        }
        return nil
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ComciganError.parseError("인코딩 실패")
        }

        // 첫 호출 시 실제 경로 추출
        if resolvedSearchPath == nil {
            resolvedSearchPath = await resolveSearchPath()
        }

        // 시도 경로 목록: 동적 추출 결과 + 버전별 알려진 경로
        var candidates: [String] = []
        if let p = resolvedSearchPath { candidates.append(p) }
        for p in ["/st/sc5", "/st/sc4", "/st/sc3", "/st/sc2", "/st/sch", "/st/sc"] {
            if !candidates.contains(p) { candidates.append(p) }
        }

        var lastRaw = ""
        for path in candidates {
            guard let url = URL(string: "\(baseURL)\(path)?q=\(encoded)"),
                  let (data, _) = try? await makeSession().data(from: url),
                  !data.isEmpty else { continue }

            if let results = parseSchoolResponse(data: data), !results.isEmpty {
                resolvedSearchPath = path   // 성공한 경로 캐시
                return results
            }
            lastRaw = String(data: data, encoding: .utf8)?.prefix(300).description ?? ""
        }

        if lastRaw.isEmpty {
            throw ComciganError.networkError(URLError(.cannotConnectToHost))
        }
        throw ComciganError.parseError("응답: \(lastRaw)")
    }

    // MARK: - 응답 파싱 (여러 형식 대응)

    private func parseSchoolResponse(data: Data) -> [SchoolResult]? {
        // JSON 파싱 (UTF-8, EUC-KR 순)
        var json: [String: Any]?
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = j
        } else if let str = String(data: data, encoding: .isoLatin1),
                  let d2 = str.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d2) as? [String: Any] {
            json = j
        }
        guard let json else { return nil }

        // 키 후보 우선 탐색, 없으면 첫 번째 배열 값 사용
        let keyCandidates = ["학교", "학교검색", "학교목록", "result", "data", "list"]
        var rows: [[Any]]?
        for key in keyCandidates {
            if let arr = json[key] as? [[Any]] { rows = arr; break }
        }
        if rows == nil {
            rows = json.values.compactMap { $0 as? [[Any]] }.first
        }
        guard let rows, !rows.isEmpty else { return nil }

        return rows.compactMap { row -> SchoolResult? in
            // 형식 A: [Int코드, String이름, String지역]  ← 컴시간 일반
            if row.count >= 2,
               let code = (row[0] as? Int).map(String.init),
               let name = row[1] as? String {
                let region = row.count > 2 ? (row[2] as? String ?? "") : ""
                return SchoolResult(name: name, code: code, region: region)
            }
            // 형식 B: [Int교육청코드, Int학교코드, String이름, String지역]
            if row.count >= 3,
               row[0] is Int,
               let code = (row[1] as? Int).map(String.init),
               let name = row[2] as? String {
                let region = row.count > 3 ? (row[3] as? String ?? "") : ""
                return SchoolResult(name: name, code: code, region: region)
            }
            // 형식 C: [String이름, String코드]
            if row.count >= 2,
               let name = row[0] as? String,
               let code = row[1] as? String {
                return SchoolResult(name: name, code: code, region: "")
            }
            return nil
        }
    }

    // MARK: - 시간표 조회

    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        let paths = ["/st/tt", "/st/tt2", "/st/timetable"]
        for path in paths {
            guard let url = URL(string: "\(baseURL)\(path)?s=\(schoolCode)&g=\(grade)&c=\(classNum)"),
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
