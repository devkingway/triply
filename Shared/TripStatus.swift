import Foundation

// Trip status shared by the app and the Home Screen widget.
extension Trip {
    enum Phase { case draft, upcoming(days: Int), during(day: Int), finished }

    var phase: Phase {
        if isDraft { return .draft }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)
        if today < start {
            return .upcoming(days: cal.dateComponents([.day], from: today, to: start).day ?? 0)
        } else if today <= end {
            return .during(day: (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
        }
        return .finished
    }

    var phaseText: String {
        switch phase {
        case .draft: "Draft"
        case .upcoming(let days): days == 1 ? "Tomorrow" : "In \(days) days"
        case .during(let day): "Day \(day) of \(dayCount)"
        case .finished: "Completed"
        }
    }

    var phaseIcon: String {
        switch phase {
        case .draft: "pencil.and.list.clipboard"
        case .upcoming: "airplane.departure"
        case .during: "location.fill"
        case .finished: "checkmark.seal.fill"
        }
    }

    /// Today's 0-based day index if the trip is happening now.
    var todayIndex: Int? {
        if case .during(let day) = phase { return day - 1 }
        return nil
    }

    /// Spending recorded on a given trip day, in MYR.
    func spent(onDay day: Int) -> Double {
        let date = date(forDay: day)
        return myExpenses
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.finalMYR }
    }

    /// The next stop today: the first place whose time hasn't passed, otherwise the first place of the day.
    func nextStop(onDay day: Int, now: Date = .now) -> Place? {
        // Stops not ticked off yet, in plan order. A stop moves on when it's marked done,
        // or when its set time has passed. `nil` = everything is done.
        let remaining = places(onDay: day).filter { !$0.isDone }
        return remaining.first { ($0.time ?? .distantFuture) > now } ?? remaining.last
    }

    /// Stable ID used in widget links (tripple://add-expense?trip=…).
    var widgetID: String { String(Int(createdAt.timeIntervalSince1970 * 1000)) }

    /// The trip to focus on: one happening now, else the next upcoming one, else the most recent.
    static func focus(in trips: [Trip]) -> Trip? {
        let planned = trips.filter { !$0.isDraft }
        if let now = planned.first(where: { $0.todayIndex != nil }) { return now }
        let today = Calendar.current.startOfDay(for: .now)
        if let next = planned.filter({ $0.startDate >= today }).min(by: { $0.startDate < $1.startDate }) { return next }
        return planned.max(by: { $0.endDate < $1.endDate })
    }
}
