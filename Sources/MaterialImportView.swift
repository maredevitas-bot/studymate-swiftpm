import SwiftUI
import PDFKit
import PencilKit
import VisionKit
import Vision
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
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run { errorMessage = "파일 접근 권한이 없습니다." }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let pdf = PDFDocument(url: url) else {
            await MainActor.run { errorMessage = "PDF를 열 수 없어요." }
            return
        }
        await MainActor.run { isAnalyzing = true }

        do {
            // 1단계: 모든 페이지를 로컬 OCR로 텍스트 추출 (API 호출 없음)
            let extractedText = try await extractTextFromPDF(pdf)

            // 2단계: 텍스트만으로 Gemini에 요약/키워드 요청 (이미지 0개, 1회 호출)
            try await analyzeAndSaveText(extractedText: extractedText, type: .ppt)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
        await MainActor.run { isAnalyzing = false }
    }

    /// PDF 전체 페이지를 로컬 Vision OCR로 텍스트 추출
    private func extractTextFromPDF(_ pdf: PDFDocument) async throws -> String {
        var pageTexts: [String] = []

        for i in 0..<min(pdf.pageCount, 20) {
            guard let page = pdf.page(at: i) else { continue }

            // PDFKit 내장 텍스트 우선 사용
            let pdfText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pdfText.count > 30 {
                pageTexts.append(pdfText)
                continue
            }

            // 텍스트 없는 페이지(이미지)는 Vision OCR로 처리
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(1024 / max(bounds.width, bounds.height), 2.0)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let img = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            if let cgImage = img.cgImage {
                let ocrText = try await recognizeText(from: cgImage)
                if !ocrText.isEmpty { pageTexts.append(ocrText) }
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    /// Vision 프레임워크로 로컬 OCR (한국어 + 영어)
    private func recognizeText(from cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) }
            catch { continuation.resume(throwing: error) }
        }
    }

    /// 텍스트만으로 AI 요약 요청 (이미지 없음 → 토큰 최소)
    private func analyzeAndSaveText(extractedText: String, type: MaterialType) async throws {
        let analysis = try await AIClientFactory.current().summarizeText(extractedText)
        let materialTitle = await MainActor.run { title.isEmpty ? "자료 \(subject.materials.count + 1)" : title }
        let material = Material(type: type, title: materialTitle)
        material.extractedText = extractedText
        material.summary = analysis.summary
        material.highlights = analysis.highlights
        material.subject = subject
        try await MainActor.run {
            modelContext.insert(material)
            try modelContext.save()
            dismiss()
        }
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
