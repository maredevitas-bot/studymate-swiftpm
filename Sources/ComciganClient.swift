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

// MARK: - EUC-KR

private let eucKREncoding = String.Encoding(rawValue:
    CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))

private func eucKRHex(_ s: String) -> String {
    guard let d = s.data(using: eucKREncoding) else { return s }
    return d.map { String(format: "%%%02x", $0) }.joined()
}

private func decodeEUCKR(_ data: Data) -> String {
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: eucKREncoding) { return s }
    return String(data: data, encoding: .isoLatin1) ?? ""
}

// MARK: - Client

actor ComciganClient {
    static let shared = ComciganClient()

    private var baseUrl: String?     // "http://comci.net:4082"
    private var extractCode: String? // "/36179?17384l"
    private var scData: [String] = []

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    // MARK: - Init

    private func ensureInit() async throws {
        guard baseUrl == nil || extractCode == nil else { return }

        // 1) 메인 페이지에서 frame URL 동적 탐색
        //    컴시간학생.kr punycode + 대안 도메인들 순서로 시도
        let mainCandidates = [
            "http://xn--s39aj90b0nb2xw6xh.kr",  // 컴시간학생.kr punycode
            "http://comcigan.kr",
            "http://comcigan.com",
        ]

        var frameUrlStr: String? = nil
        for urlStr in mainCandidates {
            guard let url = URL(string: urlStr),
                  let (data, _) = try? await session.data(from: url) else { continue }
            let html = decodeEUCKR(data)
            if let found = extractFrameSrc(from: html) {
                frameUrlStr = found
                break
            }
        }

        // 2) 위에서 못 찾으면 알려진 frame URL 직접 사용
        let frameUrl = frameUrlStr ?? "http://comci.net:4082/st"

        guard let frameUrlObj = URL(string: frameUrl) else {
            throw ComciganError.parseError("frame URL 파싱 실패: \(frameUrl)")
        }

        // baseUrl = scheme://host:port
        let port = frameUrlObj.port.map { ":\($0)" } ?? ""
        let host = frameUrlObj.host ?? "comci.net"
        let scheme = frameUrlObj.scheme ?? "http"
        baseUrl = "\(scheme)://\(host)\(port)"

        // 3) frame 페이지에서 extractCode, scData 추출
        guard let (frameData, _) = try? await session.data(from: frameUrlObj) else {
            throw ComciganError.networkError(URLError(.cannotConnectToHost))
        }
        let source = decodeEUCKR(frameData)

        extractCode = extractSchoolRaPath(from: source)
        scData      = extractScData(from: source)

        guard extractCode != nil else {
            throw ComciganError.parseError("검색 경로 추출 실패 (소스 길이: \(source.count))")
        }
    }

    // MARK: - HTML 파싱

    /// <FRAME src='http://comci.net:4082/st'>  ← 싱글쿼트, 대문자 TAG
    private func extractFrameSrc(from html: String) -> String? {
        let normalized = html.replacingOccurrences(of: "'", with: "\"")
        guard let re = try? NSRegularExpression(pattern: #"<frame[^>]+src="([^"]+)""#, options: .caseInsensitive),
              let m = re.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let r = Range(m.range(at: 1), in: normalized) else { return nil }
        return String(normalized[r])
    }

    /// school_ra(sc){$.ajax({url:'./36179?17384l'+sc,...
    /// JS 정규식: url:'.(.*?)'  → 첫 글자(.) 건너뛰고 캡처
    /// → "/36179?17384l"
    private func extractSchoolRaPath(from source: String) -> String? {
        guard let idx = source.range(of: "school_ra(sc)") else { return nil }
        let snippet = String(source[idx.lowerBound...].prefix(200))
            .replacingOccurrences(of: " ", with: "")
        guard let re = try? NSRegularExpression(pattern: #"url:'.([^']+)'"#),
              let m = re.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
              let r = Range(m.range(at: 1), in: snippet) else { return nil }
        return String(snippet[r])
    }

    /// sc_data('73629_',sc,1,'0')  → ["73629_","sc","1","0"]
    private func extractScData(from source: String) -> [String] {
        guard let idx = source.range(of: "sc_data(") else { return [] }
        let snippet = String(source[idx.lowerBound...].prefix(80))
        guard let re = try? NSRegularExpression(pattern: #"\(([^)]+)\)"#),
              let m = re.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
              let r = Range(m.range(at: 1), in: snippet) else { return [] }
        return String(snippet[r])
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "' ")) }
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        try await ensureInit()

        guard let baseUrl, let extractCode else {
            throw ComciganError.parseError("초기화 실패")
        }

        let hex = eucKRHex(name)
        let urlStr = "\(baseUrl)\(extractCode)\(hex)"
        guard let url = URL(string: urlStr) else {
            throw ComciganError.parseError("검색 URL 생성 실패: \(urlStr)")
        }

        let data: Data
        do { (data, _) = try await session.data(from: url) }
        catch { throw ComciganError.networkError(error) }

        // JSON 뒤에 불필요한 데이터 잘라내기
        var raw = decodeEUCKR(data)
        if let last = raw.lastIndex(of: "}") { raw = String(raw[...last]) }

        guard let jd = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jd) as? [String: Any],
              let rows = json["학교검색"] as? [[Any]] else {
            throw ComciganError.parseError("응답: \(raw.prefix(300))")
        }

        // 행 구조: [_, 지역, 학교이름, 학교코드]
        let results = rows.compactMap { row -> SchoolResult? in
            guard row.count >= 4,
                  let schoolName = row[2] as? String, !schoolName.isEmpty,
                  let codeInt   = row[3] as? Int,     codeInt != 0 else { return nil }
            return SchoolResult(name: schoolName,
                                code: String(codeInt),
                                region: row[1] as? String ?? "")
        }
        if results.isEmpty { throw ComciganError.schoolNotFound }
        return results
    }

    // MARK: - 시간표

    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        try await ensureInit()
        guard let baseUrl, let extractCode, !scData.isEmpty else {
            throw ComciganError.parseError("초기화 실패")
        }
        // URL: {경로부분}?{base64(scData[0]+schoolCode+"_0_"+scData[2])}
        let pathPart = extractCode.components(separatedBy: "?").first ?? extractCode
        let payload  = "\(scData[0])\(schoolCode)_0_\(scData.count > 2 ? scData[2] : "1")"
        let b64      = Data(payload.utf8).base64EncodedString()
        guard let url = URL(string: "\(baseUrl)\(pathPart)?\(b64)"),
              let (data, _) = try? await session.data(from: url) else {
            throw ComciganError.parseError("시간표 요청 실패")
        }
        var raw = decodeEUCKR(data)
        if let last = raw.lastIndex(of: "}") { raw = String(raw[...last]) }
        guard let jd   = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jd) as? [String: Any] else {
            throw ComciganError.parseError("시간표 파싱 실패")
        }
        for key in ["시간표", "timetable"] {
            if let t = json[key] as? [[String]] { return t }
        }
        throw ComciganError.parseError("시간표 자동 파싱 미지원 — 과목을 직접 추가해 주세요")
    }
}
