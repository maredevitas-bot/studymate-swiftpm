import Foundation

// SchoolResult는 위치 기반 파싱 사용 (Decodable 미사용)
struct SchoolResult: Identifiable {
    let id = UUID()
    let name: String
    let code: String
}

enum ComciganError: Error, LocalizedError {
    case networkError(Error)
    case parseError(String)
    case schoolNotFound

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "네트워크 오류: \(e.localizedDescription)"
        case .parseError(let s): return "파싱 오류: \(s)"
        case .schoolNotFound: return "학교를 찾을 수 없어요."
        }
    }
}

actor ComciganClient {
    static let shared = ComciganClient()
    private let baseURL = "https://comcigan.com/st"
    private let session = URLSession.shared

    func searchSchool(name: String) async throws -> [SchoolResult] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/sch?q=\(encoded)") else {
            throw ComciganError.parseError("Invalid URL")
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["학교"] as? [[Any]] else {
                throw ComciganError.parseError("Unexpected response format")
            }
            return rows.compactMap { row -> SchoolResult? in
                guard row.count >= 2,
                      let name = row[0] as? String,
                      let code = row[1] as? String else { return nil }
                return SchoolResult(name: name, code: code)
            }
        } catch let error as ComciganError {
            throw error
        } catch {
            throw ComciganError.networkError(error)
        }
    }

    func fetchTimetable(schoolCode: String, grade: Int, classNum: Int) async throws -> [[String]] {
        guard let url = URL(string: "\(baseURL)/tt?s=\(schoolCode)&g=\(grade)&c=\(classNum)") else {
            throw ComciganError.parseError("Invalid URL")
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let table = json["시간표"] as? [[String]] else {
                throw ComciganError.parseError("Unexpected timetable format")
            }
            return table
        } catch let error as ComciganError {
            throw error
        } catch {
            throw ComciganError.networkError(error)
        }
    }
}
