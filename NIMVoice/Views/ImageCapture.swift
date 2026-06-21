import SwiftUI
import UIKit

/// A SwiftUI wrapper over `UIImagePickerController` for capturing a photo from
/// the camera (falling back to the photo library on devices/simulators without
/// a camera).
struct ImagePicker: UIViewControllerRepresentable {
    enum Source { case camera, library }

    let source: Source
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if source == .camera, UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Resizes + JPEG-compresses an image so its base64 encoding fits comfortably
/// under NVIDIA's ~180 KB inline-image limit for vision models.
enum ImageEncoder {
    /// Returns base64 (no data-URL prefix) or nil if encoding fails.
    static func jpegBase64(_ image: UIImage, maxBytes: Int) -> String? {
        let resized = resize(image, maxDimension: 768)
        var quality: CGFloat = 0.6
        var data = resized.jpegData(compressionQuality: quality)

        while let current = data, current.count > maxBytes, quality > 0.15 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }

        // Still too large? Shrink the dimensions further and try once more.
        if let current = data, current.count > maxBytes {
            let smaller = resize(image, maxDimension: 512)
            data = smaller.jpegData(compressionQuality: 0.4)
        }

        return data?.base64EncodedString()
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
