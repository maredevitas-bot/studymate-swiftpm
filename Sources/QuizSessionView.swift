// StudyMate/Features/Quiz/QuizSessionView.swift
import SwiftUI

// MARK: - Timer Mode

enum QuizTimerMode: String, CaseIterable {
    case none      = "없음"
    case stopwatch = "시간 재기"
    case countdown = "제한 시간"
}

// MARK: - Session View

struct QuizSessionView: View {
    @Bindable var session: QuizSession
    let timerMode: QuizTimerMode
    let countdownLimit: Int          // 문제별 제한 시간(초), countdown 모드에서만 사용
    var onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var showResult = false

    // 전체 경과 시간 (스톱워치 방향, 항상 카운트업)
    @State private var totalSeconds = 0
    // 문제별 시간: stopwatch=경과(카운트업), countdown=남은(카운트다운)
    @State private var questionSeconds = 0
    @State private var showTimeUpAlert = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var sortedQuestions: [Question] {
        session.questions.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        NavigationStack {
            if showResult {
                QuizResultView(session: session, onDismiss: onComplete)
            } else {
                questionContent
            }
        }
        .onAppear { resetQuestionTimer() }
        .onReceive(tick) { _ in
            guard !showResult else { return }
            totalSeconds += 1
            tickQuestionTimer()
        }
        .alert("⏰ 시간 초과!", isPresented: $showTimeUpAlert) {
            Button("다음 문제") { advance(forced: true) }
            Button("계속 풀기", role: .cancel) { showTimeUpAlert = false }
        } message: {
            Text("제한 시간이 종료되었습니다.")
        }
    }

    // MARK: - Question Content

    @ViewBuilder
    private var questionContent: some View {
        if sortedQuestions.isEmpty {
            ContentUnavailableView("문제가 없습니다", systemImage: "questionmark.circle")
        } else {
            let question = sortedQuestions[currentIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoBar
                    if timerMode != .none {
                        HStack { Spacer(); perQuestionTimerView; Spacer() }
                    }
                    Divider()
                    Text(question.body)
                        .font(.title3)
                        .fontWeight(.medium)
                    TextEditor(text: Binding(
                        get: { question.userAnswer },
                        set: { question.userAnswer = $0 }
                    ))
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3))
                    )
                }
                .padding()
            }
            .navigationTitle("퀴즈")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(currentIndex < sortedQuestions.count - 1 ? "다음" : "완료") {
                        advance(forced: false)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Info Bar (문제 번호 + 전체 타이머)

    private var infoBar: some View {
        HStack {
            Text("문제 \(currentIndex + 1) / \(sortedQuestions.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if timerMode != .none {
                Label(formatTime(totalSeconds), systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Per-Question Timer View

    @ViewBuilder
    private var perQuestionTimerView: some View {
        if timerMode == .stopwatch {
            stopwatchBadge
        } else if timerMode == .countdown {
            countdownRing
        }
    }

    private var stopwatchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "stopwatch")
                .foregroundStyle(.blue)
            Text(formatTime(questionSeconds))
                .font(.system(.title2, design: .rounded).monospacedDigit().weight(.semibold))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.blue.opacity(0.1), in: Capsule())
    }

    private var countdownRing: some View {
        let pct = countdownLimit > 0 ? Double(questionSeconds) / Double(countdownLimit) : 0
        let color: Color = questionSeconds > countdownLimit / 3
            ? .blue
            : (questionSeconds > 10 ? .orange : .red)
        return ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: pct)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: questionSeconds)
            VStack(spacing: 1) {
                Text("\(questionSeconds)")
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text("초")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
    }

    // MARK: - Timer Logic

    private func tickQuestionTimer() {
        switch timerMode {
        case .none:
            break
        case .stopwatch:
            questionSeconds += 1
            if currentIndex < sortedQuestions.count {
                sortedQuestions[currentIndex].elapsedSeconds = questionSeconds
            }
        case .countdown:
            if questionSeconds > 0 {
                questionSeconds -= 1
            } else if !showTimeUpAlert {
                showTimeUpAlert = true
            }
        }
    }

    private func resetQuestionTimer() {
        switch timerMode {
        case .none:       questionSeconds = 0
        case .stopwatch:  questionSeconds = 0
        case .countdown:  questionSeconds = countdownLimit
        }
    }

    private func advance(forced: Bool) {
        showTimeUpAlert = false
        // 스톱워치: 현재 문제 소요 시간 저장
        if timerMode == .stopwatch, currentIndex < sortedQuestions.count {
            sortedQuestions[currentIndex].elapsedSeconds = questionSeconds
        }
        if currentIndex < sortedQuestions.count - 1 {
            currentIndex += 1
            resetQuestionTimer()
        } else {
            session.totalSeconds = totalSeconds
            session.completedAt = Date()
            showResult = true
        }
    }

    // MARK: - Helpers

    private func formatTime(_ secs: Int) -> String {
        String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}
