// StudyMate/Features/Subjects/DocumentScannerView.swift
import SwiftUI
import VisionKit
import PDFKit

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanCompleted: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanCompleted: onScanCompleted, onCancel: onCancel)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var onScanCompleted: ([UIImage]) -> Void
        var onCancel: () -> Void

        init(onScanCompleted: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanCompleted = onScanCompleted
            self.onCancel = onCancel
        }

        // 스캔 완료 — 각 페이지를 UIImage로 수집
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            onScanCompleted(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}

// MARK: - 스캔 이미지 → PDF 변환 유틸리티
extension DocumentScannerView {
    /// 스캔된 UIImage 배열을 PDF Data로 변환
    static func imagesToPDF(_ images: [UIImage]) -> Data {
        let pdfDocument = PDFDocument()
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) {
                pdfDocument.insert(page, at: index)
            }
        }
        return pdfDocument.dataRepresentation() ?? Data()
    }
}
