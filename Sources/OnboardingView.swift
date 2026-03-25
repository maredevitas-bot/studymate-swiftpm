// StudyMate/Features/Onboarding/OnboardingView.swift
import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isOnboardingComplete: Bool
    @State private var geminiKey = ""
    @State private var step = 0
    private let keychain = KeychainProvider()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            if step == 0 { welcomeStep }
            else if step == 1 { geminiKeyStep }
            Spacer()
        }
        .padding()
        .animation(.easeInOut, value: step)
        .fullScreenCover(isPresented: Binding(
            get: { step == 2 },
            set: { _ in }
        )) {
            NavigationStack {
                SchoolSetupView(onComplete: {
                    isOnboardingComplete = true
                })
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("StudyMate")
                .font(.largeTitle).bold()

            Text("AI가 수업 자료를 분석해서\n퀴즈와 스터디 플랜을 만들어줘요")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            // 기능 요약 카드
            VStack(alignment: .leading, spacing: 12) {
                featureRow("doc.viewfinder", "PDF·필기 자료 분석", .blue)
                featureRow("questionmark.circle", "서술형 퀴즈 자동 생성", .purple)
                featureRow("calendar", "AI 스터디 플랜", .green)
                featureRow("chart.bar", "성취도 분석", .orange)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

            Button("시작하기") { step = 1 }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
        }
    }

    // MARK: - Step 1: Gemini API Key

    private var geminiKeyStep: some View {
        VStack(spacing: 20) {
            // 헤더
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Gemini API 키 입력")
                        .font(.title2).bold()
                    freeBadge
                }
                Text("Google AI Studio에서 무료로 발급받을 수 있어요")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            // 발급 안내
            VStack(alignment: .leading, spacing: 8) {
                Text("발급 방법")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                stepLabel("1", "aistudio.google.com 접속")
                stepLabel("2", "Google 계정으로 로그인")
                stepLabel("3", "Get API key → Create API key")
                stepLabel("4", "키 복사 후 아래에 붙여넣기")
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            // 키 입력
            SecureField("AIza...", text: $geminiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            // 버튼
            Button("다음") {
                keychain.saveGeminiKey(geminiKey)
                // Gemini를 기본 공급자로 설정
                UserDefaults.standard.set(AIProvider.gemini.rawValue, forKey: "aiProvider")
                step = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(geminiKey.isEmpty)

            Button("나중에 설정") { step = 2 }
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var freeBadge: some View {
        Text("무료")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green, in: Capsule())
    }

    private func stepLabel(_ num: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(num)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.blue, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
