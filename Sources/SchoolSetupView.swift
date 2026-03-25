import SwiftUI
import SwiftData

struct SchoolSetupView: View {
    var onComplete: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var results: [SchoolResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedGrade = 1
    @State private var selectedClass = 1
    @State private var useManualInput = false
    @State private var manualSchoolName = ""

    var body: some View {
        Form {
            Section("학교 검색") {
                HStack {
                    TextField("학교명 입력", text: $searchText)
                    Button("검색") { Task { await searchSchool() } }
                        .disabled(searchText.isEmpty || isSearching)
                }
                if isSearching {
                    ProgressView("검색 중...")
                }
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                    Toggle("직접 입력", isOn: $useManualInput)
                }
                if useManualInput {
                    TextField("학교명 직접 입력", text: $manualSchoolName)
                    Button("직접 입력으로 추가") {
                        let school = School(name: manualSchoolName, code: "manual-\(UUID().uuidString)",
                                             grade: selectedGrade, classNum: selectedClass)
                        modelContext.insert(school)
                        try? modelContext.save()
                        onComplete?()
                    }
                    .disabled(manualSchoolName.isEmpty)
                }
            }
            if !results.isEmpty {
                Section("검색 결과") {
                    ForEach(results) { school in
                        Button {
                            selectSchool(school)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(school.name).foregroundStyle(.primary)
                                if !school.region.isEmpty {
                                    Text(school.region).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section("학년 / 반") {
                Stepper("학년: \(selectedGrade)", value: $selectedGrade, in: 1...3)
                Stepper("반: \(selectedClass)", value: $selectedClass, in: 1...20)
            }
        }
        .navigationTitle("학교 설정")
    }

    private func searchSchool() async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await ComciganClient.shared.searchSchool(name: searchText)
            if results.isEmpty {
                errorMessage = "검색 결과가 없어요. 직접 입력을 사용하세요."
            }
        } catch {
            errorMessage = "컴시간 연결 실패: \(error.localizedDescription)"
        }
        isSearching = false
    }

    private func selectSchool(_ school: SchoolResult) {
        let schoolModel = School(name: school.name, code: school.code,
                                  grade: selectedGrade, classNum: selectedClass)
        modelContext.insert(schoolModel)
        try? modelContext.save()   // persist School immediately, independent of timetable load
        Task {
            await loadTimetable(school: schoolModel)
            onComplete?()
        }
    }

    @MainActor
    private func loadTimetable(school: School) async {
        do {
            let table = try await ComciganClient.shared.fetchTimetable(
                schoolCode: school.code, grade: school.grade, classNum: school.classNum)
            createSubjectsFromTimetable(table)
        } catch {
            // 시간표 로드 실패 시 무시 — 과목은 수동 추가 가능
        }
    }

    @MainActor
    private func createSubjectsFromTimetable(_ table: [[String]]) {
        let colors = ["#4A90D9", "#E24B4B", "#4CAF50", "#FF9800", "#9C27B0", "#00BCD4"]
        var seen = Set<String>()
        var colorIdx = 0
        for row in table {
            guard row.count >= 2 else { continue }
            let key = "\(row[0])-\(row[1])"
            if !seen.contains(key) {
                seen.insert(key)
                let subject = Subject(name: row[0], teacher: row[1],
                                      colorHex: colors[colorIdx % colors.count])
                modelContext.insert(subject)
                colorIdx += 1
            }
        }
        try? modelContext.save()
    }
}
