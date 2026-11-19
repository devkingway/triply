import Foundation
import SwiftData
import CoreLocation
import SwiftUI

@Model
final class Trip {
    var name: String
    /// One or more places, joined with " · " (e.g. "Tokyo, Japan · Osaka, Japan"). Use `destinations` to read or set them.
    var destination: String
    var startDate: Date
    var endDate: Date
    /// Total budget in the home currency (MYR).
    var budget: Double
    var createdAt: Date

    /// Currency used at the destination (e.g. JPY); new expenses default to it.
    var localCurrency: String = "MYR"

    /// Optional cover photo chosen by the user; otherwise a map of the destination is shown.
    @Attribute(.externalStorage) var coverImage: Data? = nil

    /// A draft trip has no fixed dates yet, just a number of days. Confirm it later to set real dates.
    var isDraft: Bool = false
    /// Number of days planned while the trip is a draft.
    var draftDays: Int = 3
    /// The iCloud Shared Album linked to this trip (Photos' local identifier), shown on the More tab.
    var sharedAlbumID: String? = nil
    /// Its name when it was linked, shown even before Photos access is checked.
    var sharedAlbumTitle: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \Place.trip)
    var places: [Place] = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.trip)
    var expenses: [Expense] = []

    @Relationship(deleteRule: .cascade, inverse: \Hotel.trip)
    var hotels: [Hotel] = []

    var sortedHotels: [Hotel] { hotels.sorted { $0.checkIn < $1.checkIn } }

    @Relationship(deleteRule: .cascade, inverse: \Flight.trip)
    var flights: [Flight] = []

    var sortedFlights: [Flight] { flights.sorted { $0.departure < $1.departure } }

    @Relationship(deleteRule: .cascade, inverse: \Ticket.trip)
    var tickets: [Ticket] = []

    var sortedTickets: [Ticket] { tickets.sorted { $0.startsAt < $1.startsAt } }

    static let destinationSeparator = " · "

    /// The places this trip goes to, in order.
    var destinations: [String] {
        get {
            destination.components(separatedBy: Self.destinationSeparator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            destination = newValue
                .map { $0.replacingOccurrences(of: Self.destinationSeparator, with: ", ").trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: Self.destinationSeparator)
        }
    }

    /// The first destination, used to find the area on the map.
    var mainDestination: String { destinations.first ?? "" }

    @Relationship(deleteRule: .cascade, inverse: \PackingItem.trip)
    var packingItems: [PackingItem] = []

    var packedCount: Int { packingItems.filter(\.isPacked).count }

    /// Whole days until the trip starts (0 on the day, negative once it has started).
    var daysUntilDeparture: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: startDate)).day ?? 0
    }

    /// Flights that depart or arrive (in local airport time) on this trip day.
    func flights(onDay day: Int) -> [Flight] {
        guard !isDraft else { return [] }   // no real dates yet
        let target = Calendar.current.dateComponents([.year, .month, .day], from: date(forDay: day))
        func matches(_ date: Date, _ tz: TimeZone) -> Bool {
            var cal = Calendar.current
            cal.timeZone = tz
            return cal.dateComponents([.year, .month, .day], from: date) == target
        }
        return sortedFlights.filter { matches($0.departure, $0.fromTimeZone) || matches($0.arrival, $0.toTimeZone) }
    }

    /// The hotel booked for the night that starts on this trip day.
    func hotel(forNight day: Int) -> Hotel? {
        guard !isDraft else { return nil }  // no real dates yet
        let cal = Calendar.current
        let night = cal.startOfDay(for: date(forDay: day))
        return sortedHotels.first {
            cal.startOfDay(for: $0.checkIn) <= night && night < cal.startOfDay(for: $0.checkOut)
        }
    }

    /// A flight that lands on this trip day at the destination (not the flight home).
    func arrivingFlight(onDay day: Int) -> Flight? {
        guard !isDraft else { return nil }
        let target = Calendar.current.dateComponents([.year, .month, .day], from: date(forDay: day))
        // The first flight's departure airport is home; landing back there is the end of the trip.
        let home = sortedFlights.first?.fromCode
        return sortedFlights.last { flight in
            var cal = Calendar.current
            cal.timeZone = flight.toTimeZone
            return flight.toCode != home && cal.dateComponents([.year, .month, .day], from: flight.arrival) == target
        }
    }

    /// The hotel you check in to on this trip day, if any.
    func checkInHotel(onDay day: Int) -> Hotel? {
        guard !isDraft else { return nil }
        let date = date(forDay: day)
        return sortedHotels.first { Calendar.current.isDate($0.checkIn, inSameDayAs: date) }
    }

    /// Where the day starts: last night's hotel (or tonight's on arrival day).
    func startHotel(forDay day: Int) -> Hotel? {
        (day > 0 ? hotel(forNight: day - 1) : nil) ?? hotel(forNight: day)
    }

    /// Where the day ends: tonight's hotel (or last night's on departure day).
    func endHotel(forDay day: Int) -> Hotel? {
        hotel(forNight: day) ?? (day > 0 ? hotel(forNight: day - 1) : nil)
    }

    /// Trip nights (every day except the last) with no hotel booked.
    var nightsWithoutHotel: [Int] {
        (0..<max(dayCount - 1, 0)).filter { hotel(forNight: $0) == nil }
    }

    init(name: String, destination: String, startDate: Date, endDate: Date, budget: Double, localCurrency: String = "MYR") {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.budget = budget
        self.localCurrency = localCurrency
        self.createdAt = .now
    }

    /// Expenses that count as your spending: your own, plus friends' items not yet paid back.
    var myExpenses: [Expense] { expenses.filter(\.countsAsMySpending) }
    /// Items you paid for on behalf of someone else.
    var friendExpenses: [Expense] { expenses.filter(\.isForSomeoneElse) }

    var totalSpent: Double { myExpenses.reduce(0) { $0 + $1.amountMYR } }
    /// Money coming back from tax refunds (e.g. tax-free shopping), in MYR.
    var totalTaxRefund: Double { myExpenses.reduce(0) { $0 + $1.taxRefundMYR } }
    /// Total bought for friends, in MYR (not part of your spending).
    var totalForFriends: Double { friendExpenses.reduce(0) { $0 + $1.amountMYR } }
    /// What friends still owe you (items not yet marked as paid back).
    var owedToYou: Double { friendExpenses.filter { !$0.isRepaid }.reduce(0) { $0 + $1.amountMYR } }
    /// What the trip really costs after tax refunds.
    var netSpent: Double { totalSpent - totalTaxRefund }
    /// Budget left, counting tax refunds as money back.
    var remaining: Double { budget - netSpent }

    var dayCount: Int {
        if isDraft { return max(1, draftDays) }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: endDate)).day ?? 0
        return max(1, days + 1)
    }

    func date(forDay index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: startDate) ?? startDate
    }

    func dayTitle(_ index: Int) -> String {
        if isDraft { return "Day \(index + 1)" }
        return "Day \(index + 1) · \(date(forDay: index).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    /// Places planned for a day, in visiting order.
    func places(onDay index: Int) -> [Place] {
        places.filter { $0.dayIndex == index }.sorted { $0.order < $1.order }
    }

    /// Places saved for later, not yet scheduled on a day.
    var ideas: [Place] {
        places.filter { $0.dayIndex == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    func nextOrder(forDay index: Int?) -> Int {
        guard let index else { return 0 }
        return (places(onDay: index).map(\.order).max() ?? -1) + 1
    }

    var dateRangeText: String {
        if isDraft { return "Dates not set · \(dayCount) day\(dayCount == 1 ? "" : "s")" }
        return "\(startDate.formatted(.dateTime.day().month(.abbreviated))) – \(endDate.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}

@Model
final class Place {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    /// 0-based day of the trip; `nil` means it's a saved idea not yet scheduled.
    var dayIndex: Int?
    var order: Int
    var time: Date?
    var notes: String
    var createdAt: Date
    /// Ticked off on the day (Done button, or left the place with auto-arrive on).
    var isDone: Bool = false
    /// `false` for a place saved by name only (e.g. from a shared post); maps and routes skip it until a location is set.
    var hasLocation: Bool = true
    /// `nil` = in Saved places (shared to "All"), not in a trip yet.
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \SavedLink.place)
    var links: [SavedLink] = []

    /// Tickets booked for this place (e.g. Skytree entry). Deleting the place keeps the tickets.
    @Relationship(deleteRule: .nullify, inverse: \Ticket.place)
    var tickets: [Ticket] = []

    var sortedTickets: [Ticket] { tickets.sorted { $0.startsAt < $1.startsAt } }

    init(name: String, address: String, latitude: Double, longitude: Double, dayIndex: Int?, order: Int, notes: String = "") {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.dayIndex = dayIndex
        self.order = order
        self.notes = notes
        self.createdAt = .now
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Puts this place into a trip's saved ideas (from Saved places or another trip).
    func move(to trip: Trip) {
        dayIndex = nil
        order = trip.nextOrder(forDay: nil)
        time = nil
        self.trip = trip
    }

    var sortedLinks: [SavedLink] {
        links.sorted { $0.createdAt > $1.createdAt }
    }
}

@Model
final class SavedLink {
    var urlString: String
    var note: String
    var createdAt: Date
    var place: Place?

    init(urlString: String, note: String = "") {
        self.urlString = urlString
        self.note = note
        self.createdAt = .now
    }

    var url: URL? { URL(string: urlString) }
    var platform: LinkPlatform { LinkPlatform(url: url) }
}

enum LinkPlatform {
    case instagram, facebook, tiktok, xiaohongshu, youtube, web

    init(url: URL?) {
        let host = url?.host()?.lowercased() ?? ""
        if host.contains("instagram") { self = .instagram }
        else if host.contains("facebook") || host == "fb.com" || host.hasSuffix("fb.watch") { self = .facebook }
        else if host.contains("tiktok") { self = .tiktok }
        else if host.contains("xiaohongshu") || host.contains("xhslink") { self = .xiaohongshu }
        else if host.contains("youtube") || host == "youtu.be" { self = .youtube }
        else { self = .web }
    }

    var name: String {
        switch self {
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .tiktok: "TikTok"
        case .xiaohongshu: "Xiaohongshu"
        case .youtube: "YouTube"
        case .web: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .instagram: "camera.fill"
        case .facebook: "person.2.fill"
        case .tiktok: "music.note"
        case .xiaohongshu: "book.fill"
        case .youtube: "play.rectangle.fill"
        case .web: "link"
        }
    }

    var color: Color {
        switch self {
        case .instagram: .pink
        case .facebook: .blue
        case .tiktok: .black
        case .xiaohongshu: .red
        case .youtube: .red
        case .web: .gray
        }
    }
}

@Model
final class Expense {
    var title: String
    /// Amount in the currency it was paid in.
    var amount: Double
    var currency: String
    /// How many MYR one unit of `currency` was worth when recorded.
    var rateToMYR: Double
    var categoryRaw: String
    var date: Date
    var notes: String
    var createdAt: Date
    var trip: Trip?
    /// Set when this expense was created from a hotel booking.
    var hotel: Hotel?
    /// Set when this is another guest's portion of a hotel room that you paid for.
    var guestOfHotel: Hotel?
    /// When the person paid you back (`nil` = not yet, or recorded before dates were kept).
    var repaidAt: Date? = nil
    /// Set when this expense was created from a flight booking.
    var flight: Flight?
    /// Set when this is another passenger's ticket that you paid for.
    var passengerOfFlight: Flight?
    /// Set when this expense was created from a ticket booking.
    var ticket: Ticket?
    /// Set when this is another person's ticket (attraction, train…) that you paid for.
    var guestOfTicket: Ticket?

    init(title: String, amount: Double, currency: String, rateToMYR: Double, category: ExpenseCategory, date: Date, notes: String = "") {
        self.title = title
        self.amount = amount
        self.currency = currency
        self.rateToMYR = rateToMYR
        self.categoryRaw = category.rawValue
        self.date = date
        self.notes = notes
        self.createdAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// How many people share this bill (1 = not shared).
    var sharedBy: Int = 1
    /// How many of those people's portions you pay for.
    var paidPortions: Int = 1

    /// How the bill is split: equal portions between people, your percentage, or your exact amount.
    var splitModeRaw: String = SplitMode.people.rawValue
    /// Your share for the percent (0–100) and amount (in `currency`) modes.
    var myShareValue: Double = 0

    var splitMode: SplitMode {
        get { SplitMode(rawValue: splitModeRaw) ?? .people }
        set { splitModeRaw = newValue.rawValue }
    }

    /// Portions you pay for, kept between 0 (someone else paid) and the number of people.
    var myPortions: Int { min(max(paidPortions, 0), max(sharedBy, 1)) }
    /// Whether the bill is split and you pay only part of it.
    var isSplit: Bool { shareFraction < 1 }
    /// Your part of the bill (1 when not split).
    var shareFraction: Double {
        SplitMode.fraction(mode: splitMode, sharedBy: sharedBy, paidPortions: paidPortions,
                           shareValue: myShareValue, billAmount: netAmount)
    }
    /// e.g. "1 of 3 people", "your 40%" or "your RM 25.00".
    var splitText: String {
        switch splitMode {
        case .people: "\(myPortions) of \(max(sharedBy, 1)) people"
        case .percent: "your \(min(max(myShareValue, 0), 100).formatted(.number.precision(.fractionLength(0...1))))%"
        case .amount: "your \(amountMYR.myr)"
        }
    }

    /// Discount on the whole bill: "percent" or "amount" (`nil` = none). `amount` is the price before it.
    var discountType: String? = nil
    var discountValue: Double = 0
    var hasDiscount: Bool { discountType != nil && discountValue > 0 }
    /// The discount in the expense's currency.
    var discountAmount: Double {
        switch discountType {
        case "percent": amount * min(max(discountValue, 0), 100) / 100
        case "amount": min(max(discountValue, 0), amount)
        default: 0
        }
    }
    /// The bill after discount, in the expense's currency: what was actually paid.
    var netAmount: Double { max(amount - discountAmount, 0) }

    /// The whole bill after discount, in MYR.
    var totalMYR: Double { netAmount * rateToMYR }
    /// What you pay after discount, in the expense's currency.
    var myAmount: Double { netAmount * shareFraction }
    /// What you pay, in MYR. This is what the budget counts.
    var amountMYR: Double { totalMYR * shareFraction }

    /// Set when you bought this for someone else: their name ("" if not named). `nil` = your own expense.
    var paidForName: String? = nil
    /// Whether that person has paid you back.
    var isRepaid: Bool = false

    var isForSomeoneElse: Bool { paidForName != nil }
    /// A friend's item counts as your spending until they pay you back.
    var countsAsMySpending: Bool { !(isForSomeoneElse && isRepaid) }
    var paidForLabel: String {
        guard let paidForName else { return "" }
        guard paidForName.isEmpty else { return paidForName }
        // An unnamed hotel guest: "Guest 2", "Guest 3"… (you're guest 1).
        if let hotel = guestOfHotel,
           let index = hotel.sortedGuestExpenses.firstIndex(where: { $0.persistentModelID == persistentModelID }) {
            return "Guest \(index + 2)"
        }
        // An unnamed passenger: "Passenger 2", "Passenger 3"… (you're passenger 1).
        if let flight = passengerOfFlight,
           let index = flight.sortedPassengerExpenses.firstIndex(where: { $0.persistentModelID == persistentModelID }) {
            return "Passenger \(index + 2)"
        }
        if let ticket = guestOfTicket,
           let index = ticket.sortedGuestExpenses.firstIndex(where: { $0.persistentModelID == persistentModelID }) {
            return "Person \(index + 2)"
        }
        return "Someone else"
    }

    /// Marks it paid back (or not) and records when.
    func setRepaid(_ repaid: Bool) {
        isRepaid = repaid
        repaidAt = repaid ? .now : nil
    }

    /// The hotel this expense belongs to, as your own room cost or another guest's portion.
    var linkedHotel: Hotel? { hotel ?? guestOfHotel }
    /// The flight this expense belongs to, as your own ticket or another passenger's.
    var linkedFlight: Flight? { flight ?? passengerOfFlight }
    /// The ticket booking this expense belongs to, as your own ticket or someone else's.
    var linkedTicket: Ticket? { ticket ?? guestOfTicket }

    /// Receipt lines (e.g. each dish on a bill), for your records only: they never change the
    /// amount, budget or splits. Stored as JSON text so older expenses need no migration.
    var lineItemsJSON: String = ""

    var lineItems: [ExpenseLineItem] {
        get {
            guard !lineItemsJSON.isEmpty, let data = lineItemsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([ExpenseLineItem].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty { lineItemsJSON = ""; return }
            lineItemsJSON = (try? JSONEncoder().encode(newValue)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    /// Optional tax refund on this item: "percent" or "amount" (amount is in the expense's currency). `nil` = none.
    var taxRefundType: String? = nil
    var taxRefundValue: Double = 0

    var hasTaxRefund: Bool { taxRefundType != nil && taxRefundValue > 0 }

    /// Tax refunded on this item, in MYR.
    var taxRefundMYR: Double {
        switch taxRefundType {
        case "percent": amountMYR * min(taxRefundValue, 100) / 100
        case "amount": min(taxRefundValue, netAmount) * rateToMYR * shareFraction
        default: 0
        }
    }

    /// Your part of the discount, in MYR.
    var discountMYR: Double { discountAmount * rateToMYR * shareFraction }
    /// What it really costs you after discount and tax back, in MYR.
    var finalMYR: Double { max(amountMYR - (hasTaxRefund ? taxRefundMYR : 0), 0) }
    /// The same, in the expense's currency.
    var finalAmount: Double { rateToMYR > 0 ? finalMYR / rateToMYR : 0 }
}

@Model
final class Hotel {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var checkIn: Date
    var checkOut: Date
    /// Total price for the stay, in `currency`.
    var price: Double
    var currency: String
    var rateToMYR: Double
    var confirmationNumber: String
    var bookingSite: String
    var phone: String
    var notes: String
    var createdAt: Date
    /// When the booking was paid. `nil` = pay at the hotel (counted on check-in day).
    var paidOn: Date?
    /// How many people stay in the room.
    var guests: Int = 1
    /// How many of those people's portions you pay for (1 = just your own share).
    var paidPortions: Int = 1
    var trip: Trip?

    /// The matching expense in the budget, kept in sync with the price.
    @Relationship(deleteRule: .cascade, inverse: \Expense.hotel)
    var expense: Expense?

    @Relationship(deleteRule: .cascade, inverse: \HotelAttachment.hotel)
    var attachments: [HotelAttachment] = []

    /// One expense per other guest whose portion you paid for ("For Ali · Owes you" in the budget).
    @Relationship(deleteRule: .cascade, inverse: \Expense.guestOfHotel)
    var guestExpenses: [Expense] = []

    init(name: String, checkIn: Date, checkOut: Date) {
        self.name = name
        self.address = ""
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.price = 0
        self.currency = "MYR"
        self.rateToMYR = 1
        self.confirmationNumber = ""
        self.bookingSite = ""
        self.phone = ""
        self.notes = ""
        self.createdAt = .now
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var nights: Int {
        let cal = Calendar.current
        return max(1, cal.dateComponents([.day], from: cal.startOfDay(for: checkIn), to: cal.startOfDay(for: checkOut)).day ?? 1)
    }

    var priceMYR: Double { price * rateToMYR }

    /// Portions you pay for, kept between 0 (someone else paid) and the number of guests.
    var myPortions: Int { min(max(paidPortions, 0), max(guests, 1)) }
    /// Whether you pay only part of the room (sharing the cost with others).
    var isShared: Bool { myPortions < max(guests, 1) }
    /// Your part of the total, in the booking currency.
    var myShare: Double { price * Double(myPortions) / Double(max(guests, 1)) }
    var myShareMYR: Double { myShare * rateToMYR }

    /// One person's portion of the room, in the booking currency.
    var perGuest: Double { price / Double(max(guests, 1)) }
    var perGuestMYR: Double { perGuest * rateToMYR }
    /// Other guests' portions you covered, oldest first.
    var sortedGuestExpenses: [Expense] { guestExpenses.sorted { $0.createdAt < $1.createdAt } }
    var paidBackCount: Int { guestExpenses.filter(\.isRepaid).count }
    /// What the room really costs you after the people you covered paid you back.
    var myCostMYR: Double { myShareMYR - Double(paidBackCount) * perGuestMYR }
    /// True when the guest rows in the budget don't match "I pay for" yet (e.g. older bookings).
    var needsGuestSync: Bool {
        price > 0 && trip != nil && guestExpenses.count != max(myPortions - 1, 0)
    }

    /// e.g. "1 of 2 people", or "2 people" when you pay the whole room.
    var shareText: String {
        let g = max(guests, 1)
        if !isShared { return g == 1 ? "1 person" : "\(g) people" }
        return "\(myPortions) of \(g) people"
    }

    var datesText: String {
        let fmt = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        return "\(checkIn.formatted(fmt)) → \(checkOut.formatted(fmt)) · \(nights) night\(nights == 1 ? "" : "s")"
    }

    var sortedAttachments: [HotelAttachment] { attachments.sorted { $0.createdAt < $1.createdAt } }

    /// Creates, updates or removes the hotel's expense so the budget matches the booking.
    func syncExpense(in context: ModelContext) {
        guard price > 0, let trip else {
            if let expense { context.delete(expense); self.expense = nil }
            for guest in guestExpenses { context.delete(guest) }
            guestExpenses = []
            return
        }
        syncGuestExpenses(trip: trip, in: context)
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense(title: "", amount: 0, currency: currency, rateToMYR: 1, category: .hotel, date: checkIn)
            context.insert(target)
            target.trip = trip
            self.expense = target
        }
        // Just the hotel name; nights and the split show elsewhere on the budget row.
        target.title = name
        // Just your own portion; portions you cover for others are their own "owes you" rows.
        // 0 when someone else paid your portion.
        target.amount = myPortions > 0 ? perGuest : 0
        target.currency = currency
        target.rateToMYR = rateToMYR
        target.category = .hotel
        // Budget counts it on the day the money was paid (often weeks before the trip).
        target.date = paidOn ?? checkIn
    }

    /// Keeps one "owes you" expense per other guest you paid for, keeping names and paid-back ticks.
    private func syncGuestExpenses(trip: Trip, in context: ModelContext) {
        var current = sortedGuestExpenses
        let wanted = max(myPortions - 1, 0)
        // Too many: drop the newest unpaid ones first, so ticked-off names stay.
        while current.count > wanted {
            let drop = current.lastIndex(where: { !$0.isRepaid }) ?? current.count - 1
            context.delete(current.remove(at: drop))
        }
        while current.count < wanted {
            let guest = Expense(title: name, amount: 0, currency: currency, rateToMYR: rateToMYR,
                                category: .hotel, date: paidOn ?? checkIn)
            // Nudge creation times apart so the order stays stable.
            guest.createdAt = Date.now.addingTimeInterval(Double(current.count) / 1000)
            guest.paidForName = ""
            context.insert(guest)
            guest.trip = trip
            current.append(guest)
        }
        for guest in current {
            guest.title = name
            guest.amount = perGuest
            guest.currency = currency
            guest.rateToMYR = rateToMYR
            guest.category = .hotel
            guest.date = paidOn ?? checkIn
            if guest.paidForName == nil { guest.paidForName = "" }
        }
        guestExpenses = current
    }
}

@Model
final class Flight {
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
    /// Total price paid, in `currency`.
    var price: Double
    var currency: String
    var rateToMYR: Double
    var createdAt: Date
    /// When the ticket was paid (counted in the budget on this day). `nil` = departure day.
    var paidOn: Date?
    var trip: Trip?
    /// Send "check-in opens" and "leave for the airport" notifications.
    var remindersOn: Bool = true
    /// How many people the price covers.
    var passengers: Int = 1
    /// How many of those people's tickets you pay for (1 = just your own, 0 = someone else paid).
    var paidPortions: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \Expense.flight)
    var expense: Expense?

    /// One expense per other passenger whose ticket you paid for ("For Ali · Owes you" in the budget).
    @Relationship(deleteRule: .cascade, inverse: \Expense.passengerOfFlight)
    var passengerExpenses: [Expense] = []

    @Relationship(deleteRule: .cascade, inverse: \HotelAttachment.flight)
    var attachments: [HotelAttachment] = []

    init(airline: String, flightNumber: String, fromCode: String, toCode: String, departure: Date, arrival: Date) {
        self.airline = airline
        self.flightNumber = flightNumber
        self.fromCode = fromCode
        self.toCode = toCode
        self.departure = departure
        self.arrival = arrival
        self.fromTerminal = ""
        self.toTerminal = ""
        self.seat = ""
        self.bookingReference = ""
        self.bookingSite = ""
        self.baggage = ""
        self.notes = ""
        self.price = 0
        self.currency = "MYR"
        self.rateToMYR = 1
        self.createdAt = .now
    }

    var fromTimeZone: TimeZone { Airports.timeZone(for: fromCode) }
    var toTimeZone: TimeZone { Airports.timeZone(for: toCode) }
    var fromCity: String { Airports.find(fromCode)?.city ?? fromCode }
    var toCity: String { Airports.find(toCode)?.city ?? toCode }

    var title: String {
        [airline, flightNumber].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var priceMYR: Double { price * rateToMYR }

    /// Tickets you pay for, kept between 0 (someone else paid) and the number of passengers.
    var myPortions: Int { min(max(paidPortions, 0), max(passengers, 1)) }
    /// Whether you pay only part of the price (sharing it with others).
    var isShared: Bool { myPortions < max(passengers, 1) }
    /// Your part of the price, in the booking currency.
    var myShare: Double { price * Double(myPortions) / Double(max(passengers, 1)) }
    var myShareMYR: Double { myShare * rateToMYR }
    /// One passenger's ticket, in the booking currency.
    var perPassenger: Double { price / Double(max(passengers, 1)) }
    var perPassengerMYR: Double { perPassenger * rateToMYR }
    /// Other passengers' tickets you covered, oldest first.
    var sortedPassengerExpenses: [Expense] { passengerExpenses.sorted { $0.createdAt < $1.createdAt } }
    var paidBackCount: Int { passengerExpenses.filter(\.isRepaid).count }
    /// What the flight really costs you after the people you covered paid you back.
    var myCostMYR: Double { myShareMYR - Double(paidBackCount) * perPassengerMYR }
    /// True when the passenger rows in the budget don't match "I pay for" yet.
    var needsPassengerSync: Bool {
        price > 0 && trip != nil && passengerExpenses.count != max(myPortions - 1, 0)
    }
    /// e.g. "1 of 2 people", or "2 people" when you pay for everyone.
    var shareText: String {
        let p = max(passengers, 1)
        if !isShared { return p == 1 ? "1 person" : "\(p) people" }
        return "\(myPortions) of \(p) people"
    }

    var duration: TimeInterval { max(0, arrival.timeIntervalSince(departure)) }

    var durationText: String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// Local time at the departure airport, e.g. "23:30".
    var departureTimeText: String { Self.time(departure, in: fromTimeZone) }
    var arrivalTimeText: String { Self.time(arrival, in: toTimeZone) }
    var departureDateText: String { Self.day(departure, in: fromTimeZone) }
    var arrivalDateText: String { Self.day(arrival, in: toTimeZone) }

    /// How many calendar days later it lands, in local time (e.g. +1 for overnight flights).
    var arrivalDayOffset: Int {
        var depCal = Calendar.current
        depCal.timeZone = fromTimeZone
        var arrCal = Calendar.current
        arrCal.timeZone = toTimeZone
        let d = depCal.dateComponents([.year, .month, .day], from: departure)
        let a = arrCal.dateComponents([.year, .month, .day], from: arrival)
        guard let dDate = Calendar(identifier: .gregorian).date(from: d),
              let aDate = Calendar(identifier: .gregorian).date(from: a) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: dDate, to: aDate).day ?? 0
    }

    var sortedAttachments: [HotelAttachment] { attachments.sorted { $0.createdAt < $1.createdAt } }

    /// Longest wait between two flights that still counts as a transfer (not a stopover trip).
    static let maxLayover: TimeInterval = 24 * 3600

    /// Time on the ground before `next`, when it leaves from the airport this flight lands at
    /// within a day (a transfer). `nil` when the two flights aren't connected.
    func layover(before next: Flight) -> TimeInterval? {
        guard !toCode.isEmpty, next.fromCode == toCode else { return nil }
        let gap = next.departure.timeIntervalSince(arrival)
        return gap >= 0 && gap <= Self.maxLayover ? gap : nil
    }

    /// The flight you transfer to after this one, if any.
    var connectingFlight: Flight? {
        guard let trip else { return nil }
        return trip.sortedFlights.first { $0 !== self && layover(before: $0) != nil }
    }

    /// The flight you transferred from to get on this one, if any.
    var previousLeg: Flight? {
        guard let trip else { return nil }
        return trip.sortedFlights.last { $0 !== self && $0.layover(before: self) != nil }
    }

    /// e.g. "2h 30m".
    static func layoverText(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func time(_ date: Date, in tz: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = tz
        return date.formatted(style)
    }

    static func day(_ date: Date, in tz: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = tz
        return date.formatted(style)
    }

    /// Creates, updates or removes the flight's expense so the budget matches the booking.
    func syncExpense(in context: ModelContext) {
        guard price > 0, let trip else {
            if let expense { context.delete(expense); self.expense = nil }
            for passenger in passengerExpenses { context.delete(passenger) }
            passengerExpenses = []
            return
        }
        syncPassengerExpenses(trip: trip, in: context)
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense(title: "", amount: 0, currency: currency, rateToMYR: 1, category: .flight, date: departure)
            context.insert(target)
            target.trip = trip
            self.expense = target
        }
        let name = title.isEmpty ? "Flight" : title
        target.title = "\(name) \(fromCode) → \(toCode)"
        // Just your own ticket (0 when someone else paid); tickets you cover are their own "owes you" rows.
        target.amount = myPortions > 0 ? perPassenger : 0
        target.currency = currency
        target.rateToMYR = rateToMYR
        target.category = .flight
        // Budget counts it on the day the ticket was paid (usually before the trip).
        target.date = paidOn ?? departure
    }

    /// Keeps one "owes you" expense per other passenger you paid for, keeping names and paid-back ticks.
    private func syncPassengerExpenses(trip: Trip, in context: ModelContext) {
        var current = sortedPassengerExpenses
        let wanted = max(myPortions - 1, 0)
        // Too many: drop the newest unpaid ones first, so ticked-off names stay.
        while current.count > wanted {
            let drop = current.lastIndex(where: { !$0.isRepaid }) ?? current.count - 1
            context.delete(current.remove(at: drop))
        }
        let name = "\(title.isEmpty ? "Flight" : title) \(fromCode) → \(toCode)"
        while current.count < wanted {
            let passenger = Expense(title: name, amount: 0, currency: currency, rateToMYR: rateToMYR,
                                    category: .flight, date: paidOn ?? departure)
            // Nudge creation times apart so the order stays stable.
            passenger.createdAt = Date.now.addingTimeInterval(Double(current.count) / 1000)
            passenger.paidForName = ""
            context.insert(passenger)
            passenger.trip = trip
            current.append(passenger)
        }
        for passenger in current {
            passenger.title = name
            passenger.amount = perPassenger
            passenger.currency = currency
            passenger.rateToMYR = rateToMYR
            passenger.category = .flight
            passenger.date = paidOn ?? departure
            if passenger.paidForName == nil { passenger.paidForName = "" }
        }
        passengerExpenses = current
    }
}

/// A booked ticket: an attraction, show, train or tour, with its time, venue and e-tickets.
@Model
final class Ticket {
    var name: String
    /// Where it is (venue or station), free text; opens in Maps.
    var venue: String = ""
    /// When it starts (or the visit date).
    var startsAt: Date
    /// False when only the date matters (e.g. an all-day pass).
    var hasTime: Bool = true
    var bookingReference: String = ""
    var bookingSite: String = ""
    /// Seat, entry gate, time slot…
    var seat: String = ""
    var notes: String = ""
    /// Total price paid for everyone, in `currency`.
    var price: Double = 0
    var currency: String = "MYR"
    var rateToMYR: Double = 1
    var createdAt: Date
    /// When it was paid (counted in the budget on this day). `nil` = the ticket's day.
    var paidOn: Date?
    /// How many people the price covers, and how many of their tickets you pay for.
    var people: Int = 1
    var paidPortions: Int = 1
    var trip: Trip?
    /// The itinerary place it's for; the ticket shows under that place.
    var place: Place?

    /// The matching expense in the budget (Tickets category), kept in sync with the price.
    @Relationship(deleteRule: .cascade, inverse: \Expense.ticket)
    var expense: Expense?

    /// One expense per other person whose ticket you paid for ("For Ali · Owes you").
    @Relationship(deleteRule: .cascade, inverse: \Expense.guestOfTicket)
    var guestExpenses: [Expense] = []

    @Relationship(deleteRule: .cascade, inverse: \HotelAttachment.ticket)
    var attachments: [HotelAttachment] = []

    init(name: String, startsAt: Date) {
        self.name = name
        self.startsAt = startsAt
        self.createdAt = .now
    }

    var priceMYR: Double { price * rateToMYR }
    /// Tickets you pay for, kept between 0 (someone else paid) and the number of people.
    var myPortions: Int { min(max(paidPortions, 0), max(people, 1)) }
    var isShared: Bool { myPortions < max(people, 1) }
    var myShare: Double { price * Double(myPortions) / Double(max(people, 1)) }
    var myShareMYR: Double { myShare * rateToMYR }
    var perPerson: Double { price / Double(max(people, 1)) }
    var perPersonMYR: Double { perPerson * rateToMYR }
    var sortedGuestExpenses: [Expense] { guestExpenses.sorted { $0.createdAt < $1.createdAt } }
    var paidBackCount: Int { guestExpenses.filter(\.isRepaid).count }
    /// What the tickets really cost you after the people you covered paid you back.
    var myCostMYR: Double { myShareMYR - Double(paidBackCount) * perPersonMYR }
    var needsGuestSync: Bool { price > 0 && trip != nil && guestExpenses.count != max(myPortions - 1, 0) }
    /// e.g. "1 of 3 people", or "2 people" when you pay for everyone.
    var shareText: String {
        let p = max(people, 1)
        if !isShared { return p == 1 ? "1 person" : "\(p) people" }
        return "\(myPortions) of \(p) people"
    }
    var sortedAttachments: [HotelAttachment] { attachments.sorted { $0.createdAt < $1.createdAt } }

    /// e.g. "Wed, Dec 9 · 4:30 PM".
    var whenText: String {
        let day = startsAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return hasTime ? "\(day) · \(startsAt.formatted(date: .omitted, time: .shortened))" : day
    }

    /// Creates, updates or removes the ticket's expense so the budget matches the booking.
    func syncExpense(in context: ModelContext) {
        guard price > 0, let trip else {
            if let expense { context.delete(expense); self.expense = nil }
            for guest in guestExpenses { context.delete(guest) }
            guestExpenses = []
            return
        }
        syncGuestExpenses(trip: trip, in: context)
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense(title: "", amount: 0, currency: currency, rateToMYR: 1, category: .tickets, date: startsAt)
            context.insert(target)
            target.trip = trip
            self.expense = target
        }
        target.title = name
        // Just your own ticket (0 when someone else paid); tickets you cover are their own "owes you" rows.
        target.amount = myPortions > 0 ? perPerson : 0
        target.currency = currency
        target.rateToMYR = rateToMYR
        target.category = .tickets
        target.date = paidOn ?? startsAt
    }

    private func syncGuestExpenses(trip: Trip, in context: ModelContext) {
        var current = sortedGuestExpenses
        let wanted = max(myPortions - 1, 0)
        // Too many: drop the newest unpaid ones first, so ticked-off names stay.
        while current.count > wanted {
            let drop = current.lastIndex(where: { !$0.isRepaid }) ?? current.count - 1
            context.delete(current.remove(at: drop))
        }
        while current.count < wanted {
            let guest = Expense(title: name, amount: 0, currency: currency, rateToMYR: rateToMYR,
                                category: .tickets, date: paidOn ?? startsAt)
            guest.createdAt = Date.now.addingTimeInterval(Double(current.count) / 1000)
            guest.paidForName = ""
            context.insert(guest)
            guest.trip = trip
            current.append(guest)
        }
        for guest in current {
            guest.title = name
            guest.amount = perPerson
            guest.currency = currency
            guest.rateToMYR = rateToMYR
            guest.category = .tickets
            guest.date = paidOn ?? startsAt
            if guest.paidForName == nil { guest.paidForName = "" }
        }
        guestExpenses = current
    }
}

/// A saved file (screenshot or PDF) for a hotel or flight booking.
@Model
final class HotelAttachment {
    @Attribute(.externalStorage) var data: Data
    var fileName: String
    var isPDF: Bool
    var createdAt: Date
    var hotel: Hotel?
    var flight: Flight?
    var ticket: Ticket?

    init(data: Data, fileName: String, isPDF: Bool) {
        self.data = data
        self.fileName = fileName
        self.isPDF = isPDF
        self.createdAt = .now
    }

    /// Writes the file to a temporary location so it can be previewed or shared.
    func temporaryURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// One line on a receipt, in the expense's currency. Recorded only, so you can check it against the bill.
/// How an item's discount and tax deduction are worked out. Each is per item, then × quantity.
enum LineItemFormula: Int, CaseIterable, Identifiable {
    /// (Price − price×discount − price×tax deduction) × quantity: both worked on the original price.
    case bothFromPrice = 1
    /// (Price − tax deduction − discount) × quantity: the discount % is worked on the price after tax deduction.
    case taxFirst = 2
    /// (Price − discount − tax deduction) × quantity: the tax deduction % is worked on the price after discount.
    case discountFirst = 3
    /// The price already includes tax (e.g. Japan's 10%): a % tax deduction is the tax inside the price after discount,
    /// price × rate ÷ (100 + rate), so ¥1,100 at 10% has ¥100 tax.
    case taxIncluded = 4

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .bothFromPrice: "Formula 1 · Both from price"
        case .taxFirst: "Formula 2 · Tax deduction first"
        case .discountFirst: "Formula 3 · Discount first"
        case .taxIncluded: "Formula 4 · Tax included"
        }
    }
    var explanation: String {
        switch self {
        case .bothFromPrice: "(Price − discount − tax deduction) × quantity. A % discount and a % tax deduction are both worked on the original price."
        case .taxFirst: "(Price − tax deduction − discount) × quantity. The tax deduction comes off first; a % discount is worked on the price after tax deduction."
        case .discountFirst: "(Price − discount − tax deduction) × quantity. The discount comes off first; a % tax deduction is worked on the price after discount."
        case .taxIncluded: "(Price − discount − tax inside the price) × quantity. For prices that already include tax, like Japan's 10%: a % tax deduction is price after discount × rate ÷ (100 + rate), so ¥1,100 at 10% has ¥100 tax."
        }
    }
}

struct ExpenseLineItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    /// Price before tax and discount.
    var amount: Double = 0
    var tax: Double = 0
    var discount: Double = 0
    /// The item's currency; `nil` = same as the expense.
    var currency: String? = nil
    /// MYR per unit of `currency`, saved when the currency was picked (unused when it's the expense's currency).
    var rateToMYR: Double? = nil

    /// `true` = `tax` is a percentage; otherwise an amount. (Optional so older saved items read as amounts.)
    var taxIsPercent: Bool? = nil
    /// `true` = `discount` is a percentage of the amount; otherwise an amount.
    var discountIsPercent: Bool? = nil

    /// How many of this item (`nil` in older saved items = 1). `amount` is the price of one.
    var quantity: Int? = nil

    /// Which order the discount and tax deduction come off (`nil` in older saved items = discount first).
    var formulaRaw: Int? = nil
    var formula: LineItemFormula {
        get { formulaRaw.flatMap(LineItemFormula.init(rawValue:)) ?? .discountFirst }
        set { formulaRaw = newValue.rawValue }
    }

    // Tax charged on the item, as printed on the receipt. Recorded only: it never changes the item total,
    // the expense or the budget. (All optional so older saved items read as "no tax".)
    var chargedTaxKindRaw: String? = nil
    /// The rate (%) or, when `chargedTaxIsPercent` is false, the tax on one item.
    var chargedTax: Double? = nil
    var chargedTaxIsPercent: Bool? = nil
    /// `true` (default) = the price already includes the tax; `false` = tax is added on top.
    var chargedTaxIncluded: Bool? = nil

    var chargedTaxKind: ItemTaxKind {
        get { chargedTaxKindRaw.flatMap(ItemTaxKind.init(rawValue:)) ?? .none }
        set { chargedTaxKindRaw = newValue == .none ? nil : newValue.rawValue }
    }

    /// Tax charged on all of them (after discount), in the item's currency.
    var chargedTaxValue: Double {
        guard chargedTaxKind.isCharged, let value = chargedTax, value > 0 else { return 0 }
        if chargedTaxIsPercent == false { return value * Double(count) }
        let base = subtotal - discountValue
        guard base > 0 else { return 0 }
        return chargedTaxIncluded == false ? base * value / 100 : base * value / (100 + value)
    }

    /// e.g. "10%" or "¥100 each"; `nil` when no tax is charged.
    func chargedTaxRateText(bill: String) -> String? {
        guard chargedTaxKind.isCharged, let value = chargedTax, value > 0 else { return nil }
        return chargedTaxIsPercent == false
            ? "\(value.money(currencyCode(bill: bill))) each"
            : "\(value.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    /// The tax charged converted into the bill's currency (for the receipt's tax summary).
    func chargedTaxInBill(currency bill: String, rate billRate: Double) -> Double {
        inBill(chargedTaxValue, currency: bill, rate: billRate)
    }

    var count: Int { max(quantity ?? 1, 1) }
    /// Price × quantity.
    var subtotal: Double { amount * Double(count) }

    /// Discount and tax deduction for one item, worked out with the chosen formula.
    private var perItem: (discount: Double, tax: Double) {
        let d = min(max(discount, 0), 100) / 100
        let t = max(tax, 0) / 100
        func discountOff(_ base: Double) -> Double { discountIsPercent == true ? base * d : discount }
        func taxOff(_ base: Double) -> Double { taxIsPercent == true ? base * t : tax }
        switch formula {
        case .bothFromPrice:
            return (discountOff(amount), taxOff(amount))
        case .taxFirst:
            let taxValue = taxOff(amount)
            return (discountOff(amount - taxValue), taxValue)
        case .discountFirst:
            let discountValue = discountOff(amount)
            return (discountValue, taxOff(amount - discountValue))
        case .taxIncluded:
            let discountValue = discountOff(amount)
            let base = amount - discountValue
            let included = taxIsPercent == true ? base * max(tax, 0) / (100 + max(tax, 0)) : tax
            return (discountValue, included)
        }
    }

    /// The discount in money for all of them (per item × quantity).
    var discountValue: Double { perItem.discount * Double(count) }
    /// The tax deduction in money for all of them (per item × quantity).
    var taxValue: Double { perItem.tax * Double(count) }

    /// Price × quantity − discount − tax deduction, in the item's currency.
    var total: Double { subtotal - discountValue - taxValue }

    /// The item's currency, falling back to the bill's.
    func currencyCode(bill: String) -> String { currency ?? bill }

    /// The item's total converted into the bill's currency (for checking it against the bill).
    func totalInBill(currency bill: String, rate billRate: Double) -> Double {
        inBill(total, currency: bill, rate: billRate)
    }

    /// Price × quantity − discount: what's paid at the till, before the tax deduction comes back.
    var beforeTax: Double { subtotal - discountValue }

    /// `beforeTax` converted into the bill's currency (to fill in or check the expense amount).
    func beforeTaxInBill(currency bill: String, rate billRate: Double) -> Double {
        inBill(beforeTax, currency: bill, rate: billRate)
    }

    /// The item's tax deduction converted into the bill's currency (to fill in the tax refund).
    func taxInBill(currency bill: String, rate billRate: Double) -> Double {
        inBill(taxValue, currency: bill, rate: billRate)
    }

    /// The item's discount in the bill's currency.
    func discountInBill(currency bill: String, rate billRate: Double) -> Double {
        inBill(discountValue, currency: bill, rate: billRate)
    }

    private func inBill(_ value: Double, currency bill: String, rate billRate: Double) -> Double {
        let code = currencyCode(bill: bill)
        guard code != bill, let rate = rateToMYR, rate > 0, billRate > 0 else { return value }
        return value * rate / billRate
    }
}

/// How an item on a receipt is taxed (e.g. Japan: 10% standard, 8% reduced for food).
enum ItemTaxKind: String, CaseIterable, Identifiable {
    case none, standard, reduced, taxFree, exempt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Not recorded"
        case .standard: "Standard rate"
        case .reduced: "Reduced rate"
        case .taxFree: "Tax-free"
        case .exempt: "Exempt"
        }
    }

    /// Whether a tax amount is charged (and a rate can be entered).
    var isCharged: Bool { self == .standard || self == .reduced }

    /// The usual rate for this kind in a currency's country, to fill in when it's picked.
    func usualRate(for currency: String) -> Double? {
        let rates: (standard: Double, reduced: Double?) = switch currency {
        case "JPY": (10, 8)
        case "MYR": (8, 6)
        case "SGD": (9, nil)
        case "THB": (7, nil)
        case "KRW": (10, nil)
        case "TWD": (5, nil)
        case "IDR": (12, 11)
        case "VND": (10, 8)
        case "CNY": (13, 9)
        case "AUD": (10, nil)
        case "NZD": (15, nil)
        case "EUR": (20, 10)
        case "GBP": (20, 5)
        case "CHF": (8.1, 2.6)
        default: (10, nil)
        }
        switch self {
        case .standard: return rates.standard
        case .reduced: return rates.reduced
        default: return nil
        }
    }
}

/// Ways to split a shared bill.
enum SplitMode: String, CaseIterable, Identifiable {
    /// Equal portions: N people, you pay for some of them.
    case people
    /// You pay a percentage of the bill.
    case percent
    /// You pay an exact amount (for bills that don't divide evenly).
    case amount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .people: "Equally"
        case .percent: "Percent"
        case .amount: "Amount"
        }
    }

    /// Your part of the bill as a fraction (0…1), shared by the expense model and its form.
    static func fraction(mode: SplitMode, sharedBy: Int, paidPortions: Int, shareValue: Double, billAmount: Double) -> Double {
        switch mode {
        case .people:
            let people = max(sharedBy, 1)
            return Double(min(max(paidPortions, 0), people)) / Double(people)
        case .percent:
            return min(max(shareValue, 0), 100) / 100
        case .amount:
            guard billAmount > 0 else { return 1 }
            return min(max(shareValue, 0), billAmount) / billAmount
        }
    }
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case flight, hotel, food, transport, tickets, shopping, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .flight: "Flights"
        case .food: "Food"
        case .transport: "Transport"
        case .hotel: "Hotel"
        case .tickets: "Tickets"
        case .shopping: "Shopping"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .flight: "airplane"
        case .food: "fork.knife"
        case .transport: "tram.fill"
        case .hotel: "bed.double.fill"
        case .tickets: "ticket.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .flight: .indigo
        case .food: .orange
        case .transport: .blue
        case .hotel: .purple
        case .tickets: .pink
        case .shopping: .green
        case .other: .gray
        }
    }
}

extension Double {
    /// Formats a value in any currency, e.g. ¥1,200 or RM 35.00.
    func money(_ code: String) -> String { formatted(.currency(code: code)) }

    /// Formats a value in the home currency, Malaysian Ringgit.
    var myr: String { formatted(.currency(code: "MYR")) }
}


/// One thing to pack before departure, in a group such as Documents or Clothes.
@Model
final class PackingItem {
    var name: String = ""
    var category: String = PackingCategory.other.rawValue
    var isPacked: Bool = false
    /// How many to bring (1 hides the count).
    var quantity: Int = 1
    var order: Int = 0
    var createdAt: Date = Date.now
    var trip: Trip?

    init(name: String, category: PackingCategory, quantity: Int = 1, order: Int = 0) {
        self.name = name
        self.category = category.rawValue
        self.quantity = quantity
        self.order = order
        self.createdAt = .now
    }

    var packingCategory: PackingCategory {
        get { PackingCategory(rawValue: category) ?? .other }
        set { category = newValue.rawValue }
    }
}

enum PackingCategory: String, CaseIterable, Identifiable, Codable {
    case documents = "Documents"
    case money = "Money & cards"
    case clothes = "Clothes"
    case toiletries = "Toiletries"
    case electronics = "Electronics"
    case health = "Health"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .documents: "doc.text.fill"
        case .money: "creditcard.fill"
        case .clothes: "tshirt.fill"
        case .toiletries: "drop.fill"
        case .electronics: "bolt.fill"
        case .health: "cross.case.fill"
        case .other: "bag.fill"
        }
    }

    /// A starter list for a new trip.
    var starterItems: [String] {
        switch self {
        case .documents: ["Passport", "Flight tickets", "Hotel bookings", "Travel insurance", "Visa (if needed)"]
        case .money: ["Cash in local currency", "Credit / debit card", "Travel card"]
        case .clothes: ["T-shirts", "Pants / shorts", "Underwear", "Socks", "Pyjamas", "Jacket", "Comfortable shoes"]
        case .toiletries: ["Toothbrush & toothpaste", "Skincare", "Sunscreen", "Deodorant"]
        case .electronics: ["Phone charger", "Power bank", "Travel adapter", "eSIM / SIM card", "Earphones"]
        case .health: ["Medicine", "Plasters", "Face masks"]
        case .other: ["Umbrella", "Reusable water bottle", "Small bag for day trips"]
        }
    }
}
