import SwiftUI
import SwiftData

struct SubjectDetailView: View {
    @Bindable var subject: Subject
    @State private var showImport = false
    @State private var showQuiz = false

    private var analyzedMaterials: [Material] {
        subject.materials.filter { !$0.extractedText.isEmpty }
    }

    var body: some View {
        List {
            // Materials section
            Section("자료 (\(subject.materials.count))") {
                if subject.materials.isEmpty {
                    Text("아직 자료가 없어요")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(subject.materials.sorted(by: { $0.createdAt > $1.createdAt })) { material in
                        NavigationLink(destination: MaterialDetailView(material: material)) {
                            MaterialRowView(material: material)
                        }
                    }
                }
                Button {
                    showImport = true
                } label: {
                    Label("자료 추가", systemImage: "plus.circle")
                }
                .foregroundStyle(.blue)
            }

            // Quiz section
            Section("퀴즈") {
                Button {
                    showQuiz = true
                } label: {
                    Label("새 퀴즈 시작", systemImage: "brain")
                }
                .foregroundStyle(analyzedMaterials.isEmpty ? Color.secondary : Color.blue)
                .disabled(analyzedMaterials.isEmpty)

                if analyzedMaterials.isEmpty && !subject.materials.isEmpty {
                    Text("자료 분석이 완료되면 퀴즈를 시작할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let sessions = subject.quizSessions.sorted {
                    ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
                }
                ForEach(sessions.prefix(5)) { session in
                    QuizSessionRowView(session: session)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subject.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showImport) {
            MaterialImportView(subject: subject)
        }
        .sheet(isPresented: $showQuiz) {
            QuizSetupView(subject: subject)
        }
    }
}

private struct MaterialRowView: View {
    let material: Material

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: material.type == .ppt ? "doc.richtext" : "pencil.line")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title).font(.subheadline).fontWeight(.medium)
                Text(material.createdAt, style: .date)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !material.extractedText.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Text("분석 중...")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QuizSessionRowView: View {
    let session: QuizSession

    var body: some View {
        HStack {
            Image(systemName: "checkmark.square")
                .foregroundStyle(.secondary)
            if let completedAt = session.completedAt {
                Text(completedAt, style: .date)
                    .font(.subheadline)
            } else {
                Text("날짜 없음")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let score = session.scorePercent {
                Text("\(Int(score))점")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(score < 70 ? Color.red : Color.green)
            } else {
                Text("미완료")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
