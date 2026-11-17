import SwiftUI
import MapKit

/// Search Apple Maps for a shop, restaurant or attraction and add it to a day (or save as an idea).
/// If search can't find it, the user can drop a pin on the map instead.
struct PlaceSearchView: View {
    let trip: Trip
    let dayIndex: Int?
    /// When set, the picked place replaces this one ("Change place") instead of adding a new stop.
    /// Its day, time, notes and saved links stay.
    var replacing: Place? = nil
    /// When set, the picked spot is handed back here instead of being added to the plan (e.g. a hotel's location).
    var onPick: ((PickedPlace) -> Void)? = nil
    /// Used with `onPick`: the screen title, search hint and pin button title.
    var pickTitle = "Set location"
    var pickPrompt = "Hotel name or address"
    /// Where to centre the search and the pin (e.g. the hotel's current location).
    var nearCoordinate: CLLocationCoordinate2D? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    /// True when nothing was found near the trip, so the results come from anywhere.
    @State private var searchedEverywhere = false
    @State private var isSearching = false
    @State private var resolvingSuggestion = false
    @State private var searchRegion: MKCoordinateRegion?
    @State private var completer = PlaceCompleter()
    @State private var showingPinDrop = false

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    Section {
                        ForEach(results, id: \.self) { item in
                            Button { add(item) } label: {
                                PlaceResultRow(title: item.name ?? "Unknown place", subtitle: item.placemark.title ?? "")
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if searchedEverywhere {
                            Text("Nothing near \(trip.destination.isEmpty ? "your trip" : trip.destination) · showing results from anywhere")
                                .textCase(nil)
                        }
                    }
                }

                if !extraSuggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(extraSuggestions, id: \.self) { suggestion in
                            Button { Task { await pick(suggestion) } } label: {
                                PlaceResultRow(title: suggestion.title, subtitle: suggestion.subtitle)
                            }
                            .buttonStyle(.plain)
                            .disabled(resolvingSuggestion)
                        }
                    }
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching {
                    Section {
                        Button { showingPinDrop = true } label: {
                            Label("Can't find it? Drop a pin on the map", systemImage: "mappin.and.ellipse")
                        }
                    }
                }
            }
            .overlay {
                if isSearching && results.isEmpty && extraSuggestions.isEmpty {
                    ProgressView()
                } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView {
                        Label("Search for a place", systemImage: "magnifyingglass")
                    } description: {
                        Text(onPick != nil
                             ? "Search by name or address, or drop a pin on the map."
                             : trip.destination.isEmpty
                             ? "Try a shop, restaurant or attraction."
                             : "Try a shop, restaurant or attraction in \(trip.destination).")
                    } actions: {
                        Button("Drop a pin on the map instead") { showingPinDrop = true }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: onPick != nil ? pickPrompt : "Shop, restaurant, attraction…")
            .onChange(of: query) { _, newValue in completer.update(query: newValue) }
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                await search()
            }
            .task {
                await loadSearchRegion()
                if let searchRegion { completer.region = searchRegion }
            }
            .navigationTitle(onPick != nil ? pickTitle
                             : replacing != nil ? "Change place"
                             : (dayIndex.map { "Add to Day \($0 + 1)" } ?? "Save an item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingPinDrop = true } label: {
                        Label("Drop a pin", systemImage: "mappin.and.ellipse")
                    }
                }
            }
            .navigationDestination(isPresented: $showingPinDrop) {
                PinDropView(startRegion: searchRegion,
                            startCoordinate: searchedEverywhere ? nil : (results.first?.placemark.coordinate ?? replacingCoordinate ?? nearCoordinate),
                            suggestedName: query.trimmingCharacters(in: .whitespaces),
                            destination: trip.mainDestination,
                            confirmTitle: onPick != nil ? "Use this location" : replacing == nil ? "Add place" : "Change place") { name, address, coordinate in
                    addPlace(name: name, address: address, coordinate: coordinate)
                }
            }
        }
    }

    /// The place being changed, if it already has a spot on the map.
    private var replacingCoordinate: CLLocationCoordinate2D? {
        guard let replacing, replacing.hasLocation else { return nil }
        return replacing.coordinate
    }

    /// Typing suggestions that aren't already in the search results.
    private var extraSuggestions: [MKLocalSearchCompletion] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let names = Set(results.compactMap { $0.name?.lowercased() })
        return Array(completer.suggestions.filter { !names.contains($0.title.lowercased()) }.prefix(8))
    }

    // MARK: - Where to search

    /// Search near this day's stops, else the trip's destination, else any of its places.
    private func loadSearchRegion() async {
        if let center = replacingCoordinate ?? nearCoordinate {
            searchRegion = MKCoordinateRegion(center: center,
                                              latitudinalMeters: 40_000, longitudinalMeters: 40_000)
            return
        }
        if let dayIndex {
            // Centre on the stop with the most other stops near it, so one far-away stop
            // (e.g. a place in another country) doesn't pull the area into the middle of nowhere.
            let stops = trip.places(onDay: dayIndex)
            let hub = stops.max { a, b in
                stops.filter { $0.distance(to: a) < 50_000 }.count < stops.filter { $0.distance(to: b) < 50_000 }.count
            }
            if let hub {
                searchRegion = MKCoordinateRegion(center: hub.coordinate,
                                                  latitudinalMeters: 40_000, longitudinalMeters: 40_000)
                return
            }
        }
        if !trip.mainDestination.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trip.mainDestination
            request.resultTypes = .address
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                searchRegion = MKCoordinateRegion(center: item.placemark.coordinate,
                                                  latitudinalMeters: 60_000, longitudinalMeters: 60_000)
                return
            }
        }
        if let first = trip.places.first {
            searchRegion = MKCoordinateRegion(center: first.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
    }

    // MARK: - Search

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; searchedEverywhere = false; return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let searchRegion { request.region = searchRegion }
        var found = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        // Apple Maps keeps far-away matches out when given a region. Keep only nearby ones first…
        if let searchRegion {
            found = found.filter { searchRegion.contains($0.placemark.coordinate, margin: 3) }
        }
        var everywhere = false
        // …and if nothing is near the trip, look everywhere.
        if found.isEmpty, searchRegion != nil {
            let wide = MKLocalSearch.Request()
            wide.naturalLanguageQuery = text
            found = (try? await MKLocalSearch(request: wide).start().mapItems) ?? []
            everywhere = !found.isEmpty
        }
        guard !Task.isCancelled else { return }
        results = found
        searchedEverywhere = everywhere
    }

    /// A typing suggestion was tapped: look up its full details and add it.
    private func pick(_ suggestion: MKLocalSearchCompletion) async {
        resolvingSuggestion = true
        defer { resolvingSuggestion = false }
        let request = MKLocalSearch.Request(completion: suggestion)
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            add(item, fallbackName: suggestion.title)
        } else {
            Toaster.shared.show("Couldn't open that place · try dropping a pin", systemImage: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Add

    private func add(_ item: MKMapItem, fallbackName: String? = nil) {
        addPlace(name: item.name ?? fallbackName ?? "Place",
                 address: item.placemark.title ?? "",
                 coordinate: item.placemark.coordinate,
                 phone: item.phoneNumber)
    }

    private func addPlace(name: String, address: String, coordinate: CLLocationCoordinate2D, phone: String? = nil) {
        if let onPick {
            onPick(PickedPlace(name: name, address: address, coordinate: coordinate, phone: phone))
            dismiss()
            return
        }
        if let replacing {
            replacing.name = name
            replacing.address = address
            replacing.latitude = coordinate.latitude
            replacing.longitude = coordinate.longitude
            replacing.hasLocation = true
            try? context.save()
            Toaster.shared.show("Changed to \(name)", systemImage: "mappin.circle.fill")
            dismiss()
            return
        }
        let place = Place(
            name: name,
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            dayIndex: dayIndex,
            order: trip.nextOrder(forDay: dayIndex)
        )
        context.insert(place)
        place.trip = trip
        Toaster.shared.show(dayIndex.map { "\(place.name) added to Day \($0 + 1)" } ?? "\(place.name) saved to Saved items",
                            systemImage: "mappin.circle.fill")
        dismiss()
    }
}

/// A spot chosen in `PlaceSearchView` when it is used to pick a location (not to add a stop).
struct PickedPlace {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let phone: String?
}

private struct PlaceResultRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        // Whole row is tappable, not just the text.
        .contentShape(Rectangle())
    }
}

private extension Place {
    /// Straight-line distance in metres.
    func distance(to other: Place) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

private extension MKCoordinateRegion {
    /// Whether a coordinate is inside this region, grown by `margin` times its size.
    func contains(_ coordinate: CLLocationCoordinate2D, margin: Double) -> Bool {
        abs(coordinate.latitude - center.latitude) <= span.latitudeDelta / 2 * margin
            && abs(coordinate.longitude - center.longitude) <= span.longitudeDelta / 2 * margin
    }
}

// MARK: - Suggestions while typing

/// Apple Maps' type-ahead suggestions (like the Maps app search box). Catches partial names and typos.
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var region: MKCoordinateRegion? {
        didSet { if let region { completer.region = region } }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func update(query: String) {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = text
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

// MARK: - Drop a pin

/// Move the map under a fixed centre pin, name the spot and add it. For places Apple Maps doesn't know.
/// A search box at the top jumps the map to a place or area first, then the user fine-tunes the pin.
struct PinDropView: View {
    let startRegion: MKCoordinateRegion?
    /// Where to begin when the user already found something close (e.g. the top search result).
    var startCoordinate: CLLocationCoordinate2D? = nil
    var suggestedName = ""
    /// Trip destination, used to find the area when no start region is known yet.
    var destination = ""
    /// Button title: "Change place" when swapping an existing stop or idea.
    var confirmTitle = "Add place"
    let onAdd: (String, String, CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var name = ""
    @State private var address = ""
    @State private var lookupTask: Task<Void, Never>?
    @State private var searchText = ""
    @State private var completer = PlaceCompleter()
    @State private var placed = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        Map(position: $position)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                lookUpAddress(context.region.center)
            }
            // The pin stays in the middle; the map moves under it.
            .overlay {
                Image(systemName: "mappin")
                    .font(.poppins(size: 34, weight: .bold))
                    .foregroundStyle(.red)
                    .shadow(radius: 3)
                    .offset(y: -17)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .top) { searchBox }
            .safeAreaInset(edge: .bottom) {
                if !searchFocused { bottomCard }
            }
            .navigationTitle("Drop a pin")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _, newValue in completer.update(query: newValue) }
            .task { await placeInitially() }
    }

    // MARK: Search box

    private var searchBox: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search a place or area to jump there", text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let first = completer.suggestions.first { Task { await jump(to: first) } }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if searchFocused && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                // Sized to its rows (at most 5), so a short list doesn't leave an empty box.
                VStack(spacing: 0) {
                    ForEach(completer.suggestions.prefix(5), id: \.self) { suggestion in
                        Button { Task { await jump(to: suggestion) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if completer.suggestions.isEmpty {
                        Text("No matches · move the map by hand")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: Bottom card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move the map so the pin is exactly on the place.")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
            TextField("Place name", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            if !address.isEmpty {
                Label(address, systemImage: "mappin.circle.fill")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button {
                guard let center else { return }
                onAdd(name.trimmingCharacters(in: .whitespaces), address, center)
            } label: {
                Text(confirmTitle)
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || center == nil)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: Moving the map

    /// Start at the place the user was searching for, else the day's / trip's area — never a random spot.
    private func placeInitially() async {
        guard !placed else { return }
        placed = true
        if name.isEmpty { name = suggestedName }
        if let region = startRegion { completer.region = region }

        if let startCoordinate {
            move(to: startCoordinate, meters: 600)
            return
        }
        // Try what was typed in search, near the trip.
        if !suggestedName.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = suggestedName
            if let startRegion { request.region = startRegion }
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                move(to: item.placemark.coordinate, meters: 600)
                return
            }
        }
        if let startRegion {
            move(to: startRegion.center, meters: 5_000)
            return
        }
        // No area known yet: look up the trip's destination.
        if !destination.isEmpty {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = destination
            request.resultTypes = .address
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
                completer.region = MKCoordinateRegion(center: item.placemark.coordinate,
                                                      latitudinalMeters: 60_000, longitudinalMeters: 60_000)
                move(to: item.placemark.coordinate, meters: 8_000)
                return
            }
        }
        position = .userLocation(fallback: .automatic)
    }

    /// A search suggestion was picked: fly there, close-up, and use its name if none was typed.
    private func jump(to suggestion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: suggestion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
        searchFocused = false
        searchText = ""
        // Areas (cities, districts) get a wider view than a single shop.
        let isArea = item.pointOfInterestCategory == nil && item.placemark.thoroughfare == nil
        move(to: item.placemark.coordinate, meters: isArea ? 3_000 : 400, animated: true)
        // The searched place becomes the name (you can still edit it before adding).
        name = item.name ?? suggestion.title
    }

    private func move(to coordinate: CLLocationCoordinate2D, meters: Double, animated: Bool = false) {
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
        } else {
            position = .region(region)
        }
        center = coordinate
        lookUpAddress(coordinate)
    }

    /// Shows the street address under the pin (in the local language), after the map stops moving.
    private func lookUpAddress(_ coordinate: CLLocationCoordinate2D) {
        lookupTask?.cancel()
        lookupTask = Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
                  !Task.isCancelled else { return }
            let parts = [placemark.name, placemark.locality, placemark.country].compactMap { $0 }
            address = parts.joined(separator: ", ")
        }
    }
}
