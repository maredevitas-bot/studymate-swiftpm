import SwiftUI
import PDFKit
import PencilKit
import VisionKit
import SwiftData

struct MaterialImportView: View {
    let subject: Subject
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedType: MaterialType = .ppt
    @State private var drawing = PKDrawing()
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showPDFPicker = false
    @State private var showScanner = false
    @State private var scannedImages: [UIImage] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("자료 제목", text: $title)
                    Picker("종류", selection: $selectedType) {
                        Label("PPT (PDF)", systemImage: "doc.richtext").tag(MaterialType.ppt)
                        Label("필기 (펜슬)", systemImage: "pencil.tip").tag(MaterialType.note)
                    }
                    .pickerStyle(.segmented)
                }

                Section("파일 선택") {
                    if selectedType == .ppt {
                        // PDF 파일 가져오기
                        Button {
                            showPDFPicker = true
                        } label: {
                            Label("PDF 파일 선택", systemImage: "doc.badge.plus")
                        }

                        // 문서 스캔 (iOS 메모장과 동일)
                        Button {
                            showScanner = true
                        } label: {
                            Label("문서 스캔", systemImage: "doc.viewfinder")
                        }

                        // 스캔된 페이지 수 표시
                        if !scannedImages.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("\(scannedImages.count)페이지 스캔됨")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("다시 스캔") {
                                    scannedImages = []
                                    showScanner = true
                                }
                                .font(.caption).foregroundStyle(.blue)
                            }
                        }
                    } else {
                        // Apple Pencil 필기 캔버스
                        VStack(spacing: 0) {
                            Text("Apple Pencil 또는 손가락으로 필기하세요")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)

                            NoteCanvasView(drawing: $drawing)
                                .frame(height: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            Button("캔버스 지우기") {
                                drawing = PKDrawing()
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("자료 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isAnalyzing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if selectedType == .note {
                        Button("분석 시작") {
                            Task { await importAndAnalyze() }
                        }
                        .disabled(title.isEmpty || isAnalyzing || drawing.strokes.isEmpty)
                    } else if !scannedImages.isEmpty {
                        // 스캔 완료 후 분석 버튼 표시
                        Button("분석 시작") {
                            Task { await analyzeScan() }
                        }
                        .disabled(title.isEmpty || isAnalyzing)
                    } else {
                        // PDF 모드: 파일 선택 시 자동 분석
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
            .overlay {
                if isAnalyzing {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("AI 분석 중…")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .fileImporter(
                isPresented: $showPDFPicker,
                allowedContentTypes: [.pdf]
            ) { result in
                Task { await handlePDFImport(result: result) }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView {
                    scannedImages = $0
                    showScanner = false
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
        }
    }

    // 스캔된 이미지 분석
    private func analyzeScan() async {
        isAnalyzing = true
        errorMessage = nil
        do {
            try await analyzeAndSave(images: scannedImages, type: .ppt, drawingData: nil)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isAnalyzing = false }
    }

    private func importAndAnalyze() async {
        isAnalyzing = true
        errorMessage = nil

        // Render PKDrawing to UIImage
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let screenScale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 2.0
        let image = drawing.image(from: bounds, scale: screenScale)

        do {
            try await analyzeAndSave(images: [image], type: .note, drawingData: drawing.dataRepresentation())
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isAnalyzing = false }
    }

    private func handlePDFImport(result: Result<URL, Error>) async {
        guard case .success(let url) = result else { return }
        // Fix 2: Surface security-scoped resource access denial to the user
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run { errorMessage = "파일 접근 권한이 없습니다." }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let pdf = PDFDocument(url: url) else {
            errorMessage = "PDF를 열 수 없어요."
            return
        }
        isAnalyzing = true
        var images: [UIImage] = []
        for i in 0..<min(pdf.pageCount, 20) {
            if let page = pdf.page(at: i) {
                let bounds = page.bounds(for: .mediaBox)
                let renderer = UIGraphicsImageRenderer(size: bounds.size)
                let img = renderer.image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(bounds)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                images.append(img)
            }
        }
        do {
            try await analyzeAndSave(images: images, type: .ppt, drawingData: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false
    }

    // Fix 4: Removed @MainActor so heavy I/O (saveAll, analyzeImages) runs off the main thread.
    // Main-actor-bound operations (modelContext, dismiss) are wrapped in await MainActor.run {}.
    private func analyzeAndSave(images: [UIImage], type: MaterialType, drawingData: Data? = nil) async throws {
        let storage = ImageStorageService()
        let paths = try storage.saveAll(images: images)
        let analysis = try await AIClientFactory.current().analyzeImages(images, type: type)
        let materialTitle = await MainActor.run { title.isEmpty ? "자료 \(subject.materials.count + 1)" : title }
        let material = Material(
            type: type,
            title: materialTitle
        )
        material.imagePaths = paths
        material.extractedText = analysis.extractedText
        material.summary = analysis.summary
        material.highlights = analysis.highlights
        material.drawingData = drawingData
        material.subject = subject
        try await MainActor.run {
            modelContext.insert(material)
            try modelContext.save()
            dismiss()
        }
    }
}
