import Foundation
import SwiftData
import UserNotifications

/// Local notifications for flights: "Check-in opens" and "Leave for the airport in 3 hours".
enum FlightReminders {
    /// Online check-in usually opens 24–48 h before departure; remind at 48 h.
    static let checkInLead: TimeInterval = 48 * 3600
    /// Reminder 6 h before departure saying "leave in 3 hours", so you reach the airport ~3 h early.
    static let leaveLead: TimeInterval = 6 * 3600
    private static let prefix = "flight-"

    struct Reminder {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// The reminders for one flight (including ones already in the past).
    static func reminders(for flight: Flight) -> [Reminder] {
        let key = "\(prefix)\(Int(flight.createdAt.timeIntervalSince1970 * 1000))"
        let name = flight.title.isEmpty ? "Your flight" : flight.title
        let route = "\(flight.fromCode) → \(flight.toCode)"
        let departs = "\(flight.departureDateText) \(flight.departureTimeText)"
        let terminal = flight.fromTerminal.isEmpty ? "" : ", Terminal \(flight.fromTerminal)"
        return [
            Reminder(id: "\(key)-checkin",
                     date: flight.departure.addingTimeInterval(-checkInLead),
                     title: "✈️ Check-in opens for \(name)",
                     body: "\(route) departs \(departs). Online check-in is usually open now\(flight.bookingReference.isEmpty ? "" : " · Ref \(flight.bookingReference)")."),
            Reminder(id: "\(key)-leave",
                     date: flight.departure.addingTimeInterval(-leaveLead),
                     title: "🧳 Leave for the airport in 3 hours",
                     body: "\(name) \(route) departs at \(flight.departureTimeText) from \(flight.fromCity)\(terminal). Aim to arrive 3 hours early."),
        ]
    }

    /// Asks for notification permission (shown once by iOS). Returns whether reminders can be sent.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default: return false
        }
    }

    /// Replaces all scheduled flight reminders with ones for the current flights.
    @MainActor
    static func sync(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }

        let flights = (try? context.fetch(FetchDescriptor<Flight>())) ?? []
        for flight in flights where flight.remindersOn {
            for reminder in reminders(for: flight) {
                let seconds = reminder.date.timeIntervalSinceNow
                guard seconds > 1 else { continue }   // already passed
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                // A time interval fires at the same moment even if you change time zone while travelling.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }
}
