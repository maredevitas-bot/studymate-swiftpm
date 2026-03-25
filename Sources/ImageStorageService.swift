import UIKit
import Foundation

enum ImageStorageError: Error, LocalizedError {
    case jpegConversionFailed
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .jpegConversionFailed: return "이미지를 JPEG으로 변환할 수 없어요."
        case .writeFailed(let e): return "이미지 저장 실패: \(e.localizedDescription)"
        }
    }
}

// Note: Not actor-isolated. All public methods are safe for sequential use but callers
// must ensure no concurrent writes to the same UUID path. Task 7 should use a single
// shared instance per view context to avoid concurrent writes.
final class ImageStorageService {
    private let materialsDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        materialsDir = docs.appendingPathComponent("materials", isDirectory: true)
        try? FileManager.default.createDirectory(at: materialsDir,
                                                  withIntermediateDirectories: true)
    }

    /// Saves a UIImage as JPEG to Documents/materials/<uuid>.jpg and returns the file path.
    func save(image: UIImage, uuid: String) throws -> String {
        let url = materialsDir.appendingPathComponent("\(uuid).jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ImageStorageError.jpegConversionFailed
        }
        do {
            try data.write(to: url)
        } catch {
            throw ImageStorageError.writeFailed(error)
        }
        return url.path
    }

    /// Loads a UIImage from the given file path. Returns nil if the file does not exist.
    func load(path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    /// Deletes the image file at the given path. Silently ignores missing files.
    func delete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Saves multiple images, each with a generated UUID filename. Returns paths in order.
    func saveAll(images: [UIImage]) throws -> [String] {
        try images.map { try save(image: $0, uuid: UUID().uuidString) }
    }
}
