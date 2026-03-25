import SwiftUI
import SwiftData

struct SubjectsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Subject.name) private var subjects: [Subject]
    @State private var showAddSheet = false
    @State private var selectedSubject: Subject?
    @State private var subjectToDelete: Subject?

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                subjectList
                    .navigationTitle("과목")
                    .toolbar { addButton; editButton }
                    .sheet(isPresented: $showAddSheet) {
                        AddSubjectSheet(subjectCount: subjects.count)
                    }
            }
        } else {
            NavigationSplitView {
                subjectList
                    .navigationTitle("과목")
                    .toolbar { addButton; editButton }
                    .sheet(isPresented: $showAddSheet) {
                        AddSubjectSheet(subjectCount: subjects.count)
                    }
            } detail: {
                if let subject = selectedSubject {
                    SubjectDetailView(subject: subject)
                } else {
                    ContentUnavailableView("과목을 선택하세요",
                        systemImage: "book.closed",
                        description: Text("왼쪽에서 과목을 선택하면\n상세 내용이 표시됩니다"))
                }
            }
        }
    }

    var groupedSubjects: [(teacher: String, subjects: [Subject])] {
        let grouped = Dictionary(grouping: subjects, by: \.teacher)
        return grouped.map { (teacher: $0.key, subjects: $0.value) }
            .sorted { $0.teacher < $1.teacher }
    }

    var subjectList: some View {
        List(selection: $selectedSubject) {
            ForEach(groupedSubjects, id: \.teacher) { group in
                Section(group.teacher) {
                    ForEach(group.subjects) { subject in
                        NavigationLink(value: subject) {
                            SubjectRowView(subject: subject)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                subjectToDelete = subject
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.forEach { subjectToDelete = group.subjects[$0] }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if subjects.isEmpty {
                ContentUnavailableView(
                    "과목이 없어요",
                    systemImage: "books.vertical",
                    description: Text("설정에서 학교를 연동하거나\n+ 버튼으로 직접 추가하세요.")
                )
            }
        }
        .confirmationDialog(
            "'\(subjectToDelete?.name ?? "")' 과목을 삭제할까요?",
            isPresented: Binding(
                get: { subjectToDelete != nil },
                set: { if !$0 { subjectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let s = subjectToDelete { modelContext.delete(s) }
                subjectToDelete = nil
            }
            Button("취소", role: .cancel) { subjectToDelete = nil }
        } message: {
            Text("자료, 퀴즈 기록이 모두 삭제됩니다.")
        }
    }

    var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
            }
        }
    }

    var editButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            EditButton()
        }
    }

}

private struct SubjectRowView: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: subject.colorHex))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name).font(.headline)
                Text(subject.teacher).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let score = subject.averageScore {
                Text("\(Int(score))점")
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(score < 70 ? Color.red : Color.green)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddSubjectSheet: View {
    let subjectCount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var teacher = ""

    private let colors = ["#007AFF", "#FF6B6B", "#34C759", "#AF52DE", "#FF9500", "#8E8E93"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("과목명", text: $name)
                    TextField("선생님 이름", text: $teacher)
                }
            }
            .navigationTitle("과목 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        let color = colors[subjectCount % colors.count]
                        modelContext.insert(Subject(name: name, teacher: teacher, colorHex: color))
                        dismiss()
                    }
                    .disabled(name.isEmpty || teacher.isEmpty)
                }
            }
        }
    }
}
