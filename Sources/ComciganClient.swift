import Foundation

struct SchoolResult: Identifiable {
    let id = UUID()
    let name: String
    let code: String      // 학교 코드 (숫자 문자열)
    let region: String    // 지역명
}

enum ComciganError: Error, LocalizedError {
    case networkError(Error)
    case parseError(String)
    case schoolNotFound
    case routingFailed

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
        case .parseError(let s):   return "파싱 오류: \(s)"
        case .schoolNotFound:      return "학교를 찾을 수 없어요."
        case .routingFailed:       return "컴시간 서버 응답 없음"
        }
    }
}

actor ComciganClient {
    static let shared = ComciganClient()

    private let mainURL = "http://comcigan.com/st"
    // 검색 경로 — 메인 페이지에서 동적으로 추출, 없으면 fallback 사용
    private var searchPath: String = "/st/sch"

    private func session() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }

    // MARK: - 라우팅 경로 추출

    /// 메인 페이지 HTML에서 학교 검색 경로를 추출한다.
    /// 예: getJSON("st/sch?q=" → searchPath = "/st/sch"
    private func refreshRouting() async {
        guard let url = URL(string: mainURL) else { return }
        guard let (data, _) = try? await session().data(from: url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }

        // 패턴: getJSON("st/sch?q=  또는  $.get("st/sch?q=
        let patterns = [
            #"getJSON\("([^"?]+)\?"#,
            #"get\("([^"?]+)\?"#,
            #"post\("([^"?]+)\??"#
        ]
        for pattern in patterns {
            if let range = html.range(of: pattern, options: .regularExpression),
               let innerRange = html.range(of: #"["']([^"'?]+)\?"#, options: .regularExpression, range: range) {
                var path = String(html[innerRange])
                // 따옴표·물음표 제거
                path = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"'?"))
                if !path.isEmpty {
                    searchPath = "/" + path
                    return
                }
            }
        }
        // 정규식 없으면 단순 문자열 탐색
        if html.contains("st/sch") {
            searchPath = "/st/sch"
        }
    }

    // MARK: - 학교 검색

    func searchSchool(name: String) async throws -> [SchoolResult] {
        await refreshRouting()

        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://comcigan.com\(searchPath)?q=\(encoded)") else {
            throw ComciganError.parseError("URL 생성 실패")
        }

        let data: Data
        do {
            (data, _) = try await session().data(from: url)
        } catch {
            throw ComciganError.networkError(error)
        }

        // 실제 컴시간 응답: {"학교": [[교육청코드, 학교코드, "학교명", "지역"], ...]}
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "(binary)"
            throw ComciganError.parseError("JSON 파싱 실패: \(raw.prefix(200))")
        }

        // 키 이름은 버전마다 다를 수 있으므로 여러 후보 시도
        let candidateKeys = ["학교", "학교검색", "result", "data"]
        var rows: [[Any]]?
        for key in candidateKeys {
            if let r = json[key] as? [[Any]] {
                rows = r; break
            }
        }

        guard let rows else {
            let keys = json.keys.joined(separator: ", ")
            throw ComciganError.parseError("학교 목록 키 없음 (응답 키: \(keys))")
        }

        if rows.isEmpty { throw ComciganError.schoolNotFound }

        return rows.compactMap { row -> SchoolResult? in
            guard row.count >= 3 else { return nil }
            // 형식 A: [Int코드, Int학교코드, String이름, String지역]
            if let schoolCode = row[1] as? Int,
               let schoolName = row[2] as? String {
                let region = (row.count > 3 ? row[3] as? String : nil) ?? ""
                return SchoolResult(name: schoolName, code: String(schoolCode), region: region)
            }
            // 형식 B: [Int코드, String이름, String지역] (3-element)
            if let schoolCode = row[0] as? Int,
               let schoolName = row[1] as? String {
                let region = (row.count > 2 ? row[2] as? String : nil) ?? ""
                return SchoolResult(name: schoolName, code: String(schoolCode), region: region)
            }
            // 형식 C: [String이름, String코드, ...]
            if let schoolName = row[0] as? String,
               let schoolCode = row[1] as? String {
                return SchoolResult(name: schoolName, code: schoolCode, region: "")
            }
            return nil
        }
    }

    // MARK: - 시간표 조회

    /// 반환값: [요일인덱스(0=월~4=금)][교시인덱스] = "과목명(선생님)"
    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        guard let url = URL(string: "http://comcigan.com/st/tt?s=\(schoolCode)&g=\(grade)&c=\(classNum)") else {
            throw ComciganError.parseError("URL 생성 실패")
        }

        let data: Data
        do {
            (data, _) = try await session().data(from: url)
        } catch {
            throw ComciganError.networkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComciganError.parseError("시간표 JSON 파싱 실패")
        }

        // 키 후보
        let candidateKeys = ["시간표", "timetable", "result", "data"]
        for key in candidateKeys {
            if let table = json[key] as? [[String]] {
                return table
            }
            // 숫자 배열인 경우 변환
            if let table = json[key] as? [[[Any]]] {
                return table.map { dayRow in
                    dayRow.map { cell in
                        if let s = cell.first as? String { return s }
                        return cell.map { "\($0)" }.joined(separator: " ")
                    }
                }
            }
        }

        let keys = json.keys.joined(separator: ", ")
        throw ComciganError.parseError("시간표 키 없음 (응답 키: \(keys))")
    }
}
