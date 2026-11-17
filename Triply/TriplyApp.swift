import SwiftUI
import SwiftData
import PopupView
import WidgetKit

@main
struct TriplyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Clean up leftovers (old data copy, empty space, temp files) once at launch.
    @State private var container = TriplyApp.loadContainer(cleanUp: true)
    @State private var seenChange = SharedStore.lastExternalChange
    @State private var toaster = Toaster.shared
    @State private var router = AppRouter.shared
    @AppStorage(AppAppearance.storageKey, store: AppAppearance.store) private var appearance = AppAppearance.system

    init() {
        AppFont.register()
        AppFont.styleSystemControls()
        // Back buttons (and other bar buttons iOS draws) in Triply teal, like the Edit button.
        let teal = UIColor(Theme.teal)
        UINavigationBar.appearance().tintColor = teal
        UIBarButtonItem.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = teal
        // The back arrow itself: a teal chevron drawn as-is (iOS otherwise keeps it white/black).
        if let chevron = UIImage(systemName: "chevron.backward",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))?
            .withTintColor(teal, renderingMode: .alwaysOriginal) {
            UINavigationBar.appearance().backIndicatorImage = chevron
            UINavigationBar.appearance().backIndicatorTransitionMaskImage = chevron
        }
    }

    var body: some Scene {
        WindowGroup {
            TripListView()
                // A new container (after a share) rebuilds the screens with fresh data.
                .id(ObjectIdentifier(container))
                // Poppins everywhere text doesn't pick its own style.
                .font(.app(.body))
                .tint(Theme.teal)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { router.handle($0) }
                .task { await FlightReminders.sync(in: container.mainContext) }
                .popup(item: $toaster.current) { toast in
                    ToastView(toast: toast)
                } customize: {
                    $0.type(.floater())
                        .position(.top)
                        .animation(.spring(duration: 0.4))
                        .autohideIn(2.2)
                        .dragToDismiss(true)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Keep the widget and flight reminders up to date with any changes.
                WidgetCenter.shared.reloadAllTimelines()
                Task { @MainActor in await FlightReminders.sync(in: container.mainContext) }
            }
            // Pick up links saved from Instagram/Facebook while the app was in the background.
            guard phase == .active else { return }
            let latest = SharedStore.lastExternalChange
            if latest != seenChange {
                seenChange = latest
                container = TriplyApp.loadContainer()
            }
        }
    }

    private static func loadContainer(cleanUp: Bool = false) -> ModelContainer {
        // Right after an app update the stored data is upgraded to the new format. If the widget opens
        // the same data at that moment it can be briefly locked, so wait a little and try again
        // instead of crashing.
        var lastError: Error?
        for attempt in 0..<6 {
            do {
                return try SharedStore.makeContainer(cleanUp: cleanUp && attempt == 0)
            } catch {
                lastError = error
                print("Triply: opening data failed (try \(attempt + 1)): \(error)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        fatalError("Could not open Triply data: \(String(describing: lastError))")
    }
}
