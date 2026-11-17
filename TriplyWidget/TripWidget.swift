import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Data

/// What the widgets show, read from Triply's shared data.
struct TripEntry: TimelineEntry {
    let date: Date
    /// False on the free-account build: the widget can't read the app's trips.
    var canReadTrips = true
    var tripID: String?
    var tripName: String?
    var status = ""
    var statusIcon = "airplane"
    var isDuring = false
    var remaining: Double?
    var spentToday: Double = 0
    var nextStop: String?
    var nextStopTime: Date?
    var thenStop: String?
    var thenStopTime: Date?

    static let placeholder = TripEntry(
        date: .now, tripID: nil, tripName: "Tokyo Winter", status: "Day 2 of 5", statusIcon: "location.fill",
        isDuring: true, remaining: 2763, spentToday: 465,
        nextStop: "Senso-ji", nextStopTime: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now),
        thenStop: "Tokyo Skytree", thenStopTime: Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: .now))

    /// Opens Add expense for this trip.
    var addExpenseURL: URL {
        var components = URLComponents(string: "tripple://add-expense")!
        if let tripID { components.queryItems = [URLQueryItem(name: "trip", value: tripID)] }
        return components.url!
    }
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        // Refresh every 30 minutes so "next stop" moves on through the day; the app also refreshes after changes.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [Self.load()], policy: .after(next)))
    }

    static func load() -> TripEntry {
        var entry = TripEntry(date: .now)
        guard SharedStore.isAppGroupAvailable else {
            entry.canReadTrips = false
            return entry
        }
        guard let container = try? SharedStore.makeContainer() else { return entry }
        let context = ModelContext(container)
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        guard let trip = Trip.focus(in: trips) else { return entry }
        entry.tripID = trip.widgetID
        entry.tripName = trip.name
        entry.status = trip.phaseText
        entry.statusIcon = trip.phaseIcon
        entry.remaining = trip.budget > 0 ? trip.remaining : nil

        // During the trip: today's upcoming stops. Before it: the first stops of Day 1.
        let day = trip.todayIndex ?? 0
        entry.isDuring = trip.todayIndex != nil
        if entry.isDuring { entry.spentToday = trip.spent(onDay: day) }
        let stops = trip.places(onDay: day)
        let next = entry.isDuring ? trip.nextStop(onDay: day) : stops.first
        if next == nil, entry.isDuring, !stops.isEmpty {
            entry.nextStop = "All done today ✓"
        }
        if let next {
            entry.nextStop = next.name
            entry.nextStopTime = next.time
            if let index = stops.firstIndex(where: { $0.id == next.id }), index + 1 < stops.count {
                entry.thenStop = stops[index + 1].name
                entry.thenStopTime = stops[index + 1].time
            }
        }
        return entry
    }
}

enum WidgetColors {
    static let teal = Color(red: 0.0, green: 0.62, blue: 0.60)
    static let blue = Color(red: 0.13, green: 0.42, blue: 0.86)
    static let gradient = LinearGradient(colors: [teal, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private func rm(_ value: Double) -> String {
    value.formatted(.currency(code: "MYR").precision(.fractionLength(0)))
}

// MARK: - Widget 1: Current trip

struct TripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TripWidget", provider: TripProvider()) { entry in
            TripWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors.gradient }
        }
        .configurationDisplayName("Current trip")
        .description("Trip name, status, money left and your next stop.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TripWidgetView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.tripName == nil {
                EmptyTripView(canReadTrips: entry.canReadTrips)
            } else {
                switch family {
                case .systemMedium: medium
                case .accessoryRectangular: lockScreen
                default: small
                }
            }
        }
        .widgetURL(URL(string: "tripple://today"))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.tripName ?? "").font(.app(.headline)).lineLimit(1)
            Label(entry.status, systemImage: entry.statusIcon)
                .font(.app(.caption, .bold))
                .opacity(0.9)
        }
    }

    @ViewBuilder
    private var money: some View {
        if let remaining = entry.remaining {
            VStack(alignment: .leading, spacing: 0) {
                Text(rm(abs(remaining)))
                    .font(.app(.title2, .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(remaining < 0 ? "over budget" : "left").font(.app(.caption2)).opacity(0.85)
            }
        }
    }

    private func stop(_ label: String, _ name: String?, _ time: Date?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.app(.caption2, .semibold)).opacity(0.8)
            if let name {
                HStack(spacing: 4) {
                    Text(name).font(.app(.subheadline, .semibold)).lineLimit(1)
                    if let time {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.app(.caption, .semibold)).opacity(0.85)
                    }
                }
            } else {
                Text("Nothing planned").font(.app(.subheadline)).opacity(0.85)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            money
            stop(entry.isDuring ? "Next stop" : "First stop", entry.nextStop, entry.nextStopTime)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                money
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                stop(entry.isDuring ? "Next stop" : "First stop", entry.nextStop, entry.nextStopTime)
                if entry.thenStop != nil {
                    stop("Then", entry.thenStop, entry.thenStopTime)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(entry.tripName ?? "") · \(entry.status)").font(.app(.headline)).lineLimit(1)
            if let remaining = entry.remaining {
                Text("\(rm(remaining)) left").font(.app(.caption))
            }
            if let stop = entry.nextStop {
                Text("Next: \(stop)").font(.app(.caption)).lineLimit(1)
            }
        }
    }
}

// MARK: - Widget 2: Add expense

struct ExpenseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ExpenseWidget", provider: TripProvider()) { entry in
            ExpenseWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetColors.gradient }
        }
        .configurationDisplayName("Add expense")
        .description("One tap to log an expense for your current trip.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ExpenseWidgetView: View {
    let entry: TripEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.tripName == nil {
                EmptyTripView(canReadTrips: entry.canReadTrips)
            } else if family == .accessoryCircular {
                // Lock Screen: a round "+" button.
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus").font(.app(.title, .bold))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.poppins(size: 34, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("Add expense").font(.app(.headline))
                    Text(entry.tripName ?? "").font(.app(.caption, .semibold)).opacity(0.9).lineLimit(1)
                    if entry.isDuring {
                        Text("Today \(rm(entry.spentToday))").font(.app(.caption2)).opacity(0.85)
                    } else if let remaining = entry.remaining {
                        Text("\(rm(remaining)) left").font(.app(.caption2)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        // The whole widget opens Add expense for this trip.
        .widgetURL(entry.tripName == nil ? URL(string: "tripple://today") : entry.addExpenseURL)
    }
}

// MARK: - Shared

struct EmptyTripView: View {
    var canReadTrips = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: canReadTrips ? "airplane" : "lock.fill").font(.app(.title2, .bold))
            Text(canReadTrips ? "No trips yet" : "Widget not available").font(.app(.headline))
            Text(canReadTrips ? "Open Triply to plan one" : "Needs the paid Apple Developer account")
                .font(.app(.caption)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemMedium) {
    TripWidget()
} timeline: {
    TripEntry.placeholder
}

#Preview(as: .systemSmall) {
    ExpenseWidget()
} timeline: {
    TripEntry.placeholder
}
