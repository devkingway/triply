import SwiftUI
import MapKit
import CoreLocation
import SwiftData

/// During a trip: everything needed for today at a glance.
struct TodayView: View {
    let trip: Trip

    @State private var location = LocationProvider()
    @State private var walkETA: TimeInterval?
    @State private var transitETA: TimeInterval?
    @State private var etaFinished = false
    @State private var showingExpense = false
    @State private var driverHotel: Hotel?
    /// Set when Walk/Transit/Drive is tapped: shows the "which map app?" pop-up.
    @State private var directions: DirectionsRequest?
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    /// The stop just ticked off, so the card can offer Undo.
    @State private var lastDone: Place?
    /// Auto-arrive: the stop the user is standing at, and since when.
    @State private var arrivedID: PersistentIdentifier?
    @State private var arrivedAt: Date?
    @AppStorage("autoNextStop") private var autoNextStop = true

    private var day: Int { trip.todayIndex ?? 0 }
    private var stops: [Place] { trip.places(onDay: day) }
    private var next: Place? { trip.nextStop(onDay: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                nextStopCard
                if !stops.isEmpty { planCard }
                spendingCard
                ForEach(trip.flights(onDay: day)) { flight in
                    NavigationLink { FlightDetailView(flight: flight) } label: { FlightCard(flight: flight) }
                        .buttonStyle(PressableCardStyle())
                }
                // Tickets for today's stops, ready to show at the entrance.
                ForEach(stops.flatMap(\.sortedTickets)) { ticket in
                    NavigationLink { TicketDetailView(ticket: ticket) } label: { TicketCard(ticket: ticket) }
                        .buttonStyle(PressableCardStyle())
                }
                if let hotel = trip.hotel(forNight: day) ?? trip.endHotel(forDay: day) {
                    hotelCard(hotel)
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingExpense) {
            ExpenseFormView(trip: trip)
        }
        .mapAppChooser($directions)
        .fullScreenCover(item: $driverHotel) { hotel in
            DriverCardView(hotel: hotel)
        }
        .task { location.request() }
        .onAppear { if autoNextStop { location.startFollowing() } }
        .onDisappear { location.stopFollowing() }
        .onChange(of: autoNextStop) { _, on in
            if on { location.startFollowing() } else { location.stopFollowing(); arrivedID = nil }
        }
        .onChange(of: location.location) { _, newValue in
            if let newValue { checkArrival(at: newValue) }
        }
        // Re-work travel times when the next stop changes or the user moves ~200 m (not on every GPS tick).
        .task(id: "\(next?.name ?? "")-\(roundedLocationKey)") { await loadETAs() }
    }

    // MARK: - Done / auto-arrive

    /// Location rounded to ~200 m, so travel times aren't re-fetched on every GPS update.
    private var roundedLocationKey: String {
        guard let c = location.location?.coordinate else { return "none" }
        return "\(Int(c.latitude * 500)),\(Int(c.longitude * 500))"
    }

    private func markDone(_ place: Place, automatically: Bool = false) {
        let wasNext = place.id == next?.id
        withAnimation(.snappy) { place.isDone = true }
        lastDone = place
        if arrivedID == place.persistentModelID { arrivedID = nil; arrivedAt = nil }
        try? context.save()
        Haptics.success()
        if automatically {
            let upcoming = trip.nextStop(onDay: day)
            Toaster.shared.show(upcoming.map { "Left \(place.name) · next: \($0.name)" } ?? "Left \(place.name) · all done today",
                                systemImage: "checkmark.circle.fill")
        } else if wasNext, trip.nextStop(onDay: day) == nil {
            Toaster.shared.show("All stops done today", systemImage: "party.popper.fill")
        }
    }

    private func undoDone(_ place: Place) {
        withAnimation(.snappy) { place.isDone = false }
        if lastDone?.id == place.id { lastDone = nil }
        try? context.save()
        Haptics.tap()
    }

    /// Auto-arrive: within ~150 m of the next stop counts as "here"; walking 300 m+ away after
    /// staying at least 5 minutes ticks it off and moves on to the following stop.
    private func checkArrival(at here: CLLocation) {
        guard autoNextStop, let next, next.hasLocation, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 100 else { return }
        let distance = here.distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
        if distance < 150 {
            if arrivedID != next.persistentModelID {
                arrivedID = next.persistentModelID
                arrivedAt = .now
            }
        } else if arrivedID == next.persistentModelID, distance > 300,
                  let arrivedAt, Date.now.timeIntervalSince(arrivedAt) > 5 * 60 {
            markDone(next, automatically: true)
        }
    }

    // MARK: - Cards

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.app(.largeTitle, .bold))
                Text("\(trip.name) · \(trip.phaseText)")
                    .font(.app(.headline))
                    .foregroundStyle(Theme.teal)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.app(.subheadline, .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Full trip (plan, budget, flights, hotels).
            NavigationLink(value: trip) {
                Text("Trip details")
                    .font(.app(.subheadline, .semibold))
            }
            .buttonStyle(.bordered)
            .tint(Theme.teal)
        }
    }

    @ViewBuilder
    private var nextStopCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("NEXT STOP", systemImage: "location.north.circle.fill")
                .font(.app(.caption, .heavy))
                .foregroundStyle(Theme.teal)
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.name).font(.app(.title2, .bold))
                        Spacer()
                        if let time = next.time {
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.app(.headline))
                                .foregroundStyle(Theme.teal)
                        }
                    }
                    if !next.address.isEmpty {
                        Text(next.address).font(.app(.subheadline)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                if arrivedID == next.persistentModelID {
                    Label("You're here", systemImage: "mappin.and.ellipse")
                        .font(.app(.caption, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange, in: Capsule())
                } else if next.hasLocation {
                    etaRow
                }
                if next.hasLocation {
                    HStack(spacing: 10) {
                        directionsButton(next, mode: .walk, icon: "figure.walk")
                        directionsButton(next, mode: .transit, icon: "tram.fill")
                        directionsButton(next, mode: .drive, icon: "car.fill")
                    }
                } else {
                    Label("No location yet · open it in the Itinerary tab to set one", systemImage: "mappin.slash")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            } else if !stops.isEmpty {
                Label("All done for today", systemImage: "party.popper.fill")
                    .font(.app(.title3, .bold))
                Text("You've finished every stop on Day \(day + 1).")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing planned for today yet.")
                    .foregroundStyle(.secondary)
                Text("Add places to Day \(day + 1) on the Itinerary tab.")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
            }
            if let lastDone, lastDone.isDone {
                HStack {
                    Label("\(lastDone.name) done", systemImage: "checkmark")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") { undoDone(lastDone) }
                        .font(.app(.caption, .bold))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var etaRow: some View {
        switch location.status {
        case .denied, .restricted:
            Label("Allow location in Settings to see travel time", systemImage: "location.slash")
                .font(.app(.caption)).foregroundStyle(.secondary)
        case .notDetermined:
            Button { location.request() } label: {
                Label("Show travel time from where I am", systemImage: "location")
            }
            .font(.app(.subheadline))
        default:
            if walkETA == nil && transitETA == nil {
                Label(location.location == nil ? "Finding your location…"
                      : (etaFinished ? "No route from your location" : "Working out travel time…"),
                      systemImage: etaFinished ? "map" : "clock")
                    .font(.app(.caption)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    if let walkETA { eta("figure.walk", walkETA) }
                    if let transitETA { eta("tram.fill", transitETA) }
                    Text("from you").font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func eta(_ icon: String, _ seconds: TimeInterval) -> some View {
        Label(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), systemImage: icon)
            .font(.app(.subheadline, .semibold))
    }

    private func directionsButton(_ place: Place, mode: TravelChoice, icon: String) -> some View {
        Button {
            directions = DirectionsRequest(name: place.name, coordinate: place.coordinate, mode: mode)
        } label: {
            Label(mode.label, systemImage: icon)
                .font(.app(.subheadline, .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Theme.teal)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's plan").font(.app(.headline))
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                NavigationLink { PlaceDetailView(place: place) } label: {
                    HStack(spacing: 10) {
                        StopBadge(number: index + 1, size: 24, done: place.isDone)
                        Text(place.name)
                            .foregroundStyle(place.isDone ? .secondary : (place.id == next?.id ? Theme.teal : .primary))
                            .strikethrough(place.isDone, color: .secondary)
                            .font(.app(.body, place.id == next?.id ? .semibold : .regular))
                        Spacer()
                        if let time = place.time {
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.app(.caption)).foregroundStyle(.secondary)
                        }
                        // Tick a stop off (or back on) by hand.
                        Button {
                            if place.isDone { undoDone(place) } else { markDone(place) }
                        } label: {
                            Image(systemName: place.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.app(.title3))
                                .foregroundStyle(place.isDone ? Theme.teal : Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(place.isDone ? "Mark \(place.name) not done" : "Mark \(place.name) done")
                    }
                }
                .buttonStyle(.plain)
            }
            Divider().padding(.top, 2)
            Toggle(isOn: $autoNextStop) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Move on automatically").font(.app(.subheadline, .medium))
                    Text("Ticks off a stop when you leave it (while Triply is open)")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.teal)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 0)
    }

    private var spendingCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spent today").font(.app(.caption, .semibold)).foregroundStyle(.secondary)
                Text(trip.spent(onDay: day).myr).font(.app(.title3, .bold))
                if trip.budget > 0 {
                    Text("\(trip.remaining.myr) left for the trip")
                        .font(.app(.caption))
                        .foregroundStyle(trip.remaining < 0 ? .red : .secondary)
                }
            }
            Spacer()
            Button { showingExpense = true } label: {
                Label("Add expense", systemImage: "plus")
                    .font(.app(.subheadline, .semibold))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .cardStyle(padding: 0)
    }

    private func hotelCard(_ hotel: Hotel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("TONIGHT", systemImage: "bed.double.fill")
                .font(.app(.caption, .heavy))
                .foregroundStyle(.purple)
            Text(hotel.name).font(.app(.title3, .bold))
            if !hotel.address.isEmpty {
                Text(hotel.address).font(.app(.subheadline)).foregroundStyle(.secondary)
            }
            if Calendar.current.isDateInToday(hotel.checkIn) {
                Label("Check-in from \(hotel.checkIn.formatted(date: .omitted, time: .shortened))", systemImage: "key.fill")
                    .font(.app(.caption, .semibold))
            }
            HStack(spacing: 10) {
                Button { driverHotel = hotel } label: {
                    Label("Show to driver", systemImage: "car.side.fill")
                        .font(.app(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                if let coordinate = hotel.coordinate {
                    Button {
                        directions = DirectionsRequest(name: hotel.name, coordinate: coordinate, mode: .transit)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.app(.subheadline, .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .purple, secondTint: .pink)
    }

    // MARK: - Travel time

    private func loadETAs() async {
        walkETA = nil
        transitETA = nil
        etaFinished = false
        guard let next, next.hasLocation, let here = location.location else { return }
        defer { etaFinished = true }
        func eta(_ type: MKDirectionsTransportType) async -> TimeInterval? {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: next.coordinate))
            request.transportType = type
            return try? await MKDirections(request: request).calculateETA().expectedTravelTime
        }
        walkETA = await eta(.walking)
        transitETA = await eta(.transit)
    }
}

/// Full-screen, high-contrast card to show a taxi driver where to go.
struct DriverCardView: View {
    let hotel: Hotel
    @Environment(\.dismiss) private var dismiss
    @State private var localAddress: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.app(.largeTitle))
                }
                .foregroundStyle(.secondary)
            }
            Text("Please take me to")
                .font(.app(.title2, .semibold))
                .foregroundStyle(.secondary)
            Text(hotel.name)
                .font(.poppins(size: 40, weight: .heavy))
                .minimumScaleFactor(0.5)
            if let localAddress, localAddress != hotel.address {
                Text(localAddress)
                    .font(.poppins(size: 30, weight: .bold))
                    .minimumScaleFactor(0.5)
            }
            if !hotel.address.isEmpty {
                Text(hotel.address)
                    .font(.app(.title3))
                    .foregroundStyle(.secondary)
            }
            if !hotel.phone.isEmpty {
                Label(hotel.phone, systemImage: "phone.fill").font(.app(.title3, .semibold))
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .task { localAddress = await Self.localLanguageAddress(for: hotel) }
    }

    /// The hotel's address written in the local language (e.g. Japanese in Tokyo), easier for drivers.
    static func localLanguageAddress(for hotel: Hotel) async -> String? {
        guard let coordinate = hotel.coordinate else { return nil }
        let spot = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        guard let country = try? await geocoder.reverseGeocodeLocation(spot).first?.isoCountryCode,
              let locale = localeByCountry[country] else { return nil }
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(spot, preferredLocale: Locale(identifier: locale)).first
        else { return nil }
        let parts = [mark.administrativeArea, mark.locality, mark.subLocality, mark.thoroughfare, mark.subThoroughfare].compactMap { $0 }
        return parts.isEmpty ? mark.name : parts.joined(separator: " ")
    }

    private static let localeByCountry: [String: String] = [
        "JP": "ja_JP", "KR": "ko_KR", "CN": "zh_CN", "TW": "zh_TW", "HK": "zh_HK", "MO": "zh_HK",
        "TH": "th_TH", "VN": "vi_VN", "ID": "id_ID", "KH": "km_KH", "MY": "ms_MY", "AE": "ar_AE",
        "SA": "ar_SA", "QA": "ar_QA", "FR": "fr_FR", "DE": "de_DE", "IT": "it_IT", "ES": "es_ES", "TR": "tr_TR",
    ]
}

/// Asks for "while using the app" location and keeps the latest position.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus
    var location: CLLocation?

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    /// Keep following the user while the Today page is open (for auto-arrive). Stops when it closes.
    private var following = false

    func startFollowing() {
        following = true
        manager.distanceFilter = 25
        if status == .authorizedWhenInUse || status == .authorizedAlways { manager.startUpdatingLocation() }
    }

    func stopFollowing() {
        following = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        if following { manager.startUpdatingLocation() } else { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
