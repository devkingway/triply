import SwiftUI
import SwiftData
import Charts
import Pow

struct BudgetView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var editing: Expense?
    @State private var duplicating: Expense?
    /// Summary card page: 0 = spending, 1 = by category.
    @State private var summaryPage = 0
    @State private var summaryHeights: [Int: CGFloat] = [:]
    /// Day chips: `allID`, a trip day index, or `otherID` (spent before/after the trip).
    @State private var daySelection = TripDetailView.allID
    @State private var pickedDefaultDay = false

    private static let allID = TripDetailView.allID
    /// Space between the summary cards while swiping.
    private static let cardGap: CGFloat = 16
    private var otherID: Int { trip.dayCount }
    /// Day chips only make sense when the trip has real dates and more than one day.
    /// Drafts have no dates, so their expenses can't be split by day.
    private var showsDayChips: Bool { !trip.isDraft }

    /// Which trip day an expense falls on, or `otherID` when it's outside the trip (e.g. booked earlier).
    private func dayIndex(of expense: Expense) -> Int {
        let cal = Calendar.current
        let index = cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate),
                                       to: cal.startOfDay(for: expense.date)).day ?? -1
        return (0..<trip.dayCount).contains(index) ? index : otherID
    }

    private var selection: Int {
        guard showsDayChips else { return Self.allID }
        return daySelection == Self.allID || daySelection == otherID || (0..<trip.dayCount).contains(daySelection)
            ? daySelection : Self.allID
    }

    /// Chip name for money paid outside the trip dates (usually flights and hotels booked early).
    private var outsideLabel: String {
        let start = Calendar.current.startOfDay(for: trip.startDate)
        let outside = trip.expenses.filter { dayIndex(of: $0) == otherID }
        return outside.allSatisfy { $0.date < start } ? "Before trip" : "Other"
    }

    /// The expenses for the selected chip.
    private var shownExpenses: [Expense] {
        selection == Self.allID ? trip.expenses : trip.expenses.filter { dayIndex(of: $0) == selection }
    }

    private var byCategory: [(category: ExpenseCategory, total: Double)] {
        ExpenseCategory.allCases
            // Only your own spending (items bought for friends aren't counted).
            .map { cat in (cat, shownExpenses.filter { $0.countsAsMySpending && $0.category == cat }.reduce(0) { $0 + $1.finalMYR }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    /// Expenses grouped by calendar day, newest day first.
    private var byDay: [(day: Date, items: [Expense])] {
        let groups = Dictionary(grouping: shownExpenses) { Calendar.current.startOfDay(for: $0.date) }
        return groups
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.0 > $1.0 }
    }

    var body: some View {
        List {
            Section {
                summaryStack
            } footer: {
                // In the footer, not a row, so the list's rounded row corners don't cut the chips off.
                if showsDayChips {
                    DayJumpBar(
                        trip: trip, selection: selection, allID: Self.allID,
                        extra: trip.expenses.contains { dayIndex(of: $0) == otherID }
                            ? ExtraDayChip(id: otherID, icon: "calendar.badge.clock", label: outsideLabel,
                                           tint: .secondary, accessibility: "Paid before or after the trip")
                            : nil,
                        hasDot: { day in trip.expenses.contains { dayIndex(of: $0) == day } }
                    ) { picked in
                        Haptics.tap()
                        withAnimation(.snappy) { daySelection = picked }
                    }
                    .dayBarFooter()
                }
            }

            if !trip.expenses.isEmpty && shownExpenses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(selection == otherID ? "Nothing paid outside the trip dates" : "Nothing spent on this day yet",
                              systemImage: "banknote")
                    } description: {
                        Text(selection == otherID
                             ? "Flights and hotels paid before the trip show up here, on the day you paid."
                             : "Tap Add expense below to log what you spend on this day.")
                    }
                }
            }

            if trip.expenses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No expenses yet", systemImage: "banknote")
                    } description: {
                        Text("Add what you spend on food, transport, tickets and shopping. Amounts in \(trip.localCurrency) are converted to RM automatically.")
                    }
                }
            }

            ForEach(byDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { expense in
                        if let flight = expense.linkedFlight {
                            // Flight costs (and passengers you paid for) are managed in the Flights tab: tap opens the flight.
                            NavigationLink { FlightDetailView(flight: flight) } label: { ExpenseRow(expense: expense) }
                                .swipeActions(edge: .leading) {
                                    if expense.isForSomeoneElse { paidBackButton(expense) }
                                }
                        } else if let ticket = expense.linkedTicket {
                            // Ticket bookings (and people you paid for) are managed in Booking → Tickets.
                            NavigationLink { TicketDetailView(ticket: ticket) } label: { ExpenseRow(expense: expense) }
                                .swipeActions(edge: .leading) {
                                    if expense.isForSomeoneElse { paidBackButton(expense) }
                                }
                        } else if let hotel = expense.linkedHotel {
                            // Hotel costs (and guests you paid for) are managed on the hotel.
                            NavigationLink { HotelDetailView(hotel: hotel) } label: { ExpenseRow(expense: expense) }
                                .swipeActions(edge: .leading) {
                                    if expense.isForSomeoneElse { paidBackButton(expense) }
                                }
                        } else {
                            Button { editing = expense } label: { ExpenseRow(expense: expense) }
                                // Plain style keeps names/amounts in normal text colour instead of the teal tint.
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        duplicating = expense
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                            .labelStyle(.iconOnly)
                                    }
                                    .tint(trip.accent)
                                    if expense.isForSomeoneElse { paidBackButton(expense) }
                                }
                                // Icon-only delete (no caption under the icon).
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation { context.delete(expense) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .labelStyle(.iconOnly)
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text(dayHeader(group.day))
                        Spacer()
                        Text(group.items.filter(\.countsAsMySpending).reduce(0) { $0 + $1.finalMYR }.myr)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAdd = true
            } label: {
                Label("Add expense", systemImage: "plus")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .bottomBarBlur()
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseFormView(trip: trip)
        }
        .onAppear {
            // Older bookings: add the "owes you" rows for guests you paid for.
            for hotel in trip.hotels where hotel.needsGuestSync { hotel.syncExpense(in: context) }
            for flight in trip.flights where flight.needsPassengerSync { flight.syncExpense(in: context) }
            for ticket in trip.tickets where ticket.needsGuestSync { ticket.syncExpense(in: context) }
            // During the trip, open on today's spending.
            guard !pickedDefaultDay else { return }
            pickedDefaultDay = true
            if showsDayChips, let today = trip.todayIndex { daySelection = today }
        }
        .sheet(item: $editing) { expense in
            ExpenseFormView(trip: trip, expense: expense)
        }
        .sheet(item: $duplicating) { expense in
            ExpenseFormView(trip: trip, expense: expense, startAsCopy: true)
        }
    }

    /// Swipe action: mark someone you paid for as paid back (or undo it).
    private func paidBackButton(_ expense: Expense) -> some View {
        Button {
            withAnimation { expense.setRepaid(!expense.isRepaid) }
            Toaster.shared.show(expense.isRepaid
                                ? "\(expense.paidForLabel) paid you back · \(expense.amountMYR.myr) removed from spending"
                                : "Not paid back yet · counted in spending again",
                                systemImage: expense.isRepaid ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
        } label: {
            Label(expense.isRepaid ? "Not paid" : "Paid back",
                  systemImage: expense.isRepaid ? "arrow.uturn.backward" : "checkmark")
                .labelStyle(.iconOnly)
        }
        .tint(expense.isRepaid ? .gray : .green)
    }

    // MARK: - Summary

    /// The summary cards: swipe left or right to switch between spending and categories.
    private var summaryStack: some View {
        // Both cards share the taller one's height, so the stack stays the same size.
        let height = summaryHeights.values.max() ?? 200
        return VStack(spacing: 10) {
            TabView(selection: $summaryPage) {
                summaryPageView(0) { summary }
                if hasMoneyBack { summaryPageView(1) { moneyBackPage } }
                summaryPageView(2) { categoryPage }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)
            // Measure both cards up front (the pager only builds a page once you swipe to it),
            // so the stack is sized to the largest card from the start and never grows mid-swipe.
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    measured(0) { summary }
                    if hasMoneyBack { measured(1) { moneyBackPage } }
                    measured(2) { categoryPage }
                }
                .padding(.horizontal, Self.cardGap / 2)
                .hidden()
                .accessibilityHidden(true)
            }
            // Each page has 8pt each side, so swiping shows a 16pt gap between cards;
            // pulling the pager out by 8pt keeps the card at rest lined up with the rest of the page.
            .padding(.horizontal, -Self.cardGap / 2)

            HStack(spacing: 6) {
                ForEach(summaryPages, id: \.self) { page in
                    Capsule()
                        .fill(page == summaryPage ? trip.accent : Color.secondary.opacity(0.35))
                        .frame(width: page == summaryPage ? 18 : 6, height: 6)
                        .onTapGesture { withAnimation(.snappy) { summaryPage = page } }
                }
            }
            .animation(.snappy, value: summaryPage)
            .accessibilityElement()
            .accessibilityLabel("\(Self.pageNames[summaryPage] ?? ""), page \((summaryPages.firstIndex(of: summaryPage) ?? 0) + 1) of \(summaryPages.count)")

        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        // The tax back / friends card goes away when there's nothing on it.
        .onChange(of: hasMoneyBack) { _, has in
            if !has && summaryPage == 1 { summaryPage = 0 }
            if !has { summaryHeights[1] = nil }
        }
    }

    private static let pageNames = [0: "Spending summary", 1: "Tax back and bought for friends", 2: "By category"]

    /// Tax back or items bought for friends: shown on their own card after the first one.
    private var hasMoneyBack: Bool { trip.totalTaxRefund > 0 || trip.totalForFriends > 0 }

    private var summaryPages: [Int] { hasMoneyBack ? [0, 1, 2] : [0, 2] }

    /// Second card: tax refunds taken off Spent, and what you bought for friends, as two tiles.
    private var moneyBackPage: some View {
        let taxBack = trip.totalTaxRefund
        let refunds = trip.myExpenses.filter(\.hasTaxRefund).count
        let friends = trip.totalForFriends
        let owed = trip.owedToYou
        let paidBack = max(friends - owed, 0)
        let items = trip.friendExpenses.count
        let repaid = trip.friendExpenses.filter(\.isRepaid).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                MoneyBackTile(
                    icon: "arrow.uturn.backward",
                    tint: .green,
                    title: "Tax back",
                    amount: taxBack > 0 ? "−\(taxBack.myr)" : nil,
                    detail: taxBack > 0
                        ? "\(refunds) refund\(refunds == 1 ? "" : "s") · taken off Spent"
                        : "Add a tax refund to an expense",
                    progress: nil,
                    progressText: nil
                )
                MoneyBackTile(
                    icon: "person.2.fill",
                    tint: .orange,
                    title: "For friends",
                    amount: friends > 0 ? friends.myr : nil,
                    detail: friends == 0 ? "Nothing bought for friends"
                        : owed > 0 ? "\(owed.myr) owed to you" : "All paid back",
                    progress: friends > 0 ? paidBack / friends : nil,
                    progressText: friends > 0 ? "\(repaid) of \(items) paid back" : nil
                )
            }
            // Both tiles as tall as the taller one.
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    /// One card in the stack. Measures its natural height so both cards share the taller one's height.
    private func summaryPageView<Content: View>(_ page: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Self.cardGap / 2)
            .tag(page)
    }

    /// A card at its natural height, reporting that height (used hidden, just to size the stack).
    private func measured<Content: View>(_ page: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { summaryHeights[page] = $0 }
    }

    /// Last card: spending by category for the selected day (or the whole trip).
    private var categoryPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if byCategory.isEmpty {
                Text("Nothing spent yet. Add an expense to see where your money goes.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                categoryChart
            }
        }
        .padding(18)
        // Centred in the card when the other card is taller.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private var summary: some View {
        // Spending after discounts and tax back.
        let spent = trip.netSpent
        let net = trip.netSpent
        let budget = trip.budget
        // Progress and "left" count tax refunds as money back.
        let ratio = budget > 0 ? net / budget : 0
        let over = budget > 0 && net > budget
        let accent: Color = over ? .red : trip.accent
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                if budget > 0 {
                    ZStack {
                        Circle().stroke(accent.opacity(0.18), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: min(ratio, 1))
                            .stroke(over ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.brandGradient),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(duration: 0.6), value: ratio)
                        Text("\(Int((ratio * 100).rounded()))%")
                            .font(.app(.headline, .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 84, height: 84)
                    .changeEffect(.shine, value: spent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spent")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(.secondary)
                    Text(spent.myr)
                        .font(.poppins(size: 30, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: spent)
                        .changeEffect(.spray(origin: .center) {
                            Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                        }, value: trip.myExpenses.count)
                    if budget > 0 {
                        Text(over ? "Over by \((-trip.remaining).myr)" : "\(trip.remaining.myr) left of \(budget.myr)")
                            .font(.app(.subheadline, .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(accent)
                            .changeEffect(.shake(rate: .fast), value: over, isEnabled: over)
                    }
                }
                Spacer(minLength: 0)
            }
            if budget <= 0 {
                Text("Set a budget with Edit to track how much is left.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        // Centred in the card when the other card is taller.
        .frame(maxHeight: .infinity)
        // See-through frosted glass with a faint brand (or red) tint.
        .glassCard(tint: accent, secondTint: over ? .orange : trip.accent2)
    }

    private var categoryChart: some View {
        HStack(spacing: 16) {
            Chart(byCategory, id: \.category) { item in
                SectorMark(angle: .value("Amount", item.total), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(item.category.color)
                    .cornerRadius(3)
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(byCategory, id: \.category) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.category.color).frame(width: 8, height: 8)
                        Text(item.category.name).font(.app(.subheadline))
                        Spacer()
                        Text(item.total.myr).font(.app(.subheadline))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        let index = cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: day).day ?? -1
        let dateText = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if (0..<trip.dayCount).contains(index) { return "Day \(index + 1) · \(dateText)" }
        return index < 0 ? "Before trip · \(dateText)" : "After trip · \(dateText)"
    }
}

struct ExpenseRow: View {
    @Environment(\.tripAccent) private var accent
    let expense: Expense

    /// "Split · 1 of 2 people · bill RM …" for a split expense or a shared hotel room.
    private var splitLine: String? {
        if let hotel = expense.hotel, hotel.guests > 1 {
            // This row is your own portion; people you paid for have their own rows.
            return "Split · your \(min(hotel.myPortions, 1)) of \(hotel.guests) · bill \(hotel.priceMYR.myr)"
        }
        if let ticket = expense.ticket, ticket.people > 1 {
            return "Split · your \(min(ticket.myPortions, 1)) of \(ticket.people) · bill \(ticket.priceMYR.myr)"
        }
        if let flight = expense.flight, flight.passengers > 1 {
            return "Split · your \(min(flight.myPortions, 1)) of \(flight.passengers) · bill \(flight.priceMYR.myr)"
        }
        if expense.isSplit {
            return "Split · \(expense.splitText) · bill \(expense.totalMYR.myr)"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.systemImage)
                .font(.app(.subheadline))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(expense.category.color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                // Hotel rows show just the hotel name (older ones were saved with "(4 nights)" added).
                Text(expense.linkedHotel?.name ?? (expense.title.isEmpty ? expense.category.name : expense.title))
                    .foregroundStyle(.primary)
                if expense.isForSomeoneElse {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text("For \(expense.paidForLabel)")
                        Text("·")
                        Text(expense.isRepaid ? (expense.repaidAt.map { "Paid back \($0.formatted(.dateTime.day().month(.abbreviated))) ✓" } ?? "Paid back ✓") : "Owes you")
                            .foregroundStyle(expense.isRepaid ? .green : .orange)
                    }
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.orange)
                }
                if let split = splitLine {
                    Label(split, systemImage: "person.3.fill")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(accent)
                }
                if !expense.notes.isEmpty {
                    Text(expense.notes)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // The amount after discount and tax back.
                Text(expense.finalMYR.myr)
                    .font(.app(.body))
                    // Grey once a friend has paid back: recorded, no longer your spending.
                    .foregroundStyle(expense.countsAsMySpending ? .primary : .secondary)
                if expense.currency != "MYR" {
                    Text(expense.finalAmount.money(expense.currency))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                if expense.hasTaxRefund {
                    Text("+\(expense.taxRefundMYR.myr) tax back")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(.green)
                }
                if expense.hasDiscount {
                    Text("−\(expense.discountMYR.myr) discount")
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(accent)
                }
            }
        }
        .contentShape(Rectangle())
    }
}


/// One half of the Money back card: an icon, the amount, and a line about it.
private struct MoneyBackTile: View {
    let icon: String
    let tint: Color
    let title: String
    /// `nil` = nothing yet (the tile is dimmed).
    let amount: String?
    let detail: String
    /// Share paid back so far (0...1), shown as a bar.
    let progress: Double?
    let progressText: String?

    var body: some View {
        let done = (progress ?? 0) >= 1
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: done ? "checkmark" : icon)
                    .font(.app(.subheadline, .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill((done ? Color.green : tint).gradient))
                    .contentTransition(.symbolEffect(.replace))
                Spacer()
                Text(title)
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(amount ?? "RM 0")
                .font(.poppins(size: 22, weight: .bold))
                .foregroundStyle(amount == nil ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy, value: amount)
            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint.opacity(0.2))
                            Capsule()
                                .fill((done ? Color.green : tint).gradient)
                                .frame(width: max(geo.size.width * min(progress, 1), progress > 0 ? 6 : 0))
                        }
                    }
                    .frame(height: 6)
                    .animation(.spring, value: progress)
                    if let progressText {
                        Text(progressText)
                            .font(.app(.caption2, .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(detail)
                .font(.app(.caption, .medium))
                .foregroundStyle(amount == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(amount == nil ? 0.05 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(amount == nil ? 0.1 : 0.25), lineWidth: 1)
        )
        .opacity(amount == nil ? 0.75 : 1)
    }
}

