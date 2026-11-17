import SwiftUI
import SwiftData
import MapKit

struct HotelFormView: View {
    let trip: Trip
    var hotel: Hotel?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var address = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var checkIn = Date.now
    @State private var checkOut = Date.now
    @State private var price: Double?
    @State private var currency = "MYR"
    @State private var rate: Double = 1
    @State private var rateLoading = false
    @State private var rateFailed = false
    @State private var confirmation = ""
    @State private var bookingSite = ""
    @State private var phone = ""
    @State private var notes = ""
    @State private var loaded = false
    @State private var paidAlready = true
    @State private var paidOn = Date.now
    @State private var guests = 1
    @State private var paidPortions = 1
    @State private var showingLocation = false

    private static let sites = ["", "Agoda", "Booking.com", "Trip.com", "Expedia", "Airbnb", "Hotels.com", "Hotel website", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Hotel") {
                    TextField("Hotel name", text: $name)
                    // Same search as adding a place: suggestions while typing, or drop a pin.
                    Button {
                        showingLocation = true
                    } label: {
                        HStack {
                            if address.isEmpty && latitude == nil {
                                Label("Set location on map", systemImage: "mappin.and.ellipse")
                            } else {
                                Label {
                                    Text(address.isEmpty ? "Pinned location" : address)
                                        .font(.app(.subheadline)).lineLimit(2)
                                } icon: {
                                    Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // Teal prompt until a location is set, then the address in normal text colour.
                    .tint(address.isEmpty && latitude == nil ? Theme.teal : Color.primary)
                }

                Section("Stay") {
                    DatePicker("Check-in", selection: $checkIn, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Check-out", selection: $checkOut, in: checkIn..., displayedComponents: [.date, .hourAndMinute])
                    LabeledContent("Nights", value: "\(nights)")
                }

                Section {
                    Stepper(value: $guests, in: 1...20) {
                        LabeledContent("Guests", value: guests == 1 ? "1 person" : "\(guests) people")
                    }
                    if guests > 1 {
                        Picker("I pay for", selection: $paidPortions) {
                            ForEach(0...guests, id: \.self) { n in
                                Text(n == 0 ? "Nothing (0)" : n == 1 ? "Just me (1)" : n == guests ? "Everyone (\(n))" : "\(n) people").tag(n)
                            }
                        }
                    }
                } header: {
                    Text("Guests")
                } footer: {
                    if guests > 1 {
                        if let price, price > 0 {
                            Text(paidPortions == 0
                                 ? "You pay nothing: someone else paid for the room. It stays in Expenses at RM 0.00."
                                 : paidPortions > 1
                                 ? "You pay \(paidPortions) of \(guests) portions: ≈ \(myShareMYR.myr) of \((price * rate).myr). Each other guest you cover shows in Expenses as \"Owes you\". Add their names in the hotel details and tick them off when they pay you back."
                                 : "You pay \(paidPortions) of \(guests) portions: ≈ \(myShareMYR.myr) of \((price * rate).myr) (\((myShareMYR / Double(nights)).myr) per night). Only your part goes in the budget.")
                        } else {
                            Text("Only the part you pay goes in your budget.")
                        }
                    }
                }

                Section {
                    HStack {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        TextField("Total price", value: $price, format: .number.precision(.fractionLength(0...2)))
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
                    Toggle("Already paid", isOn: $paidAlready)
                        .tint(Theme.teal)
                    if paidAlready {
                        DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                    }
                } header: {
                    Text("Price")
                } footer: {
                    if let price, price > 0 {
                        Text("≈ \((price * rate).myr) total · \((price * rate / Double(nights)).myr) per night. \(paymentNote)")
                    } else {
                        Text("The total for the whole stay. It's added to your budget automatically.")
                    }
                }

                Section("Booking") {
                    TextField("Confirmation number", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Booked on", selection: $bookingSite) {
                        ForEach(Self.sites, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
                    }
                    TextField("Hotel phone", text: $phone)
                        .keyboardType(.phonePad)
                    NotesEditor(placeholder: "Notes (e.g. breakfast included, late check-in)", text: $notes)
                }
            }
            .navigationTitle(hotel == nil ? "Add hotel" : "Edit hotel")
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
            .onChange(of: guests) { _, newValue in
                paidPortions = min(paidPortions, newValue)
            }
            .sheet(isPresented: $showingLocation) {
                PlaceSearchView(trip: trip, dayIndex: nil,
                                onPick: { picked in
                                    if name.trimmingCharacters(in: .whitespaces).isEmpty { name = picked.name }
                                    address = picked.address
                                    latitude = picked.coordinate.latitude
                                    longitude = picked.coordinate.longitude
                                    if phone.isEmpty, let number = picked.phone { phone = number }
                                },
                                pickTitle: "Hotel location",
                                nearCoordinate: latitude.flatMap { lat in longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } })
            }
            .onChange(of: checkIn) { _, newValue in
                if checkOut <= newValue {
                    checkOut = Calendar.current.date(byAdding: .day, value: 1, to: newValue) ?? newValue
                }
            }
            .task(id: currency) {
                if let hotel, hotel.currency == currency, hotel.rateToMYR > 0 { return }
                await fetchRate()
            }
        }
    }

    private var paymentNote: String {
        paidAlready
            ? "Counted in your budget on \(paidOn.formatted(.dateTime.day().month(.abbreviated).year()))."
            : "Pay at the hotel: counted in your budget on check-in day."
    }

    /// Your part of the total price, in RM.
    private var myShareMYR: Double {
        (price ?? 0) * rate * Double(min(paidPortions, guests)) / Double(max(guests, 1))
    }

    private var nights: Int {
        let cal = Calendar.current
        return max(1, cal.dateComponents([.day], from: cal.startOfDay(for: checkIn), to: cal.startOfDay(for: checkOut)).day ?? 1)
    }

    private var currencyOptions: [String] {
        var list = Currencies.common
        for code in [trip.localCurrency, currency] where !list.contains(code) { list.append(code) }
        return list
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let hotel {
            name = hotel.name
            address = hotel.address
            latitude = hotel.latitude
            longitude = hotel.longitude
            checkIn = hotel.checkIn
            checkOut = hotel.checkOut
            price = hotel.price > 0 ? hotel.price : nil
            currency = hotel.currency
            rate = hotel.rateToMYR
            confirmation = hotel.confirmationNumber
            bookingSite = hotel.bookingSite
            phone = hotel.phone
            notes = hotel.notes
            paidAlready = hotel.paidOn != nil
            paidOn = hotel.paidOn ?? .now
            guests = max(hotel.guests, 1)
            paidPortions = hotel.myPortions
        } else {
            // Default: check in on the first night with no hotel, at 3pm; check out next day at 11am.
            let cal = Calendar.current
            let day = trip.nightsWithoutHotel.first ?? 0
            let inDate = trip.date(forDay: day)
            checkIn = cal.date(bySettingHour: 15, minute: 0, second: 0, of: inDate) ?? inDate
            let lastNight = trip.nightsWithoutHotel.reduce(day) { $1 == $0 + 1 ? $1 : $0 }
            let outDate = trip.date(forDay: lastNight + 1)
            checkOut = cal.date(bySettingHour: 11, minute: 0, second: 0, of: outDate) ?? outDate
            currency = trip.localCurrency
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
        let target: Hotel
        if let hotel {
            target = hotel
        } else {
            target = Hotel(name: "", checkIn: checkIn, checkOut: checkOut)
            context.insert(target)
            target.trip = trip
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.address = address
        target.latitude = latitude
        target.longitude = longitude
        target.checkIn = checkIn
        target.checkOut = checkOut
        target.price = price ?? 0
        target.currency = currency
        target.rateToMYR = rate
        target.confirmationNumber = confirmation.trimmingCharacters(in: .whitespaces)
        target.bookingSite = bookingSite
        target.phone = phone
        target.notes = notes
        target.paidOn = paidAlready ? paidOn : nil
        target.guests = guests
        target.paidPortions = min(paidPortions, guests)
        target.syncExpense(in: context)
        Toaster.shared.show(hotel == nil ? "Hotel added" : "Hotel updated", systemImage: "bed.double.fill")
        dismiss()
    }
}
