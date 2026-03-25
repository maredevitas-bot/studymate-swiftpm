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

    // HTTPS → HTTP 순으로 시도
    private let bases = ["https://comcigan.com", "http://comcigan.com"]
    private var resolvedBase: String?
    private var resolvedSearchPath: String?

    private func makeRequest(url: URL) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(
            "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://comcigan.com", forHTTPHeaderField: "Referer")
        return req
    }

    // MARK: - 메인 페이지에서 검색 경로 추출

    private func resolveEndpoint() async {
        for base in bases {
            guard let url = URL(string: "\(base)/st") else { continue }
            guard let (data, resp) = try? await URLSession.shared.data(for: makeRequest(url: url)),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }

            resolvedBase = base

            let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) ?? ""

            // getJSON("st/sc5?q=  또는  $.get("st/sch?q=
            if let regex = try? NSRegularExpression(pattern: #"["']((?:st/|/)sc\w*)[?]["']"#),
               let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html) {
                var path = String(html[r])
                if !path.hasPrefix("/") { path = "/" + path }
                resolvedSearchPath = path
            }
            return
        }
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw ComciganError.parseError("인코딩 실패")
        }

        if resolvedBase == nil { await resolveEndpoint() }
        let base = resolvedBase ?? "https://comcigan.com"

        // 시도할 경로 목록
        var paths: [String] = []
        if let p = resolvedSearchPath { paths.append(p) }
        for p in ["/st/sc5", "/st/sc4", "/st/sc3", "/st/sc2", "/st/sch", "/st/sc"] {
            if !paths.contains(p) { paths.append(p) }
        }

        var lastRaw = ""
        for path in paths {
            guard let url = URL(string: "\(base)\(path)?q=\(encoded)") else { continue }
            guard let (data, _) = try? await URLSession.shared.data(for: makeRequest(url: url)),
                  !data.isEmpty else { continue }

            if let results = parseSchoolResponse(data: data), !results.isEmpty {
                resolvedSearchPath = path
                return results
            }
            if lastRaw.isEmpty {
                lastRaw = String(data: data, encoding: .utf8)?.prefix(400).description ?? "(binary)"
            }
        }

        if lastRaw.isEmpty {
            throw ComciganError.networkError(URLError(.cannotConnectToHost))
        }
        throw ComciganError.parseError("응답: \(lastRaw)")
    }

    // MARK: - 응답 파싱

    private func parseSchoolResponse(data: Data) -> [SchoolResult]? {
        var json: [String: Any]?
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = j
        } else if let str = String(data: data, encoding: .isoLatin1),
                  let d2 = str.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d2) as? [String: Any] {
            json = j
        }
        guard let json else { return nil }

        // 키 후보 탐색 → 없으면 첫 번째 배열값 사용
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
            guard row.count >= 2 else { return nil }
            // [Int코드, String이름, String지역]
            if let code = (row[0] as? Int).map(String.init),
               let name = row[1] as? String {
                let region = row.count > 2 ? (row[2] as? String ?? "") : ""
                return SchoolResult(name: name, code: code, region: region)
            }
            // [Int교육청코드, Int학교코드, String이름, String지역]
            if row[0] is Int,
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
    }

    // MARK: - 시간표 조회

    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        let base = resolvedBase ?? "https://comcigan.com"
        for path in ["/st/tt", "/st/tt2", "/st/timetable"] {
            guard let url = URL(string: "\(base)\(path)?s=\(schoolCode)&g=\(grade)&c=\(classNum)"),
                  let (data, _) = try? await URLSession.shared.data(for: makeRequest(url: url)),
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
