import SwiftUI
import SwiftData
import PencilKit

// MARK: - 메모 에디터 (멀티페이지)

struct NotebookEditorView: View {
    @Bindable var notebook: NoteBook
    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex = 0
    @State private var drawing = PKDrawing()
    @State private var showDeleteAlert = false
    @State private var showRenameAlert = false
    @State private var newTitle = ""

    var sortedPages: [NotePage] { notebook.sortedPages }

    var body: some View {
        VStack(spacing: 0) {
            // 캔버스 (전체 남은 영역 사용)
            NoteCanvasView(drawing: $drawing)
                .background(Color.white)

            // 하단 썸네일 스트립
            thumbnailStrip
        }
        .navigationTitle(notebook.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .alert("페이지 삭제", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) { deleteCurrentPage() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("현재 페이지의 필기가 사라집니다.")
        }
        .alert("메모 이름 변경", isPresented: $showRenameAlert) {
            TextField("제목", text: $newTitle)
            Button("확인") { if !newTitle.isEmpty { notebook.title = newTitle } }
            Button("취소", role: .cancel) {}
        }
        .onAppear {
            if notebook.pages.isEmpty { appendNewPage() }
            loadPage(at: 0)
        }
        .onDisappear { saveCurrentPage() }
    }

    // MARK: - 썸네일 스트립

    var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 10) {
                    ForEach(Array(sortedPages.enumerated()), id: \.element.persistentModelID) { i, page in
                        PageThumbView(
                            drawingData: page.drawingData,
                            index: i,
                            isSelected: i == currentIndex
                        )
                        .id(i)
                        .onTapGesture {
                            guard i != currentIndex else { return }
                            saveCurrentPage()
                            currentIndex = i
                            loadPage(at: i)
                        }
                    }

                    // 페이지 추가 버튼
                    Button(action: addPage) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.08))
                            .frame(width: 46, height: 64)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: currentIndex) { _, newVal in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newVal, anchor: .center)
                }
            }
        }
        .frame(height: 90)
        .background(.bar)
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    newTitle = notebook.title
                    showRenameAlert = true
                } label: {
                    Label("이름 변경", systemImage: "pencil")
                }

                Divider()

                Button(action: addPage) {
                    Label("페이지 추가", systemImage: "plus.rectangle.on.rectangle")
                }

                if sortedPages.count > 1 {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("현재 페이지 삭제", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - 페이지 관리

    private func loadPage(at index: Int) {
        guard sortedPages.indices.contains(index) else { return }
        let data = sortedPages[index].drawingData
        drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
    }

    private func saveCurrentPage() {
        guard sortedPages.indices.contains(currentIndex) else { return }
        sortedPages[currentIndex].drawingData = drawing.dataRepresentation()
        notebook.updatedAt = Date()
    }

    private func appendNewPage() {
        let page = NotePage(pageIndex: notebook.pages.count)
        modelContext.insert(page)
        notebook.pages.append(page)
    }

    private func addPage() {
        saveCurrentPage()
        appendNewPage()
        currentIndex = sortedPages.count - 1
        drawing = PKDrawing()
    }

    private func deleteCurrentPage() {
        guard sortedPages.count > 1 else { return }
        let toDelete = sortedPages[currentIndex]

        // 관계에서 먼저 제거, 그 다음 컨텍스트 삭제
        notebook.pages.removeAll { $0.persistentModelID == toDelete.persistentModelID }
        modelContext.delete(toDelete)

        // 남은 페이지 인덱스 재정렬
        for (i, p) in notebook.sortedPages.enumerated() { p.pageIndex = i }

        let newIdx = min(currentIndex, notebook.pages.count - 1)
        currentIndex = newIdx
        loadPage(at: newIdx)
    }
}

// MARK: - 페이지 썸네일

private struct PageThumbView: View {
    let drawingData: Data
    let index: Int
    let isSelected: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: 46, height: 64)
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                .overlay {
                    if let img = thumbnail {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? Color.blue : Color.gray.opacity(0.25),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }

            // 페이지 번호 뱃지
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? Color.blue : Color.black.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(3)
        }
        .task(id: drawingData.count) {
            guard let d = try? PKDrawing(data: drawingData), !d.strokes.isEmpty else {
                thumbnail = nil; return
            }
            let rect = CGRect(x: 0, y: 0, width: 210, height: 297)
            thumbnail = d.image(from: rect, scale: 0.25)
        }
    }
}

// MARK: - 메모 목록 & 생성 시트

struct NotebookListSection: View {
    @Bindable var subject: Subject
    @Environment(\.modelContext) private var modelContext
    @State private var showNewNote = false
    @State private var notebookToDelete: NoteBook?

    var sortedNotebooks: [NoteBook] {
        subject.notebooks.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Section("메모 (\(subject.notebooks.count))") {
            if subject.notebooks.isEmpty {
                Text("아직 메모가 없어요")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(sortedNotebooks) { notebook in
                    NavigationLink(destination: NotebookEditorView(notebook: notebook)) {
                        NotebookRowView(notebook: notebook)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            notebookToDelete = notebook
                        } label: {
                            Label("삭제", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                showNewNote = true
            } label: {
                Label("새 메모 파일", systemImage: "plus.circle")
            }
            .foregroundStyle(.blue)
        }
        .sheet(isPresented: $showNewNote) {
            NewNotebookSheet(subject: subject)
        }
        .confirmationDialog(
            "'\(notebookToDelete?.title ?? "")' 메모를 삭제할까요?",
            isPresented: Binding(
                get: { notebookToDelete != nil },
                set: { if !$0 { notebookToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let nb = notebookToDelete { modelContext.delete(nb) }
                notebookToDelete = nil
            }
            Button("취소", role: .cancel) { notebookToDelete = nil }
        } message: {
            Text("모든 페이지가 삭제됩니다.")
        }
    }
}

private struct NotebookRowView: View {
    let notebook: NoteBook
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 36, height: 44)
                Image(systemName: "note.text")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(notebook.title)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text("\(notebook.pages.count)페이지")
                    Text("·")
                    Text(notebook.updatedAt, style: .relative) + Text(" 전")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct NewNotebookSheet: View {
    let subject: Subject
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("메모 제목 (예: 1단원 필기)", text: $title)
                        .onSubmit { if !title.isEmpty { create() } }
                }
                Section {
                    Text("새 메모는 빈 페이지 1장으로 시작합니다.\n이후 페이지를 자유롭게 추가할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("새 메모 파일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("만들기") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        let notebook = NoteBook(title: title.trimmingCharacters(in: .whitespaces), subject: subject)
        modelContext.insert(notebook)
        let firstPage = NotePage(pageIndex: 0)
        modelContext.insert(firstPage)
        notebook.pages.append(firstPage)
        subject.notebooks.append(notebook)
        dismiss()
    }
}
