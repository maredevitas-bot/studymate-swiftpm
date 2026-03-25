import Foundation

struct SchoolResult: Identifiable {
    let id = UUID()
    let name: String
    let code: String   // 학교코드 (숫자)
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

// MARK: - EUC-KR 인코딩 헬퍼

private let eucKREncoding = String.Encoding(rawValue:
    CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
    )
)

private func eucKRHex(_ string: String) -> String {
    guard let data = string.data(using: eucKREncoding) else { return string }
    return data.map { String(format: "%%%02x", $0) }.joined()
}

private func decodeEUCKR(_ data: Data) -> String {
    if let s = String(data: data, encoding: .utf8) { return s }
    if let s = String(data: data, encoding: eucKREncoding) { return s }
    return String(data: data, encoding: .isoLatin1) ?? ""
}

// MARK: - ComciganClient

actor ComciganClient {
    static let shared = ComciganClient()

    // 동적 초기화로 얻는 값
    private var baseUrl: String?       // e.g. "http://comci.net:4082"
    private var extractCode: String?   // e.g. "/36179?17384l"
    private var scData: [String] = []  // e.g. ["73629_", "sc", "1", "0"]

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
        return URLSession(configuration: cfg)
    }()

    // MARK: - 초기화: 컴시간학생.kr → frame URL → 검색 경로 추출

    private func ensureInit() async throws {
        if baseUrl != nil && extractCode != nil { return }

        // Step 1: 메인 페이지에서 frame src 추출
        // URLComponents 로 한글 도메인 IDNA 인코딩
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = "컴시간학생.kr"
        guard let mainUrl = comps.url else {
            throw ComciganError.parseError("메인 URL 생성 실패")
        }

        let mainHtml: String
        do {
            let (data, _) = try await session.data(from: mainUrl)
            mainHtml = decodeEUCKR(data)
        } catch {
            throw ComciganError.networkError(error)
        }

        // <frame src="..."> 에서 URL 추출
        let frameUrl = extractFrameSrc(from: mainHtml)
        guard let frameUrl else {
            throw ComciganError.parseError("frame URL을 찾을 수 없음")
        }
        guard let frameUrlObj = URL(string: frameUrl) else {
            throw ComciganError.parseError("frame URL 파싱 실패: \(frameUrl)")
        }

        // baseUrl = scheme://host:port
        let port = frameUrlObj.port.map { ":\($0)" } ?? ""
        baseUrl = "\(frameUrlObj.scheme ?? "http")://\(frameUrlObj.host ?? "")\(port)"

        // Step 2: frame 페이지 소스에서 school_ra, sc_data 추출
        let source: String
        do {
            let (data, _) = try await session.data(from: frameUrlObj)
            source = decodeEUCKR(data)
        } catch {
            throw ComciganError.networkError(error)
        }

        extractCode = extractSchoolRaPath(from: source)
        scData = extractScData(from: source)

        guard extractCode != nil else {
            throw ComciganError.parseError("검색 경로 추출 실패")
        }
    }

    // MARK: - HTML 파싱 헬퍼

    private func extractFrameSrc(from html: String) -> String? {
        // 실제 형식: <FRAME src='http://comci.net:4082/st'>  (싱글쿼트, 대문자)
        // 싱글쿼트 → 더블쿼트로 치환 후 파싱
        let normalized = html.replacingOccurrences(of: "'", with: "\"")
        guard let regex = try? NSRegularExpression(pattern: #"<frame[^>]+src="([^"]+)""#, options: .caseInsensitive),
              let m = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let r = Range(m.range(at: 1), in: normalized) else { return nil }
        return String(normalized[r])
    }

    private func extractSchoolRaPath(from source: String) -> String? {
        // 실제 형식: url:'./36179?17384l'
        // JS 정규식과 동일: url:'.(.*?)' → 첫 글자('.')를 건너뛰고 나머지 캡처
        // → '/36179?17384l' (도트 제외, 슬래시 포함)
        guard let idx = source.range(of: "school_ra(sc)") else { return nil }
        let snippet = String(source[idx.lowerBound...].prefix(200))
            .replacingOccurrences(of: " ", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"url:'.([^']+)'"#),
              let m = regex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
              let r = Range(m.range(at: 1), in: snippet) else { return nil }
        return String(snippet[r])
    }

    private func extractScData(from source: String) -> [String] {
        // sc_data('73629_','sc','1','0')
        guard let idx = source.range(of: "sc_data(") else { return [] }
        let snippet = String(source[idx.lowerBound...].prefix(80))
        guard let regex = try? NSRegularExpression(pattern: #"\(([^)]+)\)"#),
              let m = regex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
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

        // EUC-KR hex 인코딩: '서울' → '%BC%AD%BF%EF'
        let hexName = eucKRHex(name)
        let urlStr = "\(baseUrl)\(extractCode)\(hexName)"

        guard let url = URL(string: urlStr) else {
            throw ComciganError.parseError("URL 생성 실패: \(urlStr)")
        }

        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            throw ComciganError.networkError(error)
        }

        // JSON 끝 '}'까지만 사용 (컴시간은 뒤에 쓸모없는 데이터 붙음)
        var raw = decodeEUCKR(data)
        if let lastBrace = raw.lastIndex(of: "}") {
            raw = String(raw[...lastBrace])
        }

        guard let jsonData = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let rows = json["학교검색"] as? [[Any]] else {
            throw ComciganError.parseError("응답 파싱 실패: \(raw.prefix(300))")
        }

        // 행 구조: [_, 지역, 학교이름, 학교코드]
        let results = rows.compactMap { row -> SchoolResult? in
            guard row.count >= 4,
                  let schoolName = row[2] as? String, !schoolName.isEmpty,
                  let codeInt = row[3] as? Int, codeInt != 0 else { return nil }
            let region = row[1] as? String ?? ""
            return SchoolResult(name: schoolName, code: String(codeInt), region: region)
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

        // URL 공식: {extractCode 경로부분}?{base64(scData[0]+schoolCode+"_0_"+scData[2])}
        let pathPart = extractCode.components(separatedBy: "?").first ?? extractCode
        let s7 = (scData.first ?? "") + schoolCode
        let payload = "\(s7)_0_\(scData.count > 2 ? scData[2] : "1")"
        guard let payloadData = payload.data(using: .utf8) else {
            throw ComciganError.parseError("payload 인코딩 실패")
        }
        let b64 = payloadData.base64EncodedString()
        let urlStr = "\(baseUrl)\(pathPart)?\(b64)"

        guard let url = URL(string: urlStr),
              let (data, _) = try? await session.data(from: url),
              !data.isEmpty else {
            throw ComciganError.parseError("시간표 요청 실패")
        }

        var raw = decodeEUCKR(data)
        if let lastBrace = raw.lastIndex(of: "}") { raw = String(raw[...lastBrace]) }

        guard let jsonData = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ComciganError.parseError("시간표 JSON 파싱 실패")
        }

        // 시간표 파싱은 복잡한 JS eval 필요 — 현재는 기본 구조만 시도
        for key in ["시간표", "timetable"] {
            if let table = json[key] as? [[String]] { return table }
        }

        // 학급수 확인
        _ = json["학급수"] as? [Int]
        throw ComciganError.parseError("시간표 자동 파싱 미지원 — 과목을 직접 추가해 주세요")
    }
}
