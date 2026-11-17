import SwiftUI
import SwiftData

/// The trip's More tab: the packing list on top, then a button each for Flights, Hotels, Tickets and the shared album, two per row.
/// Tapping one opens that page.
struct MoreView: View {
    @Bindable var trip: Trip

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            packingCard
                .padding([.horizontal, .top])
            LazyVGrid(columns: columns, spacing: 12) {
                card(title: "Flights", icon: "airplane", tint: .indigo,
                     count: trip.flights.count, costMYR: trip.flights.reduce(0) { $0 + $1.myCostMYR },
                     empty: "Add a flight") {
                    FlightsView(trip: trip)
                }
                card(title: "Hotels", icon: "bed.double.fill", tint: .purple,
                     count: trip.hotels.count, costMYR: trip.hotels.reduce(0) { $0 + $1.myCostMYR },
                     empty: "Add a hotel") {
                    HotelsView(trip: trip)
                }
                card(title: "Tickets", icon: "ticket.fill", tint: ExpenseCategory.tickets.color,
                     count: TicketsView.count(in: trip), costMYR: TicketsView.totalMYR(in: trip),
                     empty: "Add a ticket") {
                    TicketsView(trip: trip)
                }
                card(title: "Shared album", icon: "rectangle.stack.badge.person.crop.fill", tint: .orange,
                     detail: trip.sharedAlbumTitle ?? "Link an iCloud album") {
                    SharedAlbumView(trip: trip)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Full-width button for the packing list, with the countdown and progress.
    private var packingCard: some View {
        let total = trip.packingItems.count
        let packed = trip.packedCount
        let done = total > 0 && packed == total
        let countdown: String? = {
            guard !trip.isDraft else { return nil }
            let days = trip.daysUntilDeparture
            return days < 0 ? nil : days == 0 ? "Departs today" : days == 1 ? "Departs tomorrow" : "Departs in \(days) days"
        }()
        return NavigationLink {
            PackingListView(trip: trip)
                .navigationTitle("Packing list")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: done ? "checkmark" : "suitcase.fill")
                        .font(.app(.title3, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill((done ? Color.green : Theme.teal).gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Packing list")
                            .font(.app(.headline))
                            .foregroundStyle(.primary)
                        Text(total == 0 ? "What to bring before you depart"
                             : done ? "All packed" : "\(packed) of \(total) packed")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let countdown {
                        Text(countdown)
                            .font(.app(.caption, .semibold))
                            .foregroundStyle(Theme.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.teal.opacity(0.12), in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.app(.footnote, .semibold))
                        .foregroundStyle(.tertiary)
                }
                if total > 0 {
                    ProgressView(value: Double(packed), total: Double(total))
                        .tint(done ? .green : Theme.teal)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    /// One booking button: icon, name, and how many there are and what they cost you.
    private func card<Destination: View>(title: String, icon: String, tint: Color, count: Int, costMYR: Double,
                                         empty: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        card(title: title, icon: icon, tint: tint, detail: count == 0 ? empty : "\(count) · \(costMYR.myr)",
             destination: destination)
    }

    /// One button: icon, name and a line of detail; opens its page.
    private func card<Destination: View>(title: String, icon: String, tint: Color, detail: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.app(.title3, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.gradient))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.app(.footnote, .semibold))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.headline))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}

/// Tickets: booked attractions, shows, trains and tours, plus any other Tickets-category expenses.
struct TicketsView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var editing: Expense?
    @State private var deleting: Ticket?

    /// Tickets-category expenses that aren't from a ticket booking (added from Expenses).
    static func otherExpenses(in trip: Trip) -> [Expense] {
        trip.expenses.filter { $0.category == .tickets && $0.linkedTicket == nil }.sorted { $0.date < $1.date }
    }

    static func count(in trip: Trip) -> Int { trip.tickets.count + otherExpenses(in: trip).count }

    /// What tickets cost you, matching the budget.
    static func totalMYR(in trip: Trip) -> Double {
        trip.tickets.reduce(0) { $0 + $1.myCostMYR }
            + otherExpenses(in: trip).filter(\.countsAsMySpending).reduce(0) { $0 + $1.finalMYR }
    }

    private var others: [Expense] { Self.otherExpenses(in: trip) }
    private var totalMYR: Double { Self.totalMYR(in: trip) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if trip.tickets.isEmpty && others.isEmpty {
                    emptyState
                } else {
                    let count = Self.count(in: trip)
                    HStack {
                        Label("\(count) ticket\(count == 1 ? "" : "s")", systemImage: "ticket.fill")
                        Spacer()
                        Text(totalMYR.myr).font(.app(.body, .bold))
                    }
                    .font(.app(.subheadline))
                    .cardStyle(padding: 14)
                }

                ForEach(trip.sortedTickets) { ticket in
                    NavigationLink {
                        TicketDetailView(ticket: ticket)
                    } label: {
                        TicketCard(ticket: ticket)
                    }
                    .buttonStyle(PressableCardStyle())
                    .contextMenu {
                        Button(role: .destructive) { deleting = ticket } label: {
                            Label("Delete ticket", systemImage: "trash")
                        }
                    }
                }

                if !others.isEmpty { otherList }
            }
            .padding()
            .padding(.bottom, 70)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAdd = true
            } label: {
                Label("Add ticket", systemImage: "plus")
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
            TicketFormView(trip: trip)
        }
        .sheet(item: $editing) { expense in
            ExpenseFormView(trip: trip, expense: expense)
        }
        .alert("Delete \(deleting?.name ?? "ticket")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting { withAnimation { context.delete(deleting) } }
                deleting = nil
            }
        } message: {
            Text("Its expense and saved e-tickets are removed too. This can't be undone.")
        }
    }

    /// Tickets-category expenses added from the Expenses tab (no time or e-ticket); tap to edit.
    private var otherList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From Expenses")
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(others.enumerated()), id: \.element.persistentModelID) { index, expense in
                    if index > 0 { Divider().padding(.leading, 44) }
                    Button { editing = expense } label: {
                        ExpenseRow(expense: expense)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("Expenses in the Tickets category. For a time, venue and e-tickets, add them with Add ticket.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    /// Same card as the Flights and Hotels empty states.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No tickets yet", systemImage: "ticket")
        } description: {
            Text("Add attraction, show, train and tour tickets with their time and venue. Save e-tickets and QR codes for offline use. The price is added to your budget under Tickets.")
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
