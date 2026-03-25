// StudyMate/Features/Planner/ExamDateSetupView.swift
import SwiftUI
import SwiftData

struct ExamDateSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [Subject]
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("시험일 설정") {
                    DatePicker("시험 날짜", selection: $examDate,
                               in: Date()...,
                               displayedComponents: .date)
                }
                Section {
                    Text("AI가 과목별 퀴즈 점수와 자료량을 분석해서 최적의 복습 일정을 만들어줘요. 취약한 과목은 더 많이 배정됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("AI 플랜 생성")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("생성") { Task { await generatePlan() } }
                        .disabled(isGenerating || subjects.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .overlay {
                if isGenerating {
                    ProgressView("일정 생성 중...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func generatePlan() async {
        isGenerating = true
        errorMessage = nil
        let subjectSummaries = subjects.map { s in
            (name: s.name, avgScore: s.averageScore, materialCount: s.materials.count)
        }
        do {
            let items = try await AIClientFactory.current().generateStudyPlan(
                subjects: subjectSummaries, examDate: examDate)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for item in items {
                guard let date = formatter.date(from: item.date) else { continue }
                let entry = PlanEntry(date: date, subjectName: item.subjectName,
                                      topic: item.topic, isAIGenerated: true)
                modelContext.insert(entry)
            }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }
}
