import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

@available(macOS 14.0, *)
enum WindowPreviewProvider {
    enum PreviewError: Error {
        case missingImage
    }

    static func loadImages(
        for windowIDs: [CGWindowID],
        targetSize: CGSize
    ) async throws -> [CGWindowID: NSImage] {
        AppLogger.preview.info(
            "WindowPreviewProvider starting requestedWindowIDs=\(windowIDs.count, privacy: .public) targetWidth=\(Int(targetSize.width), privacy: .public) targetHeight=\(Int(targetSize.height), privacy: .public)"
        )
        let shareableContent = try await SCShareableContent.current
        AppLogger.preview.info(
            "WindowPreviewProvider shareableContent windows=\(shareableContent.windows.count, privacy: .public)"
        )
        let windowsByID = Dictionary(uniqueKeysWithValues: shareableContent.windows.map { ($0.windowID, $0) })

        var images: [CGWindowID: NSImage] = [:]
        var missingWindowIDs: [CGWindowID] = []
        for windowID in windowIDs {
            guard let window = windowsByID[windowID] else {
                missingWindowIDs.append(windowID)
                continue
            }

            if let image = try await captureImage(for: window, targetSize: targetSize) {
                images[windowID] = image
            }
        }

        if !missingWindowIDs.isEmpty {
            AppLogger.preview.error(
                "WindowPreviewProvider could not match \(missingWindowIDs.count, privacy: .public) requested windowIDs in SCShareableContent"
            )
        }

        AppLogger.preview.info(
            "WindowPreviewProvider returning images=\(images.count, privacy: .public)"
        )

        return images
    }

    private static func captureImage(
        for window: SCWindow,
        targetSize: CGSize
    ) async throws -> NSImage? {
        let windowID = window.windowID
        let windowTitle = window.title ?? "<untitled>"
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(targetSize.width.rounded())
        configuration.height = Int(targetSize.height.rounded())
        AppLogger.preview.info(
            "captureImage windowID=\(windowID, privacy: .public) title=\(windowTitle, privacy: .public) width=\(configuration.width, privacy: .public) height=\(configuration.height, privacy: .public)"
        )

        let cgImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                AppLogger.preview.error(
                    "captureImage failed windowID=\(windowID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                continuation.resume(throwing: error ?? PreviewError.missingImage)
            }
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
