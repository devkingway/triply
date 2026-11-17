import SwiftUI
import SwiftData
import Pow

struct FlightsView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var deleting: Flight?

    private var totalMYR: Double { trip.flights.reduce(0) { $0 + $1.myCostMYR } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if trip.flights.isEmpty {
                    emptyState
                } else if totalMYR > 0 {
                    HStack {
                        Label("\(trip.flights.count) flight\(trip.flights.count == 1 ? "" : "s")", systemImage: "airplane")
                        Spacer()
                        Text(totalMYR.myr).font(.app(.body, .bold))
                    }
                    .font(.app(.subheadline))
                    .cardStyle(padding: 14)
                }

                let flights = trip.sortedFlights
                ForEach(Array(flights.enumerated()), id: \.element.id) { index, flight in
                    if index > 0, let gap = flights[index - 1].layover(before: flight) {
                        TransferChip(arriving: flights[index - 1], departing: flight, layover: gap)
                    }
                    NavigationLink {
                        FlightDetailView(flight: flight)
                    } label: {
                        FlightCard(flight: flight)
                    }
                    .buttonStyle(PressableCardStyle())
                    .contextMenu {
                        Button(role: .destructive) { deleting = flight } label: {
                            Label("Delete flight", systemImage: "trash")
                        }
                    }
                    .transition(.movingParts.pop(.indigo))
                }
            }
            .padding()
            .padding(.bottom, 70)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAdd = true
            } label: {
                Label("Add flight", systemImage: "plus")
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
            FlightFormView(trip: trip)
        }
        .alert("Delete this flight?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting { withAnimation { context.delete(deleting) } }
                Task { await FlightReminders.sync(in: context) }
                deleting = nil
            }
        } message: {
            Text("Its expense and saved boarding passes are removed too. This can't be undone.")
        }
    }

    /// Same card as the Hotels tab's empty state.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No flights yet", systemImage: "airplane")
        } description: {
            Text("Add your flights with times, seat, baggage and booking reference. The price is added to your budget, and boarding passes are saved for offline use.")
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// A flight drawn as a boarding pass.
struct FlightCard: View {
    let flight: Flight

    private let topHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            // Top: airline + route
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(flight.title.isEmpty ? "Flight" : flight.title, systemImage: "airplane")
                        .font(.app(.subheadline, .bold))
                        .foregroundStyle(Theme.teal)
                    Spacer()
                    Text(flight.departureDateText)
                        .font(.app(.subheadline, .medium))
                        .opacity(0.85)
                }
                HStack(alignment: .center) {
                    airport(code: flight.fromCode, time: flight.departureTimeText, city: flight.fromCity, alignment: .leading)
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "airplane")
                            .font(.app(.title3))
                            .foregroundStyle(Theme.teal)
                        Text(flight.durationText)
                            .font(.app(.caption2, .semibold))
                            .opacity(0.85)
                    }
                    Spacer()
                    airport(code: flight.toCode, time: flight.arrivalTimeText, city: flight.toCity, alignment: .trailing, dayOffset: flight.arrivalDayOffset)
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(height: topHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            // Same see-through teal glass as the Budget summary card.
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(colors: [Theme.teal.opacity(0.16), Theme.blue.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }

            DashedDivider().padding(.horizontal, 18)

            // Bottom: stub with details
            HStack(alignment: .top) {
                detail("SEAT", flight.seat)
                Spacer()
                detail("TERMINAL", flight.fromTerminal)
                Spacer()
                detail("BOOKING", flight.bookingReference)
                Spacer()
                detail("PRICE", flight.price > 0 ? flight.priceMYR.formatted(.currency(code: "MYR").precision(.fractionLength(0))) : "")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(TicketShape(notchY: topHeight), style: FillStyle(eoFill: true))
        .overlay(
            // Outline (only the half-circles inside the card, not the parts outside it).
            TicketShape(notchY: topHeight)
                .stroke(Theme.teal.opacity(0.35), lineWidth: 1)
                .clipShape(Rectangle())
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }

    private func airport(code: String, time: String, city: String, alignment: HorizontalAlignment, dayOffset: Int = 0) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code)
                .font(.poppins(size: 30, weight: .heavy))
            HStack(spacing: 2) {
                Text(time).font(.app(.headline))
                if dayOffset != 0 {
                    Text(dayOffset > 0 ? "+\(dayOffset)" : "\(dayOffset)")
                        .font(.app(.caption2, .bold))
                        .foregroundStyle(.orange)
                        .baselineOffset(6)
                }
            }
            Text(city)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.poppins(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.app(.subheadline, .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Sits between two connected flights: where you change planes and how long you wait.
struct TransferChip: View {
    let arriving: Flight
    let departing: Flight
    let layover: TimeInterval

    /// Under an hour is tight for most transfers.
    private var isTight: Bool { layover < 3600 }
    private var terminalChange: Bool {
        !arriving.toTerminal.isEmpty && !departing.fromTerminal.isEmpty && arriving.toTerminal != departing.fromTerminal
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isTight ? "exclamationmark.triangle.fill" : "arrow.triangle.turn.up.right.diamond.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("Transfer in \(arriving.toCity) · \(Flight.layoverText(layover))")
                    .font(.app(.subheadline, .semibold))
                if isTight || terminalChange {
                    Text([isTight ? "Short layover" : nil,
                          terminalChange ? "Terminal \(arriving.toTerminal) → \(departing.fromTerminal)" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.app(.caption))
                }
            }
        }
        .foregroundStyle(isTight ? Color.orange : Theme.teal)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill((isTight ? Color.orange : Theme.teal).opacity(0.12)))
        .frame(maxWidth: .infinity)
    }
}
