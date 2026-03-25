// StudyMate/Features/Quiz/QuizResultView.swift
import SwiftUI

struct QuizResultView: View {
    @Bindable var session: QuizSession
    var onDismiss: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var selfScore: Double = 70
    @State private var scoreSaved = false

    var sortedQuestions: [Question] {
        session.questions.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("퀴즈 완료!")
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    if session.totalSeconds > 0 {
                        Label(formatTime(session.totalSeconds), systemImage: "timer")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.top)

                ForEach(sortedQuestions) { question in
                    questionReviewCard(question)
                    Divider()
                }

                selfAssessmentSection
            }
            .padding()
        }
        .onAppear {
            if let saved = session.scorePercent {
                selfScore = saved
                scoreSaved = true
            }
        }
        .navigationTitle("퀴즈 결과")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("닫기") { onDismiss() }
            }
        }
    }

    private func questionReviewCard(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("문제 \(question.displayOrder + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if question.elapsedSeconds > 0 {
                    Label(formatTime(question.elapsedSeconds), systemImage: "stopwatch")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(question.body)
                .font(.headline)

            GroupBox {
                Text(question.userAnswer.isEmpty ? "(답변 없음)" : question.userAnswer)
                    .foregroundStyle(question.userAnswer.isEmpty ? .secondary : .primary)
            } label: {
                Label("내 답변", systemImage: "pencil")
            }

            GroupBox {
                Text(question.scoringCriteria)
                    .foregroundStyle(.blue)
            } label: {
                Label("채점 기준", systemImage: "checkmark.circle")
            }

            GroupBox {
                Text(question.modelAnswer)
                    .foregroundStyle(.green)
            } label: {
                Label("모범 답안", systemImage: "star")
            }
        }
    }

    private func formatTime(_ secs: Int) -> String {
        String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    private var selfAssessmentSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                Text("채점 기준을 보고 스스로 점수를 매겨보세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $selfScore, in: 0...100, step: 5)

                Text("\(Int(selfScore))점")
                    .font(.title2)
                    .bold()

                Button("점수 저장") {
                    session.scorePercent = selfScore
                    try? modelContext.save()
                    scoreSaved = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(scoreSaved)

                if scoreSaved {
                    Label("저장됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
        } label: {
            Label("자가 평가", systemImage: "slider.horizontal.3")
        }
    }
}
