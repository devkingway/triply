import SwiftUI
import Photos
import UIKit

/// The trip's iCloud Shared Album: link one from Photos, then see everyone's photos here.
/// Apple doesn't let apps add to shared albums, so adding photos happens in the Photos app.
struct SharedAlbumView: View {
    @Bindable var trip: Trip
    @Environment(\.openURL) private var openURL

    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var albums: [PHAssetCollection] = []
    @State private var assets: [PHAsset] = []
    @State private var linked: PHAssetCollection?
    @State private var choosing = false
    @State private var viewing: PHAsset?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch status {
                case .authorized:
                    if let linked, !choosing {
                        albumHeader(linked)
                        photoGrid
                    } else {
                        albumChooser
                    }
                case .notDetermined:
                    accessCard(
                        title: "See your shared album here",
                        message: "Allow Triply to see your photos so it can show the iCloud Shared Album you link to this trip.",
                        button: "Allow access") { requestAccess() }
                case .limited:
                    accessCard(
                        title: "Full access needed",
                        message: "With \"Limited\" access, shared albums are hidden from apps. In Settings → Triply → Photos, choose Full Access.",
                        button: "Open Settings") { openSettings() }
                default:
                    accessCard(
                        title: "Photos access is off",
                        message: "Turn on access in Settings → Triply → Photos (Full Access) to show your shared album here.",
                        button: "Open Settings") { openSettings() }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { load() }
        .onAppear { load() }
        .fullScreenCover(item: Binding(get: { viewing.map(IdentifiedAsset.init) }, set: { viewing = $0?.asset })) { item in
            PhotoPager(assets: assets, start: item.asset) { viewing = nil }
        }
    }

    // MARK: - Linked album

    private func albumHeader(_ album: PHAssetCollection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.person.crop.fill")
                    .font(.app(.title3, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.localizedTitle ?? "Shared album")
                        .font(.app(.headline))
                    Text("\(assets.count) photo\(assets.count == 1 ? "" : "s") · iCloud Shared Album")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Change album", systemImage: "arrow.triangle.2.circlepath") {
                        withAnimation { choosing = true }
                    }
                    Button("Unlink from trip", systemImage: "link.badge.plus", role: .destructive) {
                        withAnimation {
                            trip.sharedAlbumID = nil
                            trip.sharedAlbumTitle = nil
                            linked = nil
                            assets = []
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.app(.title3))
                }
            }
            Button {
                // Photos has no link to one album, so this opens the app; the album is under Albums → Shared Albums.
                if let url = URL(string: "photos-redirect://") { openURL(url) }
            } label: {
                Label("Add photos in the Photos app", systemImage: "plus.square.on.square")
                    .font(.app(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            Text("Apple only lets you add to a shared album from Photos (Albums → Shared Albums). Pull down here to see new photos.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .cardStyle(padding: 14)
    }

    @ViewBuilder
    private var photoGrid: some View {
        if assets.isEmpty {
            ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle",
                                   description: Text("Photos added to this shared album by you or your friends show up here."))
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    Button { viewing = asset } label: {
                        AssetThumbnail(asset: asset)
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Choosing an album

    @ViewBuilder
    private var albumChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a shared album for \(trip.name)")
                .font(.app(.headline))
                .padding(.horizontal, 4)
            if albums.isEmpty {
                ContentUnavailableView {
                    Label("No shared albums", systemImage: "rectangle.stack.badge.person.crop")
                } description: {
                    Text("Create one in Photos: Albums → + → New Shared Album, and invite your travel friends. Then pull down here to refresh.")
                } actions: {
                    Button("Open Photos") {
                        if let url = URL(string: "photos-redirect://") { openURL(url) }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(albums.enumerated()), id: \.element.localIdentifier) { index, album in
                        if index > 0 { Divider().padding(.leading, 76) }
                        Button { link(album) } label: {
                            AlbumRow(album: album, isLinked: album.localIdentifier == trip.sharedAlbumID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if linked != nil {
                Button("Cancel") { withAnimation { choosing = false } }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            Text("Only iCloud Shared Albums are listed. Everyone in the album can add photos from their own iPhone.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func accessCard(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "photo.stack")
        } description: {
            Text(message)
        } actions: {
            Button(button, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Photos

    private func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
            Task { @MainActor in
                status = newStatus
                load()
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func load() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized else { return }
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
        var list: [PHAssetCollection] = []
        result.enumerateObjects { album, _, _ in list.append(album) }
        albums = list.sorted { ($0.localizedTitle ?? "") < ($1.localizedTitle ?? "") }

        if let id = trip.sharedAlbumID,
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            linked = album
            loadAssets(album)
        } else {
            linked = nil
            assets = []
        }
    }

    private func loadAssets(_ album: PHAssetCollection) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: album, options: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
    }

    private func link(_ album: PHAssetCollection) {
        Haptics.tap()
        withAnimation {
            trip.sharedAlbumID = album.localIdentifier
            trip.sharedAlbumTitle = album.localizedTitle
            linked = album
            choosing = false
            loadAssets(album)
        }
        Toaster.shared.show("Linked \(album.localizedTitle ?? "shared album")", systemImage: "photo.stack.fill")
    }
}

/// Wraps an asset so it can drive `fullScreenCover(item:)`.
private struct IdentifiedAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// One shared album in the chooser: cover photo, name, photo count.
private struct AlbumRow: View {
    let album: PHAssetCollection
    let isLinked: Bool

    private var cover: PHAsset? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(in: album, options: options).firstObject
    }

    private var count: Int { PHAsset.fetchAssets(in: album, options: nil).count }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let cover {
                    AssetThumbnail(asset: cover)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGray5))
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(album.localizedTitle ?? "Shared album")
                    .font(.app(.body, .semibold))
                    .foregroundStyle(.primary)
                Text("\(count) photo\(count == 1 ? "" : "s")")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLinked {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A square thumbnail of a photo or video from the library (downloads from iCloud if needed).
struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Color(.systemGray5)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.app(.caption2, .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                image = await PhotoLoader.image(for: asset, side: 300)
            }
    }
}

/// Full-screen swipeable viewer for the album's photos.
private struct PhotoPager: View {
    let assets: [PHAsset]
    let start: PHAsset
    let close: () -> Void
    @State private var selection: String = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    FullPhoto(asset: asset).tag(asset.localIdentifier)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.app(.title))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.25))
            }
            .padding()
        }
        .onAppear { selection = start.localIdentifier }
    }
}

private struct FullPhoto: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: asset.localIdentifier) {
            image = await PhotoLoader.image(for: asset, side: 1600)
        }
    }
}

/// Loads library images, allowing iCloud downloads (shared album photos live in iCloud).
enum PhotoLoader {
    static func image(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
