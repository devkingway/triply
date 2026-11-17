import UIKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Entry point of the Share extension: hosts the SwiftUI share screen.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        AppFont.register()
        AppFont.styleSystemControls()
        super.viewDidLoad()

        let root: AnyView
        if let container = try? SharedStore.makeContainer() {
            root = AnyView(
                ShareView(
                    loadInput: { [weak self] in await self?.sharedInput() ?? SharedInput() },
                    onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                    onCancel: { [weak self] in
                        self?.extensionContext?.cancelRequest(withError: NSError(domain: "Triply", code: NSUserCancelledError))
                    }
                )
                .modelContainer(container)
                // Match the app's look: Triply teal, Poppins type, and the chosen light/dark setting.
                .tint(Color(UIColor { $0.userInterfaceStyle == .dark
                    ? UIColor(red: 0.22, green: 0.80, blue: 0.78, alpha: 1)
                    : UIColor(red: 0.0, green: 0.62, blue: 0.60, alpha: 1) }))
                .font(.app(.body))
                .preferredColorScheme(
                    AppAppearance(rawValue: AppAppearance.store.string(forKey: AppAppearance.storageKey) ?? "")?.colorScheme
                )
            )
        } else {
            root = AnyView(Text("Couldn't open Triply data. Open the Triply app once, then try again.").padding())
        }

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// Reads the shared link (and any caption text) from the share sheet.
    private func sharedInput() async -> SharedInput {
        var result = SharedInput()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if result.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                if let url = item as? URL, url.scheme?.hasPrefix("http") == true { result.url = url }
                else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { result.url = url }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let text = item as? String {
                result.text = text
                if result.url == nil { result.url = LinkExtractor.firstURL(in: text) }
            }
        }
        return result
    }
}

struct SharedInput {
    var url: URL?
    var text = ""
}
