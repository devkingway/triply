import SwiftUI
import SwiftData
import CoreLocation
import Pow

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @State private var addTarget: AddTarget?
    @State private var showingEdit = false
    @State private var expenseFor: Place?
    @State private var tab: Tab = .plan
    /// Plan tab: what the day chips show — `allID`, a day index, or `ideasID`.
    @State private var planSelection = TripDetailView.allID
    @State private var pickedDefaultDay = false
    // Export / import of the itinerary or expenses as a file.
    @State private var exportDocument: TripExportDocument?
    @State private var exportName = ""
    @State private var showingImporter = false
    @State private var pendingImport: TripTransfer.FileContents?
    @State private var transferError: String?

    /// Flights, hotels, tickets and the shared album live on the More tab.
    enum Tab: String, CaseIterable { case plan = "Itinerary", budget = "Expenses", more = "More" }

    enum AddTarget: Identifiable {
        case day(Int), idea
        var id: String {
            switch self {
            case .day(let d): "day-\(d)"
            case .idea: "idea"
            }
        }
        var dayIndex: Int? {
            if case .day(let d) = self { return d }
            return nil
        }
    }

    var body: some View {
        Group {
            switch tab {
            case .plan: planList
            case .budget: BudgetView(trip: trip)
            case .more: MoreView(trip: trip)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onChange(of: tab) { _, _ in Haptics.tap() }
        .navigationTitle(trip.name)
        .tripAccent(trip)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Export to a file") {
                        Button("Export itinerary", systemImage: "map") { export(.itinerary) }
                        Button("Export expenses", systemImage: "banknote") { export(.expenses) }
                    }
                    Button("Import from file", systemImage: "square.and.arrow.down") { showingImporter = true }
                } label: {
                    Label("Export or import", systemImage: "square.and.arrow.up")
                }
                .tint(trip.accent)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
                    .tint(trip.accent)
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            if case .success = result {
                Toaster.shared.show("Exported", systemImage: "square.and.arrow.up.fill")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            readImport(result)
        }
        .alert("Add to \(trip.name)?",
               isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
               presenting: pendingImport) { contents in
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                withAnimation { TripTransfer.add(contents, to: trip, context: context) }
                Toaster.shared.show("Added \(TripTransfer.summary(of: contents))", systemImage: "square.and.arrow.down.fill")
            }
        } message: { contents in
            Text("\(contents.kind.title) from \"\(contents.trip.name)\": \(TripTransfer.summary(of: contents)). They're added alongside what's already here; nothing is replaced.")
        }
        .alert("Couldn't import", isPresented: Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transferError ?? "")
        }
        .sheet(item: $addTarget) { target in
            PlaceSearchView(trip: trip, dayIndex: target.dayIndex)
        }
        .sheet(isPresented: $showingEdit) {
            TripFormView(trip: trip)
        }
        .sheet(item: $expenseFor) { place in
            ExpenseFormView(trip: trip, prefillTitle: place.name)
        }
    }

    // MARK: - Plan tab

    /// Day chip ids: `allID` shows every day, `ideasID` only Saved ideas, any other value that day.
    static let allID = -1
    private var ideasID: Int { trip.dayCount }

    /// The selection, falling back to "All" if the trip got shorter.
    private var selection: Int {
        planSelection == Self.allID || planSelection == ideasID || (0..<trip.dayCount).contains(planSelection)
            ? planSelection : Self.allID
    }

    private var shownDays: [Int] {
        switch selection {
        case Self.allID: Array(0..<trip.dayCount)
        case ideasID: []
        default: [selection]
        }
    }

    private var planList: some View {
        List {
            // No trip summary card here: the plan starts with the day chips.
            // (In a section header, not a row, so the list's rounded row corners don't cut the chips off.)
            Section {
            } header: {
                // Always shown, even for a one-day trip, so the Ideas chip is one tap away.
                do {
                    let ideaCount = trip.ideas.count
                    DayJumpBar(
                        trip: trip, selection: selection, allID: Self.allID,
                        extra: ExtraDayChip(id: ideasID, icon: "lightbulb.fill",
                                            label: ideaCount == 1 ? "1 item" : ideaCount > 1 ? "\(ideaCount) items" : "Items",
                                            tint: Color.yellow.mix(with: .orange, by: 0.4), accessibility: "Saved items"),
                        hasDot: { !trip.places(onDay: $0).isEmpty },
                        draftCaption: { day in
                            let count = trip.places(onDay: day).count
                            return count == 0 ? "empty" : "\(count) stops"
                        }
                    ) { picked in
                        Haptics.tap()
                        withAnimation(.snappy) { planSelection = picked }
                    }
                    .dayBarFooter()
                }
            }

            ForEach(shownDays, id: \.self) { day in
                daySection(day)
            }

            if selection == Self.allID || selection == ideasID {
                ideasSection
            }
        }
        .listSectionSpacing(.compact)
        .onAppear {
            // During the trip, open on today's plan.
            guard !pickedDefaultDay else { return }
            pickedDefaultDay = true
            if let today = trip.todayIndex, trip.dayCount > 1 { planSelection = today }
        }
    }

    @ViewBuilder
    private func daySection(_ day: Int) -> some View {
        let stops = trip.places(onDay: day)
        Section {
            DayHeader(trip: trip, day: day, stopCount: stops.count)
                .headerRow()
        }
        .listSectionSpacing(0)
        Section {
            ForEach(trip.flights(onDay: day)) { flight in
                NavigationLink {
                    FlightDetailView(flight: flight)
                } label: {
                    BookingRow(
                        icon: "airplane", tint: .indigo,
                        title: "\(flight.title.isEmpty ? "Flight" : flight.title) · \(flight.fromCode) → \(flight.toCode)",
                        subtitle: "Departs \(flight.departureTimeText) · Arrives \(flight.arrivalTimeText)\(flight.arrivalDayOffset > 0 ? " (+\(flight.arrivalDayOffset))" : "")"
                    )
                }
            }

            // Landing day: the map shows airport → places → hotel, even before any place is added.
            let landing = trip.arrivingFlight(onDay: day) != nil
            if !stops.isEmpty || landing || trip.startHotel(forDay: day)?.coordinate != nil {
                NavigationLink {
                    DayRouteView(trip: trip, day: day)
                } label: {
                    Label(stops.count > 1 || landing ? "View route on map" : "View on map", systemImage: "map.fill")
                        .font(.app(.subheadline, .semibold))
                        .foregroundStyle(.tint)
                }
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    TimelineRow(
                        place: place,
                        number: index + 1,
                        isFirst: index == 0,
                        isLast: index == stops.count - 1,
                        nextLeg: index + 1 < stops.count && place.hasLocation && stops[index + 1].hasLocation
                            ? LegEstimate(from: place, to: stops[index + 1]) : nil
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                // No long-press menu here: press and hold starts dragging the stop up or down instead.
                // (Moving to another day is in the place's page → Day.)
                .swipeActions(edge: .leading) {
                    Button {
                        expenseFor = place
                    } label: {
                        Label("Add expense here", systemImage: "banknote")
                            .labelStyle(.iconOnly)
                    }
                    .tint(trip.accent)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation { context.delete(place) }
                        Haptics.tap()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.red)
                }
            }
            // Press and hold a stop, then drag it to a new position.
            .onMove { from, to in
                var reordered = stops
                reordered.move(fromOffsets: from, toOffset: to)
                withAnimation {
                    for (i, place) in reordered.enumerated() { place.order = i }
                }
                try? context.save()
                Haptics.tap()
            }

            Button {
                addTarget = .day(day)
            } label: {
                Label("Add place", systemImage: "plus.circle.fill")
                    .font(.app(.subheadline, .medium))
            }

            if let hotel = trip.hotel(forNight: day) {
                NavigationLink {
                    HotelDetailView(hotel: hotel)
                } label: {
                    BookingRow(
                        icon: "bed.double.fill", tint: .purple,
                        title: "Tonight: \(hotel.name)",
                        subtitle: Calendar.current.isDate(hotel.checkIn, inSameDayAs: trip.date(forDay: day))
                            ? "Check-in \(hotel.checkIn.formatted(date: .omitted, time: .shortened))" : nil
                    )
                }
            } else if day < trip.dayCount - 1 && !trip.hotels.isEmpty {
                Label("No hotel booked tonight", systemImage: "bed.double")
                    .font(.app(.subheadline))
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var ideasSection: some View {
        Section {
            HStack {
                Text("Saved items")
                Spacer()
                if !trip.ideas.isEmpty { Text("\(trip.ideas.count)") }
            }
            .font(.app(.headline))
            .foregroundStyle(.primary)
            .padding(.top, 8)
            .headerRow()
        }
        .listSectionSpacing(0)
        Section {
            let ideas = trip.ideas
            if ideas.isEmpty {
                Label("Share a post from Instagram or Facebook to Triply, or tap below to save a place for later.", systemImage: "sparkles")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            ForEach(ideas) { place in
                NavigationLink {
                    PlaceDetailView(place: place)
                } label: {
                    PlaceRow(place: place, number: nil)
                }
                .contextMenu { placeMenu(place) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation { context.delete(place) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.red)
                }
            }
            Button {
                addTarget = .idea
            } label: {
                Label("Save an item", systemImage: "lightbulb.fill")
                    .font(.app(.subheadline, .medium))
            }
        }
    }

    @ViewBuilder
    private func placeMenu(_ place: Place) -> some View {
        Menu {
            ForEach(0..<trip.dayCount, id: \.self) { day in
                Button(trip.dayTitle(day)) { move(place, to: day) }
                    .disabled(place.dayIndex == day)
            }
            Button("Saved items") { move(place, to: nil) }
                .disabled(place.dayIndex == nil)
        } label: {
            Label("Move to…", systemImage: "arrow.right.circle")
        }
        Button {
            expenseFor = place
        } label: {
            Label("Add expense here", systemImage: "banknote")
        }
        Button(role: .destructive) {
            withAnimation { context.delete(place) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func export(_ kind: TripTransfer.Kind) {
        do {
            exportName = TripTransfer.fileName(kind, of: trip)
            exportDocument = TripExportDocument(data: try TripTransfer.export(kind, of: trip))
        } catch {
            transferError = "Couldn't create the file: \(error.localizedDescription)"
        }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try TripTransfer.read(try Data(contentsOf: url))
        } catch {
            transferError = error.localizedDescription
        }
    }

    private func move(_ place: Place, to day: Int?) {
        withAnimation {
            place.order = trip.nextOrder(forDay: day)
            place.dayIndex = day
        }
        Toaster.shared.show(day.map { "Moved to Day \($0 + 1)" } ?? "Moved to Saved items", systemImage: "arrow.right.circle.fill")
    }
}

// MARK: - Day chips

extension View {
    /// Day chips placed as a section footer: full screen width, normal text colours.
    func dayBarFooter() -> some View {
        self
            .textCase(nil)
            .foregroundStyle(.primary)
            .padding(.top, 6)
            // The footer indents its text past the card edge; pull the chips back in line with the cards.
            .padding(.horizontal, -16)
    }
}

private extension View {
    /// Styles a list row to look like a section header (no card, no separator).
    func headerRow() -> some View {
        self
            .textCase(nil)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))
    }
}

/// A chip after the days (Saved ideas on Plan, "Other" on Budget).
struct ExtraDayChip {
    let id: Int
    let icon: String
    let label: String
    let tint: Color
    let accessibility: String
}

/// Chips under a summary card: All, one per day, and an optional extra chip.
/// Tap one to show only that part of the list. Used on the Plan and Budget tabs.
struct DayJumpBar: View {
    let trip: Trip
    /// The selected chip: `allID`, a day index, or the extra chip's id.
    let selection: Int
    let allID: Int
    var extra: ExtraDayChip? = nil
    /// Days that get a small dot (they already have something in them).
    var hasDot: (Int) -> Bool = { _ in false }
    /// Caption under the day number on draft trips (they have no dates).
    var draftCaption: (Int) -> String = { _ in "" }
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    allChip.id(allID)
                    ForEach(0..<trip.dayCount, id: \.self) { day in
                        dayChip(day).id(day)
                    }
                    if let extra {
                        extraChip(extra).id(extra.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
        }
    }

    /// Selected chip: see-through teal with a thin teal outline (same look as the "DAY 2" label).
    private func chipBackground(_ isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isActive ? trip.accent.opacity(0.15) : Color.secondary.opacity(0.12))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(trip.accent.opacity(0.5), lineWidth: 1)
                }
            }
    }

    private var allChip: some View {
        let isActive = selection == allID
        return Button { onSelect(allID) } label: {
            VStack(spacing: 1) {
                Image(systemName: "list.bullet")
                    .font(.app(.subheadline, .bold))
                    .frame(height: 20)
                Text("All")
                    .font(.app(.caption2, .medium))
            }
            .foregroundStyle(isActive ? trip.accent : Color.primary)
            .frame(minWidth: 48)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background { chipBackground(isActive) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All days")
    }

    private func dayChip(_ day: Int) -> some View {
        let isActive = selection == day
        let isToday = trip.todayIndex == day
        let dot = hasDot(day)
        return Button { onSelect(day) } label: {
            VStack(spacing: 1) {
                Text("D\(day + 1)")
                    .font(.app(.subheadline, .heavy))
                    .frame(height: 20)
                if trip.isDraft {
                    Text(draftCaption(day))
                        .font(.app(.caption2, .medium))
                } else if isToday {
                    Text("Today")
                        .font(.app(.caption2, .bold))
                } else {
                    Text(trip.date(forDay: day).formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.app(.caption2, .medium))
                }
            }
            .foregroundStyle(isActive ? trip.accent : (isToday ? Color.orange : Color.primary))
            .frame(minWidth: 48)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background { chipBackground(isActive) }
            .overlay {
                if isToday && !isActive {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.orange, lineWidth: 1.5)
                }
            }
            // A small dot: this day already has something in it.
            .overlay(alignment: .topTrailing) {
                if dot && !trip.isDraft {
                    Circle()
                        .fill(trip.accent)
                        .frame(width: 6, height: 6)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Day \(day + 1)\(isToday ? ", today" : "")")
    }

    private func extraChip(_ extra: ExtraDayChip) -> some View {
        let isActive = selection == extra.id
        return Button { onSelect(extra.id) } label: {
            VStack(spacing: 1) {
                Image(systemName: extra.icon)
                    .font(.app(.subheadline, .bold))
                    .frame(height: 20)
                Text(extra.label)
                    .font(.app(.caption2, .medium))
            }
            .foregroundStyle(isActive ? trip.accent : extra.tint)
            .frame(minWidth: 48)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background { chipBackground(isActive) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(extra.accessibility)
    }
}

// MARK: - Header

struct DayHeader: View {
    let trip: Trip
    let day: Int
    let stopCount: Int

    var body: some View {
        let isToday = trip.todayIndex == day
        HStack(spacing: 10) {
            // Same see-through teal as the trip card's chips.
            Text("DAY \(day + 1)")
                .font(.app(.caption, .heavy))
                .foregroundStyle(trip.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trip.accent.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(trip.accent.opacity(0.3), lineWidth: 1))
            if !trip.isDraft {
                Text(trip.date(forDay: day).formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.app(.headline))
                    .foregroundStyle(.primary)
            }
            if isToday {
                Chip(text: "Today", tint: .white, background: AnyShapeStyle(Color.orange))
            }
            Spacer()
            let spent = trip.spent(onDay: day)
            if spent > 0 {
                Text(spent.formatted(.currency(code: "MYR").precision(.fractionLength(0))))
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.top, 8)
    }
}

// MARK: - Rows

/// One stop on the itinerary, drawn on a vertical timeline.
struct TimelineRow: View {
    @Environment(\.tripAccent) private var accent
    let place: Place
    let number: Int
    let isFirst: Bool
    let isLast: Bool
    let nextLeg: LegEstimate?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : accent.opacity(0.35))
                    .frame(width: 2, height: 12)
                StopBadge(number: number, size: 28, done: place.isDone)
                Rectangle()
                    .fill(isLast ? Color.clear : accent.opacity(0.35))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name)
                        .font(.app(.body, .semibold))
                        .foregroundStyle(place.isDone ? .secondary : .primary)
                        .strikethrough(place.isDone, color: .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let time = place.time {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.app(.caption, .semibold))
                            .foregroundStyle(accent)
                    }
                }
                if !place.notes.isEmpty {
                    Text(place.notes)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !place.address.isEmpty {
                    Text(place.address)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !place.links.isEmpty {
                    Label("\(place.links.count) saved post\(place.links.count == 1 ? "" : "s")", systemImage: "camera.fill")
                        .font(.app(.caption2, .semibold))
                        .foregroundStyle(.pink)
                }
                // Tickets booked for this place, e.g. "Ticket · 4:30 PM · 2 people".
                ForEach(place.sortedTickets) { ticket in
                    Label {
                        Text(["Ticket",
                              ticket.hasTime ? ticket.startsAt.formatted(date: .omitted, time: .shortened) : nil,
                              ticket.people > 1 ? "\(ticket.people) people" : nil,
                              ticket.attachments.isEmpty ? nil : "e-ticket saved"]
                            .compactMap { $0 }.joined(separator: " · "))
                    } icon: {
                        Image(systemName: "ticket.fill")
                    }
                    .font(.app(.caption2, .semibold))
                    .foregroundStyle(ExpenseCategory.tickets.color)
                }
                if let nextLeg {
                    Label(nextLeg.text, systemImage: nextLeg.icon)
                        .font(.app(.caption2))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, isLast ? 14 : 8)
        }
    }
}

/// Rough straight-line travel estimate between two stops (the map shows the real route).
struct LegEstimate {
    let meters: CLLocationDistance

    init(from a: Place, to b: Place) {
        meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private var distanceText: String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var icon: String { meters < 2_000 ? "figure.walk" : "tram.fill" }

    var text: String {
        if meters < 2_000 {
            let minutes = max(1, Int((meters * 1.3 / 80).rounded()))
            return "~\(minutes) min walk · \(distanceText)"
        }
        return "~\(distanceText) to next stop"
    }
}

struct BookingRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.subheadline, .semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PlaceRow: View {
    let place: Place
    let number: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let number {
                StopBadge(number: number)
            } else {
                // Saved idea: the shared post's picture, or the bulb until it loads (or if there's none).
                LinkThumbnail(url: place.sortedLinks.first?.url, size: 36) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.yellow.gradient, in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.app(.body, .medium))
                if !place.notes.isEmpty {
                    Text(place.notes)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !place.address.isEmpty {
                    Text(place.address)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !place.links.isEmpty {
                Label("\(place.links.count)", systemImage: "camera.fill")
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.pink)
            }
        }
    }
}

struct StopBadge: View {
    @Environment(\.tripAccent) private var accent
    let number: Int
    var size: CGFloat = 26
    /// Ticked off: shows a check mark on grey instead of the number.
    var done = false

    var body: some View {
        Group {
            if done {
                Image(systemName: "checkmark")
                    .font(.poppins(size: size * 0.45, weight: .heavy))
            } else {
                Text("\(number)")
                    .font(.poppins(size: size * 0.48, weight: .bold))
            }
        }
        .foregroundStyle(done ? Color.white : accent)
        .frame(width: size, height: size)
        .background {
            if done {
                Circle().fill(Color.gray)
            } else {
                // Same see-through teal as the "DAY 2" label, on the card colour so the timeline
                // line doesn't show through.
                ZStack {
                    Circle().fill(Color(.secondarySystemGroupedBackground))
                    Circle().fill(accent.opacity(0.15))
                }
            }
        }
        .overlay {
            Circle().strokeBorder(done ? Color.clear : accent.opacity(0.5), lineWidth: 1)
        }
    }
}
