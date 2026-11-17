import Foundation
import SwiftData

enum SampleData {
    static func insertTokyoTrip(into context: ModelContext) {
        let start = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: .now))!
        let end = Calendar.current.date(byAdding: .day, value: 4, to: start)!
        let trip = Trip(name: "Tokyo Winter", destination: "Tokyo, Japan", startDate: start, endDate: end, budget: 8000, localCurrency: "JPY")
        context.insert(trip)

        // Example hotel for every night; its price becomes a Hotel expense.
        let cal = Calendar.current
        let hotel = Hotel(
            name: "Hotel Gracery Asakusa",
            checkIn: cal.date(bySettingHour: 15, minute: 0, second: 0, of: start)!,
            checkOut: cal.date(bySettingHour: 11, minute: 0, second: 0, of: end)!
        )
        hotel.address = "2-16-2 Asakusa, Taito City, Tokyo"
        hotel.latitude = 35.7127
        hotel.longitude = 139.7948
        hotel.price = 2400
        hotel.currency = "MYR"
        hotel.confirmationNumber = "SAMPLE123"
        hotel.bookingSite = "Agoda"
        context.insert(hotel)
        hotel.trip = trip
        hotel.syncExpense(in: context)

        // Example flights: overnight there, daytime back (times are local at each airport).
        func at(_ hour: Int, _ minute: Int, dayOffset: Int, from base: Date, tz: String) -> Date {
            var c = Calendar.current
            c.timeZone = TimeZone(identifier: tz)!
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: base)
            var dc = DateComponents(year: comps.year, month: comps.month, day: comps.day! + dayOffset, hour: hour, minute: minute)
            dc.timeZone = c.timeZone
            return c.date(from: dc)!
        }
        let outbound = Flight(airline: "Malaysia Airlines", flightNumber: "MH88", fromCode: "KUL", toCode: "HND",
                              departure: at(23, 30, dayOffset: -1, from: start, tz: "Asia/Kuala_Lumpur"),
                              arrival: at(7, 30, dayOffset: 0, from: start, tz: "Asia/Tokyo"))
        outbound.fromTerminal = "1"
        outbound.toTerminal = "3"
        outbound.seat = "32A"
        outbound.baggage = "30kg checked + 7kg cabin"
        outbound.bookingReference = "SAMPLE"
        outbound.price = 2100
        let inbound = Flight(airline: "Malaysia Airlines", flightNumber: "MH89", fromCode: "HND", toCode: "KUL",
                             departure: at(10, 30, dayOffset: 0, from: end, tz: "Asia/Tokyo"),
                             arrival: at(17, 0, dayOffset: 0, from: end, tz: "Asia/Kuala_Lumpur"))
        inbound.seat = "33K"
        inbound.bookingReference = "SAMPLE"
        for flight in [outbound, inbound] {
            context.insert(flight)
            flight.trip = trip
            flight.syncExpense(in: context)
        }

        // Example expenses (approximate rate: 1 JPY ≈ RM 0.03).
        let expenses: [(String, Double, String, Double, ExpenseCategory, Int)] = [
            ("Narita Express", 3070, "JPY", 0.03, .transport, 0),
            ("Senso-ji street snacks", 1800, "JPY", 0.03, .food, 0),
            ("Skytree tickets", 3800, "JPY", 0.03, .tickets, 0),
            ("Ichiran ramen", 2600, "JPY", 0.03, .food, 1),
            ("Uniqlo jacket", 12900, "JPY", 0.03, .shopping, 1),
        ]
        for (title, amount, currency, rate, category, day) in expenses {
            let date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: trip.date(forDay: day))!
            let expense = Expense(title: title, amount: amount, currency: currency, rateToMYR: rate, category: category, date: date)
            context.insert(expense)
            expense.trip = trip
        }

        let stops: [(String, String, Double, Double, Int?, String)] = [
            ("Senso-ji", "2-3-1 Asakusa, Taito City, Tokyo", 35.7148, 139.7967, 0, "Go early to avoid crowds"),
            ("Ueno Park", "Uenokoen, Taito City, Tokyo", 35.7156, 139.7745, 0, ""),
            ("Tokyo Skytree", "1-1-2 Oshiage, Sumida City, Tokyo", 35.7101, 139.8107, 0, "Sunset slot booked"),
            ("Meiji Jingu", "1-1 Yoyogikamizonocho, Shibuya, Tokyo", 35.6764, 139.6993, 1, ""),
            ("Shibuya Crossing", "Shibuya, Tokyo", 35.6595, 139.7005, 1, ""),
            ("Ichiran Shibuya", "1-22-7 Jinnan, Shibuya, Tokyo", 35.6614, 139.7010, 1, "Must try the tonkotsu"),
            ("teamLab Planets", "6-1-16 Toyosu, Koto City, Tokyo", 35.6491, 139.7898, nil, "Saw this on Instagram"),
        ]

        var orderByDay: [Int: Int] = [:]
        for (name, address, lat, lon, day, notes) in stops {
            let order = day.map { orderByDay[$0, default: 0] } ?? 0
            if let day { orderByDay[day] = order + 1 }
            let place = Place(name: name, address: address, latitude: lat, longitude: lon, dayIndex: day, order: order, notes: notes)
            context.insert(place)
            place.trip = trip
            if name == "teamLab Planets" {
                let link = SavedLink(urlString: "https://www.instagram.com/teamlab/", note: "teamLab on Instagram")
                context.insert(link)
                link.place = place
            }
        }
    }
}
