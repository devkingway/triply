import SwiftUI
import LinkPresentation
import UIKit

/// A small picture for a shared link (the post's preview image, like Messages shows).
/// Loaded from the link each time it's needed and kept only in memory, never saved.
struct LinkThumbnail<Fallback: View>: View {
    let url: URL?
    var size: CGFloat = 40
    @ViewBuilder var fallback: () -> Fallback

    @State private var image: UIImage?
    /// Set once the link has been checked, so the grey box shows only while loading.
    @State private var finished = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous) }

    var body: some View {
        Group {
            if let image {
                // Grey behind the picture, so see-through logos and loading edges sit on a tile.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .background(Color(.systemGray5))
                    .clipShape(shape)
                    .transition(.opacity)
            } else if url != nil && !finished {
                // Loading: a grey tile the same size as the picture.
                shape
                    .fill(Color(.systemGray5))
                    .frame(width: size, height: size)
            } else {
                fallback()
                    .frame(width: size, height: size)
            }
        }
        .task(id: url) {
            guard let url else { return }
            let loaded = await LinkPreviewImages.image(for: url, maxSide: size * 3)
            withAnimation(.easeOut(duration: 0.2)) {
                image = loaded
                finished = true
            }
        }
    }
}

/// Fetches link preview pictures and keeps them in memory while the app runs.
@MainActor
enum LinkPreviewImages {
    private static let cache = NSCache<NSURL, UIImage>()
    /// Links with no picture, so they aren't fetched again this session.
    private static var missing = Set<URL>()
    private static var inFlight: [URL: Task<UIImage?, Never>] = [:]

    static func image(for url: URL, maxSide: CGFloat) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if missing.contains(url) { return nil }
        if let running = inFlight[url] { return await running.value }

        let task = Task<UIImage?, Never> {
            let provider = LPMetadataProvider()
            provider.timeout = 8
            guard let metadata = try? await provider.startFetchingMetadata(for: url),
                  let item = metadata.imageProvider ?? metadata.iconProvider,
                  let full = await load(item) else { return nil }
            return downscale(full, maxSide: maxSide)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache.setObject(result, forKey: url as NSURL) } else { missing.insert(url) }
        return result
    }

    private static func load(_ item: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            item.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }

    /// Shrinks the picture to thumbnail size so it uses little memory.
    private static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
