import SwiftUI

struct SettingsTabView: View {
    @AppStorage("aiProvider") private var aiProviderRaw: String = AIProvider.gemini.rawValue
    @State private var geminiKeyInput = ""
    @State private var claudeKeyInput = ""
    @State private var geminiSaved = false
    @State private var claudeSaved = false
    @State private var geminiFailed = false
    @State private var claudeFailed = false
    @State private var showClaudeSection = false
    private let keychain = KeychainProvider()

    var selectedProvider: AIProvider {
        AIProvider(rawValue: aiProviderRaw) ?? .gemini
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── AI 공급자 ──────────────────────────────
                Section {
                    Picker("AI 공급자", selection: $aiProviderRaw) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.description).tag(provider.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    providerInfoRow
                } header: {
                    Text("AI 공급자")
                }

                // ── Gemini API 키 ──────────────────────────
                Section {
                    SecureField("AIza...", text: $geminiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: geminiKeyInput) { geminiSaved = false; geminiFailed = false }

                    Button("저장") {
                        let ok = keychain.saveGeminiKey(geminiKeyInput)
                        geminiSaved = ok; geminiFailed = !ok
                        if ok {
                            UserDefaults.standard.set(AIProvider.gemini.rawValue, forKey: "aiProvider")
                        }
                    }
                    .disabled(geminiKeyInput.isEmpty)

                    if geminiSaved {
                        Label("저장됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if geminiFailed {
                        Label("저장 실패", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }

                    Link("aistudio.google.com 에서 무료 발급",
                         destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.caption)
                } header: {
                    HStack {
                        Text("Gemini API 키")
                        Spacer()
                        Text("무료")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }

                // ── Claude API 키 (고급 · 접기/펼치기) ────
                Section {
                    DisclosureGroup("Claude API 키 (고급)", isExpanded: $showClaudeSection) {
                        SecureField("sk-ant-...", text: $claudeKeyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: claudeKeyInput) { claudeSaved = false; claudeFailed = false }

                        Button("저장") {
                            let ok = keychain.save(apiKey: claudeKeyInput)
                            claudeSaved = ok; claudeFailed = !ok
                        }
                        .disabled(claudeKeyInput.isEmpty)

                        if claudeSaved {
                            Label("저장됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        if claudeFailed {
                            Label("저장 실패", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }

                        Label("api.anthropic.com 에서 유료 발급", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── 컴시간 설정 ────────────────────────────
                Section("컴시간 설정") {
                    NavigationLink("학교 / 학년 / 반 설정") {
                        SchoolSetupView()
                    }
                }
            }
            .navigationTitle("설정")
            .onAppear(perform: loadKeys)
        }
    }

    // MARK: - Provider Info

    @ViewBuilder
    private var providerInfoRow: some View {
        if selectedProvider == .gemini {
            Label("분당 15회 · 하루 1,500회 무료 — 개인 학습용으로 충분합니다",
                  systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("사용량에 따라 비용이 발생합니다 (입력·출력 토큰 과금)",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Load

    private func loadKeys() {
        if let key = keychain.loadGeminiKey() {
            geminiKeyInput = key; geminiSaved = true
        }
        if let key = keychain.loadAPIKey() {
            claudeKeyInput = key; claudeSaved = true
        }
    }
}
