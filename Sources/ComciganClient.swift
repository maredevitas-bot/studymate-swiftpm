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

    private let base = "http://comcigan.com"

    // 쿠키를 유지하는 전용 URLSession
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            "Accept-Language": "ko-KR,ko;q=0.9"
        ]
        return URLSession(configuration: cfg)
    }()

    private var sessionReady = false

    // MARK: - PHP 세션 초기화 (PHPSESSID 쿠키 획득)

    private func ensureSession() async {
        guard !sessionReady else { return }
        guard let url = URL(string: "\(base)/st/") else { return }
        _ = try? await session.data(from: url)
        sessionReady = true
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        await ensureSession()

        // EUC-KR URL 인코딩 (컴시간 서버 요구 사항)
        let eucKR = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
            )
        )
        let encodedQuery: String
        if let data = name.data(using: eucKR) {
            encodedQuery = data.map { String(format: "%%%02X", $0) }.joined()
        } else {
            encodedQuery = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        }

        let urlCandidates = [
            "\(base)/st/sch?q=\(encodedQuery)",
            "\(base)/st/sc5?q=\(encodedQuery)",
            "\(base)/st/sc4?q=\(encodedQuery)",
        ]

        var lastRaw = ""

        for urlStr in urlCandidates {
            guard let url = URL(string: urlStr) else { continue }

            let data: Data
            do {
                (data, _) = try await session.data(from: url)
            } catch {
                lastRaw = "네트워크: \(error.localizedDescription)"
                continue
            }

            guard !data.isEmpty else { continue }

            // EUC-KR → UTF-8 변환
            let raw = decodeResponse(data)
            lastRaw = String(raw.prefix(500))

            if let results = parseSchoolList(raw), !results.isEmpty {
                return results
            }
        }

        throw ComciganError.parseError(lastRaw)
    }

    // MARK: - EUC-KR 디코딩

    private func decodeResponse(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        let eucKR = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
            )
        )
        if let s = String(data: data, encoding: eucKR) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - 파싱

    private func parseSchoolList(_ raw: String) -> [SchoolResult]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var rows: [[Any]]?

        // 딕셔너리: {"학교": [[...]]}
        if let dict = obj as? [String: Any] {
            for key in ["학교", "학교검색", "학교목록", "result", "data"] {
                if let r = dict[key] as? [[Any]] { rows = r; break }
            }
            if rows == nil {
                rows = dict.values.compactMap { $0 as? [[Any]] }.first
            }
        }
        // 최상위 배열: [[...]]
        if rows == nil, let r = obj as? [[Any]] { rows = r }

        guard let rows, !rows.isEmpty else { return nil }
        return mapRows(rows)
    }

    private func mapRows(_ rows: [[Any]]) -> [SchoolResult]? {
        let results = rows.compactMap { row -> SchoolResult? in
            guard row.count >= 2 else { return nil }
            // [Int코드, String이름, String지역]
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
        await ensureSession()
        let url = URL(string: "\(base)/st/tt?s=\(schoolCode)&g=\(grade)&c=\(classNum)")!
        guard let (data, _) = try? await session.data(from: url), !data.isEmpty else {
            throw ComciganError.parseError("시간표 요청 실패")
        }
        let raw = decodeResponse(data)
        guard let jsonData = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { throw ComciganError.parseError("시간표 파싱 실패") }

        for key in ["시간표", "timetable", "result", "data"] {
            if let table = json[key] as? [[String]] { return table }
        }
        throw ComciganError.parseError("시간표 키 없음")
    }
}
