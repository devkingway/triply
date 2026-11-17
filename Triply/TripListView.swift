import SwiftUI
import SwiftData
import Pow

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    /// Places shared to "All", waiting to be moved into a trip.
    @Query(filter: #Predicate<Place> { $0.trip == nil }) private var savedPlaces: [Place]
    @State private var showingNewTrip = false
    @State private var showingWhatsNew = false
    /// The newest update the user has opened; a dot shows on the button until they read a newer one.
    @AppStorage("seenUpdateNote") private var seenUpdate = ""
    @State private var showingSavedPlaces = false
    @State private var editingTrip: Trip?
    @State private var deletingTrip: Trip?
    @State private var path: [Trip] = []
    /// During a trip the app opens on Today; "Trips" switches to the full list.
    @State private var showToday = true
    @State private var quickAddTrip: Trip?
    private var router = AppRouter.shared
    @AppStorage(AppAppearance.storageKey, store: AppAppearance.store) private var appearance = AppAppearance.system

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let current = currentTrip, showToday {
                    TodayView(trip: current)
                } else if trips.isEmpty && savedPlaces.isEmpty {
                    emptyState
                } else {
                    // A List (styled to look like free cards) so trips can be swiped left to delete or edit.
                    List {
                        if let current = currentTrip {
                            Button {
                                withAnimation { showToday = true }
                            } label: {
                                TodayBanner(trip: current)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        ForEach(sections, id: \.title) { section in
                        Section {
                        ForEach(section.trips) { trip in
                            ZStack {
                                // Hidden link keeps tap-to-open without the List's arrow.
                                NavigationLink(value: trip) { EmptyView() }
                                    .opacity(0)
                                TripCard(trip: trip)
                            }
                            .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    deletingTrip = trip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .labelStyle(.iconOnly)
                                }
                                .tint(.red)
                                Button {
                                    editingTrip = trip
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .labelStyle(.iconOnly)
                                }
                                .tint(Theme.teal)
                            }
                        }
                        } header: {
                            if sections.count > 1 || section.title == "Drafts" {
                                Text(section.title)
                                    .font(.app(.headline))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 8, for: .scrollContent)
                    .background(Color(.systemGroupedBackground))
                    .safeAreaInset(edge: .bottom) {
                        // Pinned to the bottom of the screen; the list scrolls above it.
                        if !savedPlaces.isEmpty {
                            Button {
                                showingSavedPlaces = true
                            } label: {
                                SavedPlacesBanner(count: savedPlaces.count)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .bottomBarBlur()
                        }
                    }
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .sheet(isPresented: $showingSavedPlaces) {
                // Its own navigation, so opening a saved place works inside the sheet.
                NavigationStack { SavedPlacesView() }
            }
            .onAppear { handleRoute() }
            .onChange(of: router.pending) { _, _ in handleRoute() }
            .sheet(item: $quickAddTrip) { trip in
                ExpenseFormView(trip: trip)
            }
            .toolbar {
                if currentTrip != nil && showToday {
                    // Back to the list of all trips.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation { showToday = false }
                        } label: {
                            Label("Trips", systemImage: "list.bullet")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                } else {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                    } label: {
                        Label("Appearance", systemImage: appearance.systemImage)
                    }
                    .onChange(of: appearance) { _, _ in Haptics.tap() }
                }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingWhatsNew = true
                    } label: {
                        // A small orange dot until the latest update has been read.
                        // Drawn inside the icon: the toolbar's glass button clips anything outside it.
                        Image(systemName: "sparkles")
                            .padding(3)
                            .overlay(alignment: .topTrailing) {
                                if seenUpdate != UpdateNotes.latestID {
                                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                                }
                            }
                            .accessibilityLabel("What's new")
                    }
                    .accessibilityHint(seenUpdate != UpdateNotes.latestID ? "New update" : "")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewTrip = true } label: {
                        Label("New Trip", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTrip) {
                TripFormView()
            }
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView()
                    .onAppear { seenUpdate = UpdateNotes.latestID }
            }
            .sheet(item: $editingTrip) { trip in
                TripFormView(trip: trip)
            }
            // Centered alert (not a pop-up near the card) so the choice is clear.
            .alert("Delete \(deletingTrip?.name ?? "trip")?", isPresented: Binding(get: { deletingTrip != nil }, set: { if !$0 { deletingTrip = nil } })) {
                Button("Cancel", role: .cancel) { deletingTrip = nil }
                Button("Delete", role: .destructive) {
                    if let deletingTrip {
                        withAnimation { context.delete(deletingTrip) }
                        // Write the deletion straight away (not only when the app goes to the background).
                        try? context.save()
                        // Give the freed space back to the iPhone next time Triply starts.
                        SharedStore.requestCompaction()
                        Toaster.shared.show("Trip deleted", systemImage: "trash.fill", style: .info)
                    }
                    deletingTrip = nil
                }
            } message: {
                Text("All its places, expenses, hotels and flights are removed too. This can't be undone.")
            }
        }
    }

    /// Acts on a tripple:// link (from the widget or Control Center).
    private func handleRoute() {
        guard let request = router.pending else { return }
        router.pending = nil
        guard let trip = Trip.focus(in: trips) else {
            Toaster.shared.show("Create a trip first", systemImage: "airplane", style: .info)
            return
        }
        switch request {
        case .addExpense(let tripID):
            // The widget's trip if given, otherwise the current one.
            quickAddTrip = trips.first { $0.widgetID == tripID } ?? trip
        case .openCurrentTrip:
            if trip.todayIndex != nil {
                path = []
                withAnimation { showToday = true }
            } else {
                showToday = false
                path = [trip]
            }
        }
    }

    /// The trip happening today, if any.
    private var currentTrip: Trip? { trips.first { $0.todayIndex != nil } }

    /// Planned trips first (by date), then drafts with no fixed dates.
    private var sections: [(title: String, trips: [Trip])] {
        let planned = trips.filter { !$0.isDraft }
        let drafts = trips.filter(\.isDraft).sorted { $0.createdAt > $1.createdAt }
        var result: [(title: String, trips: [Trip])] = []
        if !planned.isEmpty { result.append(("Trips", planned)) }
        if !drafts.isEmpty { result.append(("Drafts", drafts)) }
        return result
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            PlaneAnimation(size: 170)
                .shadow(color: Theme.teal.opacity(0.35), radius: 20, y: 10)
            Text("Where to next?")
                .font(.app(.title, .bold))
            Text("Plan each day, track your budget in RM, keep flights and hotels together, and save places straight from Instagram.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showingNewTrip = true
            } label: {
                Label("Plan a new trip", systemImage: "plus")
                    .font(.app(.headline))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
            Button("Try a sample trip") {
                withAnimation { SampleData.insertTokyoTrip(into: context) }
                Haptics.success()
            }
            .font(.app(.subheadline))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Large photo card for a trip in the list.
struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.app(.title2, .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !trip.destinations.isEmpty {
                        Label(trip.destinations.joined(separator: " → "),
                              systemImage: trip.destinations.count > 1 ? "point.bottomleft.forward.to.point.topright.scurvepath" : "mappin.and.ellipse")
                            .font(.app(.subheadline, .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Chip(text: trip.phaseText, systemImage: trip.phaseIcon,
                     tint: trip.accent,
                     background: AnyShapeStyle(trip.accent.opacity(0.15)))
            }

            Divider().overlay(trip.accent.opacity(0.25))

            HStack(spacing: 16) {
                // Short dates (no year) so the row never gets cut off.
                stat(icon: "calendar", text: trip.isDraft
                     ? "Dates not set"
                     : "\(trip.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(trip.endDate.formatted(.dateTime.day().month(.abbreviated)))")
                    .layoutPriority(1)
                Spacer()
                stat(icon: "sun.max", text: "\(trip.dayCount)d")
                if trip.budget > 0 {
                    budgetRing
                }
            }
        }
        .padding(18)
        // Same colours for drafts and planned trips; the Draft label tells them apart.
        .glassCard(tint: trip.accent, secondTint: trip.accent2)
    }

    private func stat(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.app(.footnote, .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var budgetRing: some View {
        let ratio = min(trip.netSpent / max(trip.budget, 1), 1)
        let over = trip.netSpent > trip.budget
        return HStack(spacing: 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(over ? Color.red : trip.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text(over ? "Over" : trip.remaining.formatted(.currency(code: "MYR").precision(.fractionLength(0))))
                .font(.app(.footnote, .semibold))
                .foregroundStyle(over ? .red : .primary)
        }
    }
}

/// Slight shrink when a card is pressed.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

struct TripFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var trip: Trip?

    @State private var name = ""
    /// Each place the trip goes to; always at least one (possibly empty) field.
    @State private var destinations = [""]
    @FocusState private var focusedDestination: Int?
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!
    @State private var budget: Double = 0
    @State private var localCurrency = "MYR"
    /// Save as a draft: number of days only, real dates confirmed later.
    /// New trips start this way ("Dates not decided yet"); editing loads the trip's own setting.
    @State private var isDraft = true
    @State private var draftDays = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name (e.g. Tokyo Winter)", text: $name)
                }
                Section {
                    ForEach(destinations.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            if destinations.count > 1 {
                                Text("\(index + 1)")
                                    .font(.app(.caption, .bold))
                                    .foregroundStyle(Theme.teal)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.teal.opacity(0.15), in: Circle())
                            }
                            TextField(index == 0 ? "Destination (e.g. Tokyo, Japan)" : "Next destination (e.g. Osaka)",
                                      text: $destinations[index])
                                .autocorrectionDisabled()
                                .focused($focusedDestination, equals: index)
                                .submitLabel(.done)
                            if destinations.count > 1 {
                                Button {
                                    withAnimation { _ = destinations.remove(at: index) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove destination \(index + 1)")
                            }
                        }
                    }
                    .onMove { from, to in destinations.move(fromOffsets: from, toOffset: to) }
                    Button {
                        withAnimation { destinations.append("") }
                        focusedDestination = destinations.count - 1
                    } label: {
                        Label("Add destination", systemImage: "plus.circle.fill")
                    }
                    .disabled(destinations.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                } header: {
                    Text(destinations.count > 1 ? "Destinations" : "Destination")
                } footer: {
                    if destinations.count > 1 {
                        Text("In the order you visit them. Long-press to reorder.")
                    } else {
                        Text("Going to more than one place? Add each city or country.")
                    }
                }
                Section {
                    Toggle(isOn: $isDraft.animation()) {
                        Label("Dates not decided yet", systemImage: "pencil.and.list.clipboard")
                    }
                    .tint(Theme.teal)
                    if isDraft {
                        Stepper("\(draftDays) day\(draftDays == 1 ? "" : "s")", value: $draftDays, in: 1...60)
                    } else {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    if isDraft {
                        Text("Saved as a draft. Plan each day now, then tap Edit on the trip and turn this off when you know your dates.")
                    }
                }
                Section {
                    HStack {
                        Text("RM")
                            .foregroundStyle(.secondary)
                        TextField("0.00", value: $budget, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                    }
                    Picker("Local currency", selection: $localCurrency) {
                        ForEach(Currencies.common, id: \.self) { code in
                            Text(Currencies.label(code)).tag(code)
                        }
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text("Budget is in Malaysian Ringgit (MYR). Expenses default to the local currency and are converted to RM.")
                }
            }
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue { endDate = newValue }
            }
            .onAppear {
                if let trip {
                    name = trip.name
                    destinations = trip.destinations.isEmpty ? [""] : trip.destinations
                    startDate = trip.startDate
                    endDate = trip.endDate
                    budget = trip.budget
                    localCurrency = trip.localCurrency
                    isDraft = trip.isDraft
                    draftDays = trip.dayCount
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if let trip {
            trip.name = trimmedName
            trip.destinations = destinations
            trip.startDate = startDate
            trip.endDate = endDate
            trip.budget = budget
            trip.localCurrency = localCurrency
            trip.isDraft = isDraft
            trip.draftDays = draftDays
            // Places on days beyond the new end date go back to saved ideas.
            for place in trip.places where (place.dayIndex ?? 0) >= trip.dayCount {
                place.dayIndex = nil
            }
            Toaster.shared.show("Trip updated")
        } else {
            let new = Trip(name: trimmedName, destination: "", startDate: startDate, endDate: endDate, budget: budget, localCurrency: localCurrency)
            new.destinations = destinations
            new.isDraft = isDraft
            new.draftDays = draftDays
            withAnimation { context.insert(new) }
            Toaster.shared.show("\(trimmedName) created ✈️")
        }
        dismiss()
    }
}

/// Banner at the top of the trip list during a trip: tap to go back to Today.
struct TodayBanner: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.app(.title2))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.brandGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.app(.headline))
                Text("\(trip.name) · \(trip.phaseText)")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(Theme.teal)
        }
        .padding(16)
        .glassCard()
    }
}

/// Trip list row for places shared to "All" that aren't in a trip yet.
private struct SavedPlacesBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.app(.headline))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.teal.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved items").font(.app(.headline)).foregroundStyle(.primary)
                Text("\(count) waiting to be moved into a trip")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassCard()
    }
}
