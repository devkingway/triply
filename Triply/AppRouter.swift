import Foundation

/// Handles tripple:// links from the widget and Control Center.
///  - tripple://add-expense → Add expense for the current trip
///  - tripple://today       → open the current trip (Today tab during a trip)
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// `tripID` is the trip chosen by the widget (nil = current trip).
    enum Request: Equatable { case addExpense(tripID: String?), openCurrentTrip }
    var pending: Request?

    func handle(_ url: URL) {
        guard url.scheme == "tripple" else { return }
        switch url.host() {
        case "add-expense":
            let tripID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "trip" })?.value
            pending = .addExpense(tripID: tripID)
        case "today", "trip": pending = .openCurrentTrip
        default: break
        }
    }
}
