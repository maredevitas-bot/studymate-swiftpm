import SwiftUI
import PencilKit

struct MaterialDetailView: View {
    let material: Material

    var storedDrawing: PKDrawing {
        guard let data = material.drawingData,
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 필기 캔버스 (노트 타입만)
                if material.type == .note {
                    GroupBox {
                        let drawing = storedDrawing
                        NoteCanvasView(drawing: .constant(drawing), isEditable: false)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } label: {
                        Label("필기 내용", systemImage: "pencil.tip")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                }

                // Summary card
                if !material.summary.isEmpty {
                    GroupBox {
                        Text(material.summary)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("요약", systemImage: "doc.text")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                }

                // Highlights
                if !material.highlights.isEmpty {
                    GroupBox {
                        FlowLayout(spacing: 8) {
                            ForEach(material.highlights, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    } label: {
                        Label("핵심 키워드", systemImage: "tag")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                }

                // Full extracted text
                if !material.extractedText.isEmpty {
                    GroupBox {
                        Text(material.extractedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("추출된 전체 텍스트", systemImage: "text.alignleft")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                }

                // Loading state
                if material.extractedText.isEmpty {
                    ContentUnavailableView(
                        "분석 대기 중",
                        systemImage: "clock",
                        description: Text("AI가 자료를 분석하는 중이에요.")
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// Simple flow layout for keyword chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += maxHeight + spacing
                x = 0
                maxHeight = 0
            }
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
        return CGSize(width: width, height: y + maxHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var maxHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += maxHeight + spacing
                x = bounds.minX
                maxHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}
