import SwiftUI
import SwiftData
import MapKit
import WidgetKit

/// "Save to Triply" screen shown from Instagram / Facebook / Safari's share sheet.
struct ShareView: View {
    let loadInput: () async -> SharedInput
    let onDone: () -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var input = SharedInput()
    @State private var loading = true
    @State private var trip: Trip?
    @State private var mode: Mode = .newPlace
    @State private var existingPlace: Place?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var picked: MKMapItem?
    @State private var dayIndex: Int?
    @State private var note = ""
    @State private var saveError: String?
    @State private var saved = false
    /// Places found from an address or "📍" line in the post.
    @State private var detected: [MKMapItem] = []
    @State private var scanning = false
    @State private var pickedFromPost = false

    enum Mode: String, CaseIterable { case newPlace = "New place", existing = "Existing place" }

    /// A name typed in the search box, used when no map place is picked.
    private var typedName: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard input.url != nil else { return false }
        if mode == .existing { return trip != nil && existingPlace != nil }
        return picked != nil || !typedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                linkSection

                if loading {
                    EmptyView()
                } else if !SharedStore.isAppGroupAvailable {
                    // Free Apple ID build: this screen can't reach the app's trips.
                    Section {
                        Label("Sharing to Triply needs the paid Apple Developer account. For now, tap Copy Link here, then in Triply open the place and use Add Instagram / Facebook link.",
                              systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                } else if input.url != nil {
                    tripSection
                    placeSection
                    Section("Note (optional)") {
                        NotesEditor(placeholder: "e.g. must try the matcha dessert", text: $note, minHeight: 60)
                    }
                }

                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Save to Triply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
        .overlay {
            if saved {
                ZStack {
                    Rectangle().fill(.regularMaterial).ignoresSafeArea()
                    VStack(spacing: 8) {
                        SuccessAnimation(onFinish: onDone)
                        Text(trip.map { "Saved to \($0.name)" } ?? "Saved to Saved items")
                            .font(.app(.headline))
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
            input = await loadInput()
            trip = defaultTrip
            loading = false
            await findLocationInPost()
        }
        .task(id: query) { await search() }
        .onChange(of: trip) { _, newTrip in
            existingPlace = nil
            dayIndex = nil
            if newTrip == nil { mode = .newPlace }
        }
    }

    // MARK: - Sections

    private var linkSection: some View {
        Section {
            if loading {
                HStack { ProgressView(); Text("Reading link…").foregroundStyle(.secondary) }
            } else if let url = input.url {
                let platform = LinkPlatform(url: url)
                HStack(spacing: 12) {
                    Image(systemName: platform.systemImage)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(platform.color.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(platform.name) \(platform == .web ? "" : "post")").font(.app(.headline))
                        Text(url.absoluteString)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Label("No link found in what was shared. In Instagram or Facebook, use Share → Triply on the post.", systemImage: "link.badge.plus")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tripSection: some View {
        Section {
            Picker("Trip", selection: $trip) {
                Text("All (choose a trip later)").tag(Trip?.none)
                ForEach(trips) { trip in
                    Text(trip.name).tag(Optional(trip))
                }
            }
        } header: {
            Text("Trip")
        } footer: {
            if trip == nil {
                Text("Kept in Saved items in the app. Move it into a trip whenever you like.")
            }
        }
    }

    @ViewBuilder
    private var placeSection: some View {
        Section {
            if trip != nil {
                Picker("Place", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch mode {
            case .newPlace:
                if let picked {
                    if pickedFromPost {
                        Label("Found in the post", systemImage: "sparkles")
                            .font(.app(.caption, .semibold))
                            .foregroundStyle(.tint)
                    }
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red).font(.app(.title2))
                        VStack(alignment: .leading) {
                            Text(picked.name ?? "Place").font(.app(.headline))
                            Text(picked.placemark.title ?? "").font(.app(.caption)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button("Change") {
                            self.picked = nil
                            pickedFromPost = false
                        }
                            .buttonStyle(.borderless)
                    }
                    if let trip {
                        Picker("Add to", selection: $dayIndex) {
                            Text("Saved items").tag(Int?.none)
                            ForEach(0..<trip.dayCount, id: \.self) { day in
                                Text(trip.dayTitle(day)).tag(Int?.some(day))
                            }
                        }
                    }
                } else {
                    if scanning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking for an address in the post…").foregroundStyle(.secondary)
                        }
                    }
                    // Places found in the post's caption, ready to tap.
                    ForEach(detected, id: \.self) { item in
                        Button {
                            picked = item
                            pickedFromPost = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Place").foregroundStyle(.primary)
                                    Text("Found in the post · \(item.placemark.title ?? "")")
                                        .font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    TextField("Place name, or search the map…", text: $query)
                        .autocorrectionDisabled()
                    if !typedName.isEmpty {
                        Label("Save as “\(typedName)” · add the location later, or tap a map result below",
                              systemImage: "text.cursor")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    if searching { ProgressView() }
                    ForEach(results, id: \.self) { item in
                        Button {
                            picked = item
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").foregroundStyle(.primary)
                                Text(item.placemark.title ?? "").font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            case .existing:
                if let trip, !trip.places.isEmpty {
                    Picker("Place", selection: $existingPlace) {
                        Text("Choose…").tag(Place?.none)
                        ForEach(placesForPicker(trip)) { place in
                            Text(placeLabel(place, in: trip)).tag(Optional(place))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } else {
                    Text("This trip has no places yet. Use New place.").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Which place is this post about?")
        }
    }

    // MARK: - Logic

    /// Reads the post's caption for an address or "📍 Place" line and suggests that place.
    private func findLocationInPost() async {
        guard input.url != nil || !input.text.isEmpty else { return }
        scanning = true
        defer { scanning = false }
        let text = await PostLocationFinder.postText(url: input.url, sharedText: input.text)
        let candidates = PostLocationFinder.candidates(in: text)
        guard !candidates.isEmpty else { return }
        let region = trip?.places.first.map {
            MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        }
        detected = await PostLocationFinder.places(for: candidates, near: region)
        if picked == nil, mode == .newPlace, let first = detected.first {
            // Fill it in; the user can still tap Change.
            picked = first
            pickedFromPost = true
        } else if detected.isEmpty, query.isEmpty {
            // Nothing matched on the map: start a search with what the post said.
            query = candidates[0]
        }
    }

    /// The trip happening now, or the next upcoming one, or the latest.
    private var defaultTrip: Trip? {
        let today = Calendar.current.startOfDay(for: .now)
        return trips.first { Calendar.current.startOfDay(for: $0.endDate) >= today } ?? trips.last
    }

    private func placesForPicker(_ trip: Trip) -> [Place] {
        var list: [Place] = []
        for day in 0..<trip.dayCount { list += trip.places(onDay: day) }
        return list + trip.ideas
    }

    private func placeLabel(_ place: Place, in trip: Trip) -> String {
        if let day = place.dayIndex { return "Day \(day + 1) · \(place.name)" }
        return "Saved item · \(place.name)"
    }

    private func search() async {
        do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let center = trip?.places.first?.coordinate {
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
        results = Array(((try? await MKLocalSearch(request: request).start().mapItems) ?? []).prefix(8))
    }

    private func save() {
        guard let url = input.url else { return }
        let place: Place
        switch mode {
        case .existing:
            guard trip != nil, let existingPlace else { return }
            place = existingPlace
        case .newPlace:
            // No trip chosen ("All"): the place waits in Saved places, so it isn't on a day.
            let day = trip == nil ? nil : dayIndex
            let order = trip?.nextOrder(forDay: day) ?? 0
            if let picked {
                let c = picked.placemark.coordinate
                place = Place(name: picked.name ?? "Place", address: picked.placemark.title ?? "",
                              latitude: c.latitude, longitude: c.longitude, dayIndex: day, order: order)
            } else {
                // Saved by name only; the location can be set later in the app.
                guard !typedName.isEmpty else { return }
                place = Place(name: typedName, address: "", latitude: 0, longitude: 0, dayIndex: day, order: order)
                place.hasLocation = false
            }
            context.insert(place)
            place.trip = trip
        }
        let link = SavedLink(urlString: url.absoluteString, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(link)
        link.place = place
        do {
            try context.save()
            SharedStore.markChanged()
            WidgetCenter.shared.reloadAllTimelines()
            withAnimation(.easeOut(duration: 0.2)) { saved = true }
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
