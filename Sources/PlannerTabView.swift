// StudyMate/Features/Planner/PlannerTabView.swift
import SwiftUI
import SwiftData

struct PlannerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \PlanEntry.date) private var entries: [PlanEntry]
    @Query private var subjects: [Subject]
    @State private var showExamSetup = false
    @State private var showAddEntry = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .compact {
                    // iPhone: 기존 VStack 레이아웃
                    VStack(spacing: 0) {
                        datePicker
                        entryList
                    }
                } else {
                    // iPad: 좌우 분할 — 왼쪽 캘린더, 오른쪽 일정 목록
                    HStack(alignment: .top, spacing: 0) {
                        datePicker
                            .frame(maxWidth: 380)
                        Divider()
                        entryList
                    }
                }
            }
            .navigationTitle("플래너")
            .toolbar { plannerToolbar }
            .sheet(isPresented: $showExamSetup) { ExamDateSetupView() }
            .sheet(isPresented: $showAddEntry) { AddPlanEntryView(date: selectedDate) }
        }
    }

    var datePicker: some View {
        DatePicker("날짜 선택", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .padding(.horizontal)
    }

    var entryList: some View {
        List {
            let dayEntries = entries.filter {
                Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
            }
            if dayEntries.isEmpty {
                Text("일정 없음").foregroundStyle(.secondary)
            } else {
                ForEach(dayEntries) { entry in
                    HStack {
                        Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(entry.isCompleted ? Color.green : Color.gray)
                            .onTapGesture { entry.isCompleted.toggle() }
                        VStack(alignment: .leading) {
                            Text(entry.subjectName).font(.headline)
                            Text(entry.topic).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entry.isAIGenerated {
                            Image(systemName: "brain")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        }
                    }
                }
                .onDelete { offsets in
                    let dayList = dayEntries
                    offsets.forEach { modelContext.delete(dayList[$0]) }
                }
            }
            Button { showAddEntry = true } label: {
                Label("일정 추가", systemImage: "plus")
            }
        }
        .listStyle(.insetGrouped)
    }

    var plannerToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showExamSetup = true } label: {
                Label("AI 플랜", systemImage: "brain")
            }
        }
    }
}

struct AddPlanEntryView: View {
    var date: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var subjects: [Subject]
    @State private var selectedSubject: Subject?
    @State private var topic = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("과목", selection: $selectedSubject) {
                    Text("선택").tag(nil as Subject?)
                    ForEach(subjects) { s in
                        Text(s.displayTitle).tag(s as Subject?)
                    }
                }
                TextField("복습 내용", text: $topic)
            }
            .navigationTitle("일정 추가")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("추가") {
                        guard let subject = selectedSubject else { return }
                        modelContext.insert(PlanEntry(date: date, subjectName: subject.name, topic: topic))
                        dismiss()
                    }.disabled(selectedSubject == nil || topic.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
    }
}
