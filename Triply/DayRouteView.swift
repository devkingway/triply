import SwiftUI
import MapKit

enum TravelMode: String, CaseIterable, Identifiable {
    case walking, driving
    var id: String { rawValue }

    var label: String { self == .walking ? "Walk" : "Drive" }
    var systemImage: String { self == .walking ? "figure.walk" : "car.fill" }
    var transportType: MKDirectionsTransportType { self == .walking ? .walking : .automobile }
    var appleMapsKey: String { self == .walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving }
    var googleKey: String { self == .walking ? "walking" : "driving" }
}

/// A point on the day's route: a planned place (numbered), the hotel, or the airport you land at.
struct RouteStop: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// Visiting number for places; `nil` for the hotel and airport.
    let number: Int?
    var isAirport = false

    var isHotel: Bool { number == nil && !isAirport }
}

/// Finds an airport's location from its code (e.g. HND), once per code.
@MainActor
enum AirportLocator {
    private static var cache: [String: CLLocationCoordinate2D] = [:]

    static func coordinate(code: String, city: String) async -> CLLocationCoordinate2D? {
        let key = code.uppercased()
        if let hit = cache[key] { return hit }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(key) airport \(city)"
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.airport])
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        cache[key] = item.placemark.coordinate
        return item.placemark.coordinate
    }
}

struct RouteLeg: Identifiable {
    let from: RouteStop
    let to: RouteStop
    let route: MKRoute?
    var id: String { "\(from.id)>\(to.id)" }
}

/// Shows one day's stops as numbered pins with the route drawn between them.
struct DayRouteView: View {
    let trip: Trip
    let day: Int

    @Environment(\.openURL) private var openURL
    @State private var mode: TravelMode = .walking
    @State private var includeHotel = true
    @State private var legs: [RouteLeg] = []
    @State private var isLoading = false
    @State private var position: MapCameraPosition = .automatic
    /// Routes already worked out this session, keyed by mode + coordinates.
    @State private var cache: [String: MKRoute] = [:]

    private var places: [Place] { trip.places(onDay: day) }
    /// Where the flight that lands today arrives (found from its airport code).
    @State private var airportCoordinate: CLLocationCoordinate2D?

    private var arrivingFlight: Flight? { trip.arrivingFlight(onDay: day) }

    private var airportStop: RouteStop? {
        guard let flight = arrivingFlight, let c = airportCoordinate else { return nil }
        return RouteStop(id: "airport-\(flight.toCode)", name: "\(flight.toCode) airport", coordinate: c, number: nil, isAirport: true)
    }

    /// Today's check-in hotel, placed in the day by its check-in time.
    private var checkInHotel: Hotel? {
        guard let hotel = trip.checkInHotel(onDay: day), hotel.coordinate != nil else { return nil }
        return hotel
    }

    private var startHotelStop: RouteStop? {
        guard let hotel = trip.startHotel(forDay: day), let c = hotel.coordinate else { return nil }
        return RouteStop(id: "hotel-start", name: hotel.name, coordinate: c, number: nil)
    }

    private var endHotelStop: RouteStop? {
        guard let hotel = trip.endHotel(forDay: day), let c = hotel.coordinate else { return nil }
        return RouteStop(id: "hotel-end", name: hotel.name, coordinate: c, number: nil)
    }

    private var hasHotel: Bool { startHotelStop != nil || endHotelStop != nil }

    /// The full ordered route:
    /// arrival airport (on the day you land) or last night's hotel → places → tonight's hotel.
    /// On check-in day the hotel goes in at its check-in time, between the places before and after it.
    private var stops: [RouteStop] {
        var result: [RouteStop] = []
        // Start: the airport you land at, else the hotel you woke up in.
        if let airport = airportStop {
            result.append(airport)
        } else if includeHotel, let start = startHotelStop {
            result.append(start)
        }

        // Places saved by name only have no spot on the map yet, so they're left out of the route.
        var placeStops = places.enumerated().filter { $0.element.hasLocation }.map { index, place in
            (stop: RouteStop(id: "place-\(index)-\(place.latitude),\(place.longitude)", name: place.name,
                             coordinate: place.coordinate, number: index + 1),
             time: place.time)
        }

        var endsAtCheckIn = false
        if includeHotel, let hotel = checkInHotel, let c = hotel.coordinate {
            let checkInStop = RouteStop(id: "hotel-checkin", name: hotel.name, coordinate: c, number: nil)
            // Goes before the first place planned for after check-in time; otherwise at the end.
            let cal = Calendar.current
            let checkInMinutes = cal.component(.hour, from: hotel.checkIn) * 60 + cal.component(.minute, from: hotel.checkIn)
            let index = placeStops.firstIndex { item in
                guard let time = item.time else { return false }
                return cal.component(.hour, from: time) * 60 + cal.component(.minute, from: time) > checkInMinutes
            }
            if let index {
                placeStops.insert((checkInStop, nil), at: index)
            } else {
                placeStops.append((checkInStop, nil))
                endsAtCheckIn = true
            }
        }
        result += placeStops.map(\.stop)

        // End: back at tonight's hotel (unless the day already ends with checking in there).
        if includeHotel, !endsAtCheckIn, let end = endHotelStop, result.last?.id != end.id {
            result.append(end)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $position) {
                ForEach(legs) { leg in
                    if let route = leg.route {
                        MapPolyline(route.polyline)
                            .stroke(Color.accentColor, lineWidth: 5)
                    } else {
                        MapPolyline(coordinates: [leg.from.coordinate, leg.to.coordinate])
                            .stroke(.gray, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    }
                }
                ForEach(stops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                        StopIcon(stop: stop, size: 30)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .frame(maxHeight: .infinity)

            List {
                Section {
                    Picker("Travel mode", selection: $mode) {
                        ForEach(TravelMode.allCases) { m in
                            Label(m.label, systemImage: m.systemImage).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if hasHotel {
                        Toggle(isOn: $includeHotel) {
                            Label("Start & end at hotel", systemImage: "bed.double.fill")
                        }
                        .tint(.purple)
                    }

                    if stops.count < 2 {
                        Text("Add another place to this day to see the route.")
                            .foregroundStyle(.secondary)
                    } else if isLoading && legs.allSatisfy({ $0.route == nil }) {
                        HStack { ProgressView(); Text("Finding route…").foregroundStyle(.secondary) }
                    } else {
                        summaryRow
                    }
                }

                if !legs.isEmpty {
                    Section("Legs") {
                        ForEach(legs) { leg in
                            legRow(leg)
                        }
                    }
                }

                Section {
                    Button {
                        openDayInAppleMaps()
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                    }
                    Button {
                        openDayInGoogleMaps(transit: false)
                    } label: {
                        Label("Open in Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    Button {
                        openDayInGoogleMaps(transit: true)
                    } label: {
                        Label("Public transport in Google Maps", systemImage: "tram.fill")
                    }
                    .disabled(stops.count < 2)
                } footer: {
                    Text("Tap a leg for public transport directions in Apple Maps.")
                }
            }
            .listStyle(.insetGrouped)
            .frame(height: 380)
        }
        .navigationTitle(trip.dayTitle(day))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(mode.rawValue)-\(includeHotel)-\(airportCoordinate != nil)") {
            // Find the arrival airport first so the route starts there.
            if airportCoordinate == nil, let flight = arrivingFlight {
                airportCoordinate = await AirportLocator.coordinate(code: flight.toCode, city: flight.toCity)
                if airportCoordinate != nil { return }  // the task restarts with the airport included
            }
            await loadRoutes()
        }
    }

    private var summaryRow: some View {
        let routes = legs.compactMap(\.route)
        let time = routes.reduce(0) { $0 + $1.expectedTravelTime }
        let distance = routes.reduce(0) { $0 + $1.distance }
        return HStack {
            Label(formatDuration(time), systemImage: mode.systemImage)
                .font(.app(.headline))
            Spacer()
            Text(formatDistance(distance))
                .foregroundStyle(.secondary)
            Text("· \(places.count) stops")
                .foregroundStyle(.secondary)
        }
    }

    private func legRow(_ leg: RouteLeg) -> some View {
        Menu {
            Button { openLegInAppleMaps(leg, modeKey: mode.appleMapsKey) } label: {
                Label("\(mode.label) in Apple Maps", systemImage: mode.systemImage)
            }
            Button { openLegInAppleMaps(leg, modeKey: MKLaunchOptionsDirectionsModeTransit) } label: {
                Label("Public transport in Apple Maps", systemImage: "tram.fill")
            }
        } label: {
            HStack(spacing: 10) {
                StopIcon(stop: leg.from, size: 22)
                Image(systemName: "arrow.right").font(.app(.caption)).foregroundStyle(.secondary)
                StopIcon(stop: leg.to, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(leg.from.name) → \(leg.to.name)")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let route = leg.route {
                        Text("\(formatDuration(route.expectedTravelTime)) · \(formatDistance(route.distance))")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(isLoading ? "Finding route…" : "Route unavailable (check internet)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Routing

    private func loadRoutes() async {
        let stops = self.stops
        guard stops.count >= 2 else { legs = []; return }
        let pairs = Array(zip(stops, stops.dropFirst()))
        legs = pairs.map { RouteLeg(from: $0.0, to: $0.1, route: cache[key($0.0, $0.1)]) }
        isLoading = true
        defer { isLoading = false }

        // One request per leg, sequentially to stay under Apple's rate limit.
        for (index, (from, to)) in pairs.enumerated() {
            if Task.isCancelled { return }
            let k = key(from, to)
            if cache[k] != nil { continue }
            let request = MKDirections.Request()
            request.source = mapItem(for: from)
            request.destination = mapItem(for: to)
            request.transportType = mode.transportType
            if let route = try? await MKDirections(request: request).calculate().routes.first {
                cache[k] = route
                if index < legs.count { legs[index] = RouteLeg(from: from, to: to, route: route) }
            }
        }
    }

    private func key(_ a: RouteStop, _ b: RouteStop) -> String {
        "\(mode.rawValue)|\(a.coordinate.latitude),\(a.coordinate.longitude)|\(b.coordinate.latitude),\(b.coordinate.longitude)"
    }

    private func mapItem(for stop: RouteStop) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        return item
    }

    // MARK: - Open in other apps

    private func openDayInAppleMaps() {
        MKMapItem.openMaps(with: stops.map(mapItem(for:)),
                           launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.appleMapsKey])
    }

    private func openLegInAppleMaps(_ leg: RouteLeg, modeKey: String) {
        MKMapItem.openMaps(with: [mapItem(for: leg.from), mapItem(for: leg.to)],
                           launchOptions: [MKLaunchOptionsDirectionsModeKey: modeKey])
    }

    private func openDayInGoogleMaps(transit: Bool) {
        let stops = self.stops
        guard let first = stops.first else { return }
        func coord(_ s: RouteStop) -> String { "\(s.coordinate.latitude),\(s.coordinate.longitude)" }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [URLQueryItem(name: "api", value: "1")]
        if stops.count == 1 {
            components = URLComponents(string: "https://www.google.com/maps/search/")!
            items.append(URLQueryItem(name: "query", value: coord(first)))
        } else {
            items.append(URLQueryItem(name: "origin", value: coord(first)))
            items.append(URLQueryItem(name: "destination", value: coord(stops.last!)))
            let middle = stops.dropFirst().dropLast()
            // Google Maps ignores waypoints for public transport, so only send them for walk/drive.
            if !middle.isEmpty && !transit {
                items.append(URLQueryItem(name: "waypoints", value: middle.map(coord).joined(separator: "|")))
            }
            items.append(URLQueryItem(name: "travelmode", value: transit ? "transit" : mode.googleKey))
        }
        components.queryItems = items
        if let url = components.url { openURL(url) }
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

/// Numbered badge for a place, bed icon for the hotel, plane for the airport.
struct StopIcon: View {
    let stop: RouteStop
    var size: CGFloat = 26

    var body: some View {
        if let number = stop.number {
            StopBadge(number: number, size: size)
        } else if stop.isAirport {
            Image(systemName: "airplane.arrival")
                .font(.poppins(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.indigo))
                .overlay(Circle().stroke(.white, lineWidth: 2))
        } else {
            Image(systemName: "bed.double.fill")
                .font(.poppins(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.purple))
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }
}
