// StudyMate/Features/Quiz/QuizSetupView.swift
import SwiftUI
import SwiftData

struct QuizSetupView: View {
    var subject: Subject
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMaterials: Set<PersistentIdentifier> = []
    @State private var difficulty = "보통"
    @State private var questionCount = 3
    @State private var timerMode: QuizTimerMode = .none
    @State private var countdownSeconds = 60
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedSession: QuizSession?

    let difficulties = ["쉬움", "보통", "어려움"]

    var analyzedMaterials: [Material] {
        subject.materials.filter { !$0.extractedText.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("자료 선택 (복수 선택 가능)") {
                    if analyzedMaterials.isEmpty {
                        Text("분석된 자료가 없습니다. 자료를 먼저 추가하고 분석해주세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(analyzedMaterials) { material in
                            Toggle(material.title, isOn: Binding(
                                get: { selectedMaterials.contains(material.id) },
                                set: { if $0 { selectedMaterials.insert(material.id) } else { selectedMaterials.remove(material.id) } }
                            ))
                        }
                    }
                }
                Section("퀴즈 설정") {
                    Picker("난이도", selection: $difficulty) {
                        ForEach(difficulties, id: \.self) { Text($0) }
                    }
                    Stepper("문제 수: \(questionCount)개", value: $questionCount, in: 1...5)
                }
                Section("타이머") {
                    Picker("모드", selection: $timerMode) {
                        ForEach(QuizTimerMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if timerMode == .countdown {
                        Stepper("문제당 \(countdownSeconds)초", value: $countdownSeconds,
                                in: 30...300, step: 30)
                    }
                    if timerMode != .none {
                        Label(timerMode == .stopwatch
                              ? "문제별 경과 시간과 전체 시간을 측정합니다"
                              : "제한 시간 초과 시 알림이 표시됩니다",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("퀴즈 생성")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("생성") { Task { await generateQuiz() } }
                        .disabled(selectedMaterials.isEmpty || isGenerating)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .overlay {
                if isGenerating {
                    ProgressView("문제 생성 중...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .fullScreenCover(item: $generatedSession) { session in
                QuizSessionView(
                    session: session,
                    timerMode: timerMode,
                    countdownLimit: countdownSeconds,
                    onComplete: { dismiss() }
                )
            }
        }
    }

    private func generateQuiz() async {
        isGenerating = true
        errorMessage = nil
        let combinedText = analyzedMaterials
            .filter { selectedMaterials.contains($0.id) }
            .map(\.extractedText).joined(separator: "\n\n")
        do {
            let generated = try await AIClientFactory.current().generateQuiz(
                from: combinedText, count: questionCount, difficulty: difficulty)
            let session = QuizSession(subject: subject)
            modelContext.insert(session)
            generated.enumerated().forEach { idx, q in
                let question = Question(body: q.body, scoringCriteria: q.scoringCriteria,
                                        modelAnswer: q.modelAnswer, displayOrder: idx)
                question.session = session
                session.questions.append(question)
                modelContext.insert(question)
            }
            try modelContext.save()
            generatedSession = session
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }
}
