import SwiftUI
import SwiftData
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// A form section to add, view and remove screenshots / PDFs for a booking.
struct AttachmentsSection: View {
    let title: String
    let footer: String
    let attachments: [HotelAttachment]
    /// Called with (data, fileName, isPDF) for each new file.
    let onAdd: (Data, String, Bool) -> Void

    @Environment(\.modelContext) private var context
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var previewURL: URL?

    var body: some View {
        Section {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment)
                                .onTapGesture { previewURL = attachment.temporaryURL() }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        context.delete(attachment)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .quickLookPreview($previewURL)
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                Label("Add screenshot or photo", systemImage: "photo.on.rectangle")
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for (offset, item) in items.enumerated() {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                            onAdd(jpeg, "Document-\(attachments.count + offset + 1).jpg", false)
                        }
                    }
                    photoItems = []
                }
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("Add PDF from Files", systemImage: "doc.fill")
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls { importFile(url) }
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func importFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
        onAdd(data, url.lastPathComponent, isPDF)
    }
}

struct AttachmentThumbnail: View {
    let attachment: HotelAttachment

    var body: some View {
        Group {
            if !attachment.isPDF, let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.app(.largeTitle))
                        .foregroundStyle(.red)
                    Text(attachment.fileName)
                        .font(.app(.caption2))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
            }
        }
        .frame(width: 90, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }
}
