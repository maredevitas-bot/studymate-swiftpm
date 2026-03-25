import SwiftUI
import PencilKit

struct NoteCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isEditable: Bool = true

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        // Apple Pencil만 필기 가능, 손가락은 스크롤·확대/축소
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.delegate = context.coordinator

        if isEditable {
            let toolPicker = PKToolPicker()
            toolPicker.setVisible(true, forFirstResponder: canvas)
            toolPicker.addObserver(canvas)
            context.coordinator.toolPicker = toolPicker
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var toolPicker: PKToolPicker?

        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}
