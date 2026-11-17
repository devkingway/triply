import SwiftUI
import SwiftData

/// Add or edit a ticket booking (attraction, show, train, tour).
struct TicketFormView: View {
    let trip: Trip
    var ticket: Ticket?
    /// Adding from a place's page: the ticket starts linked to it.
    var place: Place? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    /// The itinerary place the ticket is for (shows under it).
    @State private var linkedPlace: Place?
    @State private var venue = ""
    @State private var startsAt = Date.now
    @State private var hasTime = true
    @State private var people = 1
    @State private var paidPortions = 1
    @State private var price: Double?
    @State private var currency = "MYR"
    @State private var rate: Double = 1
    @State private var rateLoading = false
    @State private var rateFailed = false
    @State private var paidOn = Date.now
    @State private var bookingReference = ""
    @State private var bookingSite = ""
    @State private var seat = ""
    @State private var notes = ""
    @State private var loaded = false

    private static let sites = ["", "Klook", "KKday", "Trip.com", "GetYourGuide", "Official website", "Ticket counter", "Travel agent", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Place", selection: placeBinding) {
                        Text("None").tag(Place?.none)
                        ForEach(placeOptions) { option in
                            Text(placeLabel(option)).tag(Place?.some(option))
                        }
                    }
                } header: {
                    Text("For place")
                } footer: {
                    Text(linkedPlace == nil
                         ? "Pick a place from your itinerary and the ticket shows under it."
                         : "Shows under \(linkedPlace?.name ?? "") in your itinerary.")
                }

                Section("Ticket") {
                    TextField("Name (e.g. Tokyo Skytree, Shinkansen)", text: $name)
                    // Place names: no autocorrect (it turns "Toyosu" into "Toyo's").
                    TextField("Venue or station (optional)", text: $venue)
                        .autocorrectionDisabled()
                }

                Section {
                    DatePicker("Date", selection: $startsAt, displayedComponents: .date)
                    Toggle("Set a time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Time", selection: $startsAt, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("When")
                }

                Section {
                    HStack {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField("Price", value: $price, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if currency != "MYR" {
                        HStack {
                            Text("1 \(currency) = RM").foregroundStyle(.secondary)
                            TextField("rate", value: $rate, format: .number.precision(.significantDigits(1...6)))
                                .keyboardType(.decimalPad)
                            Spacer()
                            if rateLoading { ProgressView() }
                            else if rateFailed { Image(systemName: "wifi.slash").foregroundStyle(.orange) }
                        }
                        .font(.app(.subheadline))
                    }
                    DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                } header: {
                    Text("Price")
                } footer: {
                    if let price, price > 0, currency != "MYR" {
                        Text("≈ \((price * rate).myr) for everyone. Added to your budget under Tickets, on the day you paid.")
                    } else {
                        Text("What you paid for all the tickets. Added to your budget under Tickets, on the day you paid.")
                    }
                }

                Section {
                    Stepper(value: $people, in: 1...30) {
                        LabeledContent("People", value: people == 1 ? "1 person" : "\(people) people")
                    }
                    if people > 1 {
                        Picker("I pay for", selection: $paidPortions) {
                            ForEach(0...people, id: \.self) { n in
                                Text(n == 0 ? "Nothing (0)" : n == 1 ? "Just me (1)" : n == people ? "Everyone (\(n))" : "\(n) people").tag(n)
                            }
                        }
                    }
                } header: {
                    Text("Split the bill")
                } footer: {
                    if people > 1, let price, price > 0 {
                        Text(paidPortions == 0
                             ? "You pay nothing: someone else paid. It stays in Expenses at RM 0.00."
                             : paidPortions > 1
                             ? "You pay \(paidPortions) of \(people) tickets: ≈ \(myShareMYR.myr) of \((price * rate).myr). Each other person you cover shows in Expenses as \"Owes you\". Add their names in the ticket details and tick them off when they pay you back."
                             : "You pay 1 of \(people) tickets: ≈ \(myShareMYR.myr) of \((price * rate).myr). Only your part goes in the budget.")
                    } else if people > 1 {
                        Text("Only the part you pay goes in your budget.")
                    } else {
                        Text("Bought tickets for a group? Add how many people and how many tickets you pay for.")
                    }
                }

                Section("Booking") {
                    TextField("Booking reference", text: $bookingReference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Seat, gate or time slot (optional)", text: $seat)
                    Picker("Booked on", selection: $bookingSite) {
                        ForEach(siteOptions, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                    }
                    NotesEditor(placeholder: "Notes (e.g. collect at counter B1, bring passport)", text: $notes)
                }
            }
            .navigationTitle(ticket == nil ? "Add ticket" : "Edit ticket")
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
            .onAppear(perform: load)
            .onChange(of: people) { _, newValue in
                paidPortions = min(paidPortions, newValue)
            }
            .task(id: currency) {
                if let ticket, ticket.currency == currency, ticket.rateToMYR > 0 { return }
                await fetchRate()
            }
        }
    }

    /// The trip's places: scheduled ones by day and order, then saved items.
    private var placeOptions: [Place] {
        trip.places.sorted {
            ($0.dayIndex ?? Int.max, $0.order) < ($1.dayIndex ?? Int.max, $1.order)
        }
    }

    /// e.g. "Day 1 · Tokyo Skytree", or "Saved · Ichiran".
    private func placeLabel(_ place: Place) -> String {
        "\(place.dayIndex.map { "Day \($0 + 1)" } ?? "Saved") · \(place.name)"
    }

    /// Picking a place fills in the name, venue and date when they're still empty or untouched.
    private var placeBinding: Binding<Place?> {
        Binding {
            linkedPlace
        } set: { picked in
            linkedPlace = picked
            if let picked { prefill(from: picked) }
        }
    }

    private func prefill(from place: Place) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = place.name }
        if venue.trimmingCharacters(in: .whitespaces).isEmpty { venue = place.address }
        if let day = place.dayIndex, !trip.isDraft {
            let date = trip.date(forDay: day)
            let cal = Calendar.current
            let time = place.time ?? startsAt
            let parts = cal.dateComponents([.hour, .minute], from: time)
            startsAt = cal.date(bySettingHour: parts.hour ?? 10, minute: parts.minute ?? 0, second: 0, of: date) ?? date
        }
    }

    private var myShareMYR: Double {
        (price ?? 0) * rate * Double(min(paidPortions, people)) / Double(max(people, 1))
    }

    private var siteOptions: [String] {
        Self.sites.contains(bookingSite) ? Self.sites : Self.sites + [bookingSite]
    }

    private var currencyOptions: [String] {
        var list = Currencies.common
        for code in [trip.localCurrency, currency] where !list.contains(code) { list.append(code) }
        return list
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let ticket {
            linkedPlace = ticket.place
            name = ticket.name
            venue = ticket.venue
            startsAt = ticket.startsAt
            hasTime = ticket.hasTime
            people = max(ticket.people, 1)
            paidPortions = ticket.myPortions
            price = ticket.price > 0 ? ticket.price : nil
            currency = ticket.currency
            rate = ticket.rateToMYR
            paidOn = ticket.paidOn ?? ticket.startsAt
            bookingReference = ticket.bookingReference
            bookingSite = ticket.bookingSite
            seat = ticket.seat
            notes = ticket.notes
        } else {
            // Attractions are usually paid in the local currency, on a trip day.
            currency = trip.localCurrency
            let cal = Calendar.current
            let start = cal.startOfDay(for: trip.startDate)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.endDate)) ?? trip.endDate
            let day = (start..<end).contains(.now) ? Date.now : trip.startDate
            startsAt = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
            if let place {
                linkedPlace = place
                prefill(from: place)
            }
        }
    }

    private func fetchRate() async {
        if currency == "MYR" { rate = 1; rateFailed = false; return }
        rateLoading = true
        defer { rateLoading = false }
        if let value = await ExchangeRates.rateToMYR(currency) {
            rate = value
            rateFailed = false
        } else {
            rateFailed = true
        }
    }

    private func save() {
        let target: Ticket
        if let ticket {
            target = ticket
        } else {
            target = Ticket(name: "", startsAt: startsAt)
            context.insert(target)
            target.trip = trip
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.place = linkedPlace
        target.venue = venue.trimmingCharacters(in: .whitespaces)
        // Without a time, keep it at midday so time zones don't move it to another day.
        target.startsAt = hasTime ? startsAt
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: startsAt) ?? startsAt
        target.hasTime = hasTime
        target.people = people
        target.paidPortions = min(paidPortions, people)
        target.price = price ?? 0
        target.currency = currency
        target.rateToMYR = rate
        target.paidOn = paidOn
        target.bookingReference = bookingReference.trimmingCharacters(in: .whitespaces).uppercased()
        target.bookingSite = bookingSite
        target.seat = seat
        target.notes = notes
        target.syncExpense(in: context)
        Toaster.shared.show(ticket == nil ? "\(target.name) ticket added" : "Ticket updated", systemImage: "ticket.fill")
        dismiss()
    }
}
