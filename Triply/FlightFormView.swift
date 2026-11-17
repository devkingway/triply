import SwiftUI
import SwiftData

struct FlightFormView: View {
    let trip: Trip
    var flight: Flight?
    /// When set, the form starts as the return of this flight (airports swapped).
    var returnOf: Flight?
    /// When set, the form starts as the next leg after this flight (a transfer at its arrival airport).
    var connectingFrom: Flight?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var airline = ""
    @State private var flightNumber = ""
    @State private var fromCode = "KUL"
    @State private var toCode = ""
    @State private var departure = Date.now
    @State private var arrival = Date.now
    @State private var fromTerminal = ""
    @State private var toTerminal = ""
    @State private var seat = ""
    @State private var bookingReference = ""
    @State private var bookingSite = ""
    @State private var baggage = ""
    @State private var notes = ""
    @State private var price: Double?
    @State private var currency = "MYR"
    @State private var rate: Double = 1
    @State private var rateLoading = false
    @State private var rateFailed = false
    @State private var loaded = false
    @State private var remindersOn = true
    /// When the ticket was paid; the budget counts it on this day.
    @State private var paidOn = Date.now
    /// How many people the price covers, and how many of their tickets you pay for.
    @State private var passengers = 1
    @State private var paidPortions = 1

    private static let sites = ["", "Airline website", "Airline app", "Trip.com", "Agoda", "Expedia", "Traveloka", "Skyscanner", "Travel agent", "Other"]
    private static let airlines = ["", "Malaysia Airlines", "AirAsia", "AirAsia X", "Batik Air", "Firefly", "Singapore Airlines", "Scoot",
                                   "Japan Airlines", "ANA", "Korean Air", "Asiana", "Cathay Pacific", "Thai Airways", "Vietnam Airlines",
                                   "Garuda Indonesia", "Emirates", "Qatar Airways", "Turkish Airlines", "Qantas"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Flight") {
                    Picker("Airline", selection: $airline) {
                        ForEach(airlineOptions, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                    }
                    TextField("Flight number (e.g. MH88)", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    airportField("From", code: $fromCode)
                    DatePicker("Departs", selection: $departure, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Airports.timeZone(for: fromCode))
                    TextField("Departure terminal", text: $fromTerminal)
                } header: {
                    Text("Departure")
                } footer: {
                    if let previous = connectingFrom {
                        let gap = departure.timeIntervalSince(previous.arrival)
                        if gap < 0 {
                            Text("Leaves before \(previous.title.isEmpty ? "the last flight" : previous.title) lands (\(previous.arrivalTimeText)). Check the time.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Transfer at \(Airports.find(fromCode)?.city ?? fromCode): \(Flight.layoverText(gap)) after landing at \(previous.arrivalTimeText). Times are local time.")
                        }
                    } else {
                        Text("Times are local time at \(Airports.find(fromCode)?.city ?? "the airport").")
                    }
                }

                Section {
                    airportField("To", code: $toCode)
                    DatePicker("Arrives", selection: $arrival, in: departure..., displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, Airports.timeZone(for: toCode))
                    TextField("Arrival terminal", text: $toTerminal)
                } header: {
                    Text("Arrival")
                } footer: {
                    Text("Flight time: \(Duration.seconds(max(0, arrival.timeIntervalSince(departure))).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))). Local time at \(Airports.find(toCode)?.city ?? "the airport").")
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
                        Text("≈ \((price * rate).myr). Counted in your budget on the day you paid.")
                    } else {
                        Text(connectingFrom != nil
                             ? "If both flights were one ticket, leave this at 0. The price on the first flight covers the whole trip."
                             : "What you paid for this flight (all passengers). Split it below. Counted in your budget on the day you paid. If a return ticket was one price, put it on one flight and leave the other at 0.")
                    }
                }

                Section {
                    Stepper(value: $passengers, in: 1...20) {
                        LabeledContent("Passengers", value: passengers == 1 ? "1 person" : "\(passengers) people")
                    }
                    if passengers > 1 {
                        Picker("I pay for", selection: $paidPortions) {
                            ForEach(0...passengers, id: \.self) { n in
                                Text(n == 0 ? "Nothing (0)" : n == 1 ? "Just me (1)" : n == passengers ? "Everyone (\(n))" : "\(n) people").tag(n)
                            }
                        }
                    }
                } header: {
                    Text("Split the bill")
                } footer: {
                    if passengers > 1 {
                        if let price, price > 0 {
                            Text(paidPortions == 0
                                 ? "You pay nothing: someone else paid for the tickets. It stays in Expenses at RM 0.00."
                                 : paidPortions > 1
                                 ? "You pay \(paidPortions) of \(passengers) tickets: ≈ \(myShareMYR.myr) of \((price * rate).myr). Each other passenger you cover shows in Expenses as \"Owes you\". Add their names in the flight details and tick them off when they pay you back."
                                 : "You pay \(paidPortions) of \(passengers) tickets: ≈ \(myShareMYR.myr) of \((price * rate).myr). Only your part goes in the budget.")
                        } else {
                            Text("Only the part you pay goes in your budget.")
                        }
                    } else {
                        Text("Booked for a group? Add how many people the price covers and how many tickets you pay for.")
                    }
                }

                Section("Booking") {
                    TextField("Booking reference (PNR)", text: $bookingReference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Seat (e.g. 32A)", text: $seat)
                        .textInputAutocapitalization(.characters)
                    TextField("Baggage (e.g. 30kg checked + 7kg cabin)", text: $baggage)
                    Picker("Booked on", selection: $bookingSite) {
                        ForEach(Self.sites, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                    }
                    NotesEditor(placeholder: "Notes (e.g. meal included, online check-in opens 48h)", text: $notes)
                }

                Section {
                    Toggle(isOn: $remindersOn) {
                        Label("Flight reminders", systemImage: "bell.badge.fill")
                    }
                    .tint(Theme.teal)
                } footer: {
                    Text("Notifies you when check-in opens (48 hours before) and when to leave for the airport (6 hours before, to arrive 3 hours early).")
                }
            }
            .navigationTitle(flight != nil ? "Edit flight" : connectingFrom != nil ? "Connecting flight" : returnOf != nil ? "Add return flight" : "Add flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(fromCode.count < 3 || toCode.count < 3)
                }
            }
            .onAppear(perform: load)
            .onChange(of: passengers) { _, newValue in
                paidPortions = min(paidPortions, newValue)
            }
            .onChange(of: departure) { _, new in
                if arrival < new { arrival = new.addingTimeInterval(3 * 3600) }
            }
            .task(id: currency) {
                if let flight, flight.currency == currency, flight.rateToMYR > 0 { return }
                await fetchRate()
            }
        }
    }

    private func airportField(_ label: String, code: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("Code", text: code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.app(.headline))
                .frame(width: 70)
                .onChange(of: code.wrappedValue) { _, new in
                    let cleaned = String(new.uppercased().filter(\.isLetter).prefix(3))
                    if cleaned != new { code.wrappedValue = cleaned }
                }
            Spacer()
            if let airport = Airports.find(code.wrappedValue) {
                Text(airport.city).foregroundStyle(.secondary).lineLimit(1)
            } else if code.wrappedValue.count == 3 {
                Text("Uses phone's time zone").font(.app(.caption)).foregroundStyle(.orange)
            }
        }
    }

    private var airlineOptions: [String] {
        Self.airlines.contains(airline) ? Self.airlines : Self.airlines + [airline]
    }

    private var currencyOptions: [String] {
        var list = Currencies.common
        for code in [trip.localCurrency, currency] where !list.contains(code) { list.append(code) }
        return list
    }

    private var myShareMYR: Double {
        (price ?? 0) * rate * Double(min(paidPortions, passengers)) / Double(max(passengers, 1))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let flight {
            airline = flight.airline
            flightNumber = flight.flightNumber
            fromCode = flight.fromCode
            toCode = flight.toCode
            departure = flight.departure
            arrival = flight.arrival
            fromTerminal = flight.fromTerminal
            toTerminal = flight.toTerminal
            seat = flight.seat
            bookingReference = flight.bookingReference
            bookingSite = flight.bookingSite
            baggage = flight.baggage
            notes = flight.notes
            remindersOn = flight.remindersOn
            price = flight.price > 0 ? flight.price : nil
            currency = flight.currency
            rate = flight.rateToMYR
            paidOn = flight.paidOn ?? flight.departure
            passengers = max(flight.passengers, 1)
            paidPortions = flight.myPortions
        } else if let previous = connectingFrom {
            // Next leg: leaves from where the last one lands, usually on the same booking.
            paidOn = previous.paidOn ?? .now
            airline = previous.airline
            fromCode = previous.toCode
            fromTerminal = previous.toTerminal
            toCode = ""
            bookingReference = previous.bookingReference
            bookingSite = previous.bookingSite
            baggage = previous.baggage
            currency = previous.currency
            remindersOn = previous.remindersOn
            passengers = max(previous.passengers, 1)
            paidPortions = previous.myPortions
            departure = previous.arrival.addingTimeInterval(2 * 3600)
            arrival = departure.addingTimeInterval(3 * 3600)
        } else if let returnOf {
            paidOn = returnOf.paidOn ?? .now
            airline = returnOf.airline
            fromCode = returnOf.toCode
            toCode = returnOf.fromCode
            bookingReference = returnOf.bookingReference
            bookingSite = returnOf.bookingSite
            baggage = returnOf.baggage
            currency = returnOf.currency
            passengers = max(returnOf.passengers, 1)
            paidPortions = returnOf.myPortions
            let day = trip.date(forDay: trip.dayCount - 1)
            departure = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            arrival = departure.addingTimeInterval(returnOf.duration > 0 ? returnOf.duration : 3 * 3600)
        } else {
            let day = trip.startDate
            departure = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            arrival = departure.addingTimeInterval(3 * 3600)
            currency = "MYR"
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
        let target: Flight
        if let flight {
            target = flight
        } else {
            target = Flight(airline: "", flightNumber: "", fromCode: "", toCode: "", departure: departure, arrival: arrival)
            context.insert(target)
            target.trip = trip
        }
        target.airline = airline
        target.flightNumber = flightNumber.replacingOccurrences(of: " ", with: "").uppercased()
        target.fromCode = fromCode
        target.toCode = toCode
        target.departure = departure
        target.arrival = max(arrival, departure)
        target.fromTerminal = fromTerminal
        target.toTerminal = toTerminal
        target.seat = seat.uppercased()
        target.bookingReference = bookingReference.trimmingCharacters(in: .whitespaces).uppercased()
        target.bookingSite = bookingSite
        target.baggage = baggage
        target.notes = notes
        target.remindersOn = remindersOn
        target.price = price ?? 0
        target.currency = currency
        target.rateToMYR = rate
        target.paidOn = paidOn
        target.passengers = passengers
        target.paidPortions = min(paidPortions, passengers)
        target.syncExpense(in: context)
        Toaster.shared.show(flight == nil ? "Flight \(fromCode) → \(toCode) added" : "Flight updated", systemImage: "airplane")
        // Ask for notification permission the first time, then (re)schedule reminders.
        Task { @MainActor in
            if remindersOn { await FlightReminders.requestPermission() }
            await FlightReminders.sync(in: context)
        }
        dismiss()
    }
}
