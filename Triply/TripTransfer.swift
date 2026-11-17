import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Export a trip's itinerary or expenses to a JSON file, and import such a file back into a trip.
///
/// - Itinerary: places on each day and saved ideas, with times, notes and saved links.
/// - Expenses: your expenses plus flight and hotel bookings (their costs appear in Expenses),
///   including splits, "bought for" friends and who has paid you back.
/// Attached documents (boarding passes, hotel confirmations) aren't included.
enum TripTransfer {
    enum Kind: String, Codable {
        case itinerary, expenses

        var title: String { self == .itinerary ? "Itinerary" : "Expenses" }
    }

    // MARK: - File format

    struct FileContents: Codable {
        var format = "tripple"
        var version = 1
        var kind: Kind
        var exportedAt: Date
        var trip: TripInfo
        var places: [PlaceItem]?
        var expenses: [ExpenseItem]?
        var flights: [FlightItem]?
        var hotels: [HotelItem]?
        var tickets: [TicketItem]?
    }

    struct TicketItem: Codable {
        var name: String
        var venue: String
        var startsAt: Date
        var hasTime: Bool
        var bookingReference: String
        var bookingSite: String
        var seat: String
        var notes: String
        var price: Double
        var currency: String
        var rateToMYR: Double
        var paidOn: Date?
        var people: Int
        var paidPortions: Int
        var guestsPaidFor: [GuestItem]
        /// The itinerary place it's for, matched by name on import.
        var placeName: String?
    }

    struct TripInfo: Codable {
        var name: String
        var destination: String
        var startDate: Date
        var endDate: Date
        var isDraft: Bool
        var draftDays: Int
        var localCurrency: String
        var budget: Double
    }

    struct PlaceItem: Codable {
        var name: String
        var address: String
        var latitude: Double
        var longitude: Double
        var hasLocation: Bool
        /// `nil` = saved idea.
        var dayIndex: Int?
        var order: Int
        var time: Date?
        var notes: String
        var isDone: Bool
        var links: [LinkItem]
    }

    struct LinkItem: Codable {
        var url: String
        var note: String
    }

    struct ExpenseItem: Codable {
        var title: String
        var amount: Double
        var currency: String
        var rateToMYR: Double
        var category: String
        var date: Date
        var notes: String
        var sharedBy: Int
        var paidPortions: Int
        var splitMode: String
        var myShareValue: Double
        var paidForName: String?
        var isRepaid: Bool
        var repaidAt: Date?
        var taxRefundType: String?
        var taxRefundValue: Double
        /// Receipt lines (missing in files from older versions).
        var items: [ExpenseLineItem]?
        /// Discount on the bill (missing in files from older versions).
        var discountType: String? = nil
        var discountValue: Double? = nil
    }

    struct FlightItem: Codable {
        var airline: String
        var flightNumber: String
        var fromCode: String
        var toCode: String
        var departure: Date
        var arrival: Date
        var fromTerminal: String
        var toTerminal: String
        var seat: String
        var bookingReference: String
        var bookingSite: String
        var baggage: String
        var notes: String
        var price: Double
        var currency: String
        var rateToMYR: Double
        var paidOn: Date?
        var remindersOn: Bool
        // Optional so files from older versions still open.
        var passengers: Int?
        var paidPortions: Int?
        var passengersPaidFor: [GuestItem]?
    }

    struct HotelItem: Codable {
        var name: String
        var address: String
        var latitude: Double?
        var longitude: Double?
        var checkIn: Date
        var checkOut: Date
        var price: Double
        var currency: String
        var rateToMYR: Double
        var confirmationNumber: String
        var bookingSite: String
        var phone: String
        var notes: String
        var paidOn: Date?
        var guests: Int
        var paidPortions: Int
        /// Other guests you paid for, in order, with whether they've paid you back.
        var guestsPaidFor: [GuestItem]
    }

    struct GuestItem: Codable {
        var name: String
        var isRepaid: Bool
        var repaidAt: Date?
    }

    enum TransferError: LocalizedError {
        case notTriply
        var errorDescription: String? { "This file isn't a Triply itinerary or expenses export." }
    }

    // MARK: - Export

    static func export(_ kind: Kind, of trip: Trip) throws -> Data {
        var contents = FileContents(kind: kind, exportedAt: .now, trip: TripInfo(
            name: trip.name, destination: trip.destination, startDate: trip.startDate, endDate: trip.endDate,
            isDraft: trip.isDraft, draftDays: trip.draftDays, localCurrency: trip.localCurrency, budget: trip.budget))

        switch kind {
        case .itinerary:
            // Days in route order, then saved ideas as listed in the app (newest first).
            let dayPlaces = trip.places.filter { $0.dayIndex != nil }
                .sorted { ($0.dayIndex ?? 0, $0.order) < ($1.dayIndex ?? 0, $1.order) }
            contents.places = (dayPlaces + trip.ideas)
                .map { place in
                    PlaceItem(name: place.name, address: place.address, latitude: place.latitude, longitude: place.longitude,
                              hasLocation: place.hasLocation, dayIndex: place.dayIndex, order: place.order, time: place.time,
                              notes: place.notes, isDone: place.isDone,
                              links: place.links.sorted { $0.createdAt < $1.createdAt }.map { LinkItem(url: $0.urlString, note: $0.note) })
                }
        case .expenses:
            // Hotel and flight costs are rebuilt from their bookings on import, so only your own expenses are listed.
            contents.expenses = trip.expenses
                .filter { $0.hotel == nil && $0.guestOfHotel == nil && $0.flight == nil && $0.passengerOfFlight == nil
                    && $0.ticket == nil && $0.guestOfTicket == nil }
                .sorted { $0.date < $1.date }
                .map { e in
                    ExpenseItem(title: e.title, amount: e.amount, currency: e.currency, rateToMYR: e.rateToMYR,
                                category: e.categoryRaw, date: e.date, notes: e.notes, sharedBy: e.sharedBy,
                                paidPortions: e.paidPortions, splitMode: e.splitModeRaw, myShareValue: e.myShareValue,
                                paidForName: e.paidForName, isRepaid: e.isRepaid, repaidAt: e.repaidAt,
                                taxRefundType: e.taxRefundType, taxRefundValue: e.taxRefundValue,
                                items: e.lineItems.isEmpty ? nil : e.lineItems,
                                discountType: e.discountType, discountValue: e.hasDiscount ? e.discountValue : nil)
                }
            contents.flights = trip.flights.sorted { $0.departure < $1.departure }.map { f in
                FlightItem(airline: f.airline, flightNumber: f.flightNumber, fromCode: f.fromCode, toCode: f.toCode,
                           departure: f.departure, arrival: f.arrival, fromTerminal: f.fromTerminal, toTerminal: f.toTerminal,
                           seat: f.seat, bookingReference: f.bookingReference, bookingSite: f.bookingSite, baggage: f.baggage,
                           notes: f.notes, price: f.price, currency: f.currency, rateToMYR: f.rateToMYR,
                           paidOn: f.paidOn, remindersOn: f.remindersOn,
                           passengers: f.passengers, paidPortions: f.paidPortions,
                           passengersPaidFor: f.sortedPassengerExpenses.map {
                               GuestItem(name: $0.paidForName ?? "", isRepaid: $0.isRepaid, repaidAt: $0.repaidAt)
                           })
            }
            contents.tickets = trip.sortedTickets.map { t in
                TicketItem(name: t.name, venue: t.venue, startsAt: t.startsAt, hasTime: t.hasTime,
                           bookingReference: t.bookingReference, bookingSite: t.bookingSite, seat: t.seat, notes: t.notes,
                           price: t.price, currency: t.currency, rateToMYR: t.rateToMYR, paidOn: t.paidOn,
                           people: t.people, paidPortions: t.paidPortions,
                           guestsPaidFor: t.sortedGuestExpenses.map {
                               GuestItem(name: $0.paidForName ?? "", isRepaid: $0.isRepaid, repaidAt: $0.repaidAt)
                           },
                           placeName: t.place?.name)
            }
            contents.hotels = trip.hotels.sorted { $0.checkIn < $1.checkIn }.map { h in
                HotelItem(name: h.name, address: h.address, latitude: h.latitude, longitude: h.longitude,
                          checkIn: h.checkIn, checkOut: h.checkOut, price: h.price, currency: h.currency,
                          rateToMYR: h.rateToMYR, confirmationNumber: h.confirmationNumber, bookingSite: h.bookingSite,
                          phone: h.phone, notes: h.notes, paidOn: h.paidOn, guests: h.guests, paidPortions: h.paidPortions,
                          guestsPaidFor: h.sortedGuestExpenses.map {
                              GuestItem(name: $0.paidForName ?? "", isRepaid: $0.isRepaid, repaidAt: $0.repaidAt)
                          })
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(contents)
    }

    /// e.g. "Tokyo Winter - Itinerary".
    static func fileName(_ kind: Kind, of trip: Trip) -> String {
        let safe = trip.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return "\(safe.isEmpty ? "Trip" : safe) - \(kind.title)"
    }

    // MARK: - Import

    static func read(_ data: Data) throws -> FileContents {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(FileContents.self, from: data), contents.format == "tripple" else {
            throw TransferError.notTriply
        }
        return contents
    }

    /// What the file will add, e.g. "8 places" or "12 expenses, 2 flights and 1 hotel".
    static func summary(of contents: FileContents) -> String {
        func count(_ n: Int, _ word: String) -> String? { n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")" }
        let parts = [
            count(contents.places?.count ?? 0, "place"),
            count(contents.expenses?.count ?? 0, "expense"),
            count(contents.flights?.count ?? 0, "flight"),
            count(contents.hotels?.count ?? 0, "hotel"),
            count(contents.tickets?.count ?? 0, "ticket"),
        ].compactMap { $0 }
        guard !parts.isEmpty else { return "nothing" }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }

    /// Adds everything in the file to `trip` (nothing already in the trip is changed or removed).
    @MainActor
    static func add(_ contents: FileContents, to trip: Trip, context: ModelContext) {
        // Next free position on each day, so imported stops go after what's already there, in file order.
        var nextOrder: [Int: Int] = [:]
        var ideaCount = 0
        for item in contents.places ?? [] {
            // A day the trip doesn't have (e.g. Day 6 of a 4-day trip) becomes a saved idea.
            let day = item.dayIndex.flatMap { $0 < trip.dayCount ? $0 : nil }
            var order = 0
            if let day {
                order = nextOrder[day] ?? trip.nextOrder(forDay: day)
                nextOrder[day] = order + 1
            }
            let place = Place(name: item.name, address: item.address, latitude: item.latitude, longitude: item.longitude,
                              dayIndex: day, order: order, notes: item.notes)
            if day == nil {
                // Saved ideas are listed newest first: step the times back so the file's order is kept.
                place.createdAt = Date.now.addingTimeInterval(-Double(ideaCount) / 1000)
                ideaCount += 1
            }
            place.hasLocation = item.hasLocation
            place.time = item.time
            place.isDone = item.isDone
            context.insert(place)
            place.trip = trip
            for linkItem in item.links {
                let link = SavedLink(urlString: linkItem.url, note: linkItem.note)
                context.insert(link)
                link.place = place
            }
        }

        for item in contents.expenses ?? [] {
            let expense = Expense(title: item.title, amount: item.amount, currency: item.currency, rateToMYR: item.rateToMYR,
                                  category: ExpenseCategory(rawValue: item.category) ?? .other, date: item.date, notes: item.notes)
            expense.sharedBy = item.sharedBy
            expense.paidPortions = item.paidPortions
            expense.splitModeRaw = item.splitMode
            expense.myShareValue = item.myShareValue
            expense.paidForName = item.paidForName
            expense.isRepaid = item.isRepaid
            expense.repaidAt = item.repaidAt
            expense.taxRefundType = item.taxRefundType
            expense.taxRefundValue = item.taxRefundValue
            expense.discountType = item.discountType
            expense.discountValue = item.discountValue ?? 0
            expense.lineItems = item.items ?? []
            context.insert(expense)
            expense.trip = trip
        }

        for item in contents.flights ?? [] {
            let flight = Flight(airline: item.airline, flightNumber: item.flightNumber, fromCode: item.fromCode,
                                toCode: item.toCode, departure: item.departure, arrival: item.arrival)
            flight.fromTerminal = item.fromTerminal
            flight.toTerminal = item.toTerminal
            flight.seat = item.seat
            flight.bookingReference = item.bookingReference
            flight.bookingSite = item.bookingSite
            flight.baggage = item.baggage
            flight.notes = item.notes
            flight.price = item.price
            flight.currency = item.currency
            flight.rateToMYR = item.rateToMYR
            flight.paidOn = item.paidOn
            flight.remindersOn = item.remindersOn
            flight.passengers = item.passengers ?? 1
            flight.paidPortions = item.paidPortions ?? 1
            context.insert(flight)
            flight.trip = trip
            // Creates the flight's expense and one "owes you" row per passenger you paid for.
            flight.syncExpense(in: context)
            for (passenger, saved) in zip(flight.sortedPassengerExpenses, item.passengersPaidFor ?? []) {
                passenger.paidForName = saved.name
                passenger.isRepaid = saved.isRepaid
                passenger.repaidAt = saved.repaidAt
            }
        }

        for item in contents.hotels ?? [] {
            let hotel = Hotel(name: item.name, checkIn: item.checkIn, checkOut: item.checkOut)
            hotel.address = item.address
            hotel.latitude = item.latitude
            hotel.longitude = item.longitude
            hotel.price = item.price
            hotel.currency = item.currency
            hotel.rateToMYR = item.rateToMYR
            hotel.confirmationNumber = item.confirmationNumber
            hotel.bookingSite = item.bookingSite
            hotel.phone = item.phone
            hotel.notes = item.notes
            hotel.paidOn = item.paidOn
            hotel.guests = item.guests
            hotel.paidPortions = item.paidPortions
            context.insert(hotel)
            hotel.trip = trip
            // Creates the hotel's expense and one "owes you" row per guest you paid for.
            hotel.syncExpense(in: context)
            for (guest, saved) in zip(hotel.sortedGuestExpenses, item.guestsPaidFor) {
                guest.paidForName = saved.name
                guest.isRepaid = saved.isRepaid
                guest.repaidAt = saved.repaidAt
            }
        }

        for item in contents.tickets ?? [] {
            let ticket = Ticket(name: item.name, startsAt: item.startsAt)
            ticket.venue = item.venue
            ticket.hasTime = item.hasTime
            ticket.bookingReference = item.bookingReference
            ticket.bookingSite = item.bookingSite
            ticket.seat = item.seat
            ticket.notes = item.notes
            ticket.price = item.price
            ticket.currency = item.currency
            ticket.rateToMYR = item.rateToMYR
            ticket.paidOn = item.paidOn
            ticket.people = item.people
            ticket.paidPortions = item.paidPortions
            context.insert(ticket)
            ticket.trip = trip
            if let placeName = item.placeName {
                ticket.place = trip.places.first { $0.name == placeName }
            }
            ticket.syncExpense(in: context)
            for (guest, saved) in zip(ticket.sortedGuestExpenses, item.guestsPaidFor) {
                guest.paidForName = saved.name
                guest.isRepaid = saved.isRepaid
                guest.repaidAt = saved.repaidAt
            }
        }

        try? context.save()
        if !(contents.flights ?? []).isEmpty {
            Task { await FlightReminders.sync(in: context) }
        }
    }
}

/// The exported JSON, handed to the system's "Save to Files" sheet.
struct TripExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
