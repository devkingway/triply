import SwiftUI
import SwiftData

struct HotelsView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @State private var showingAdd = false
    @State private var deletingHotel: Hotel?

    /// What you pay (your share when a room is shared), matching the budget.
    private var totalMYR: Double { trip.hotels.reduce(0) { $0 + $1.myCostMYR } }
    private var totalNights: Int { trip.hotels.reduce(0) { $0 + $1.nights } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if trip.hotels.isEmpty {
                    emptyState
                } else if totalMYR > 0 {
                    // Same total row as the Flights page.
                    HStack {
                        Label("\(trip.hotels.count) hotel\(trip.hotels.count == 1 ? "" : "s") · \(totalNights) night\(totalNights == 1 ? "" : "s")",
                              systemImage: "bed.double.fill")
                        Spacer()
                        Text(totalMYR.myr).font(.app(.body, .bold))
                    }
                    .font(.app(.subheadline))
                    .cardStyle(padding: 14)
                }

                let gaps = trip.nightsWithoutHotel
                if !gaps.isEmpty && !trip.hotels.isEmpty {
                    Label {
                        Text("No hotel yet for: \(gaps.map { "night of Day \($0 + 1)" }.joined(separator: ", "))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.app(.subheadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 14)
                }

                ForEach(trip.sortedHotels) { hotel in
                    NavigationLink {
                        HotelDetailView(hotel: hotel)
                    } label: {
                        HotelCard(hotel: hotel)
                    }
                    .buttonStyle(PressableCardStyle())
                    // Long-press → Delete asks first, same as flights.
                    .contextMenu {
                        Button(role: .destructive) { deletingHotel = hotel } label: {
                            Label("Delete hotel", systemImage: "trash")
                        }
                    }
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
                Label("Add hotel", systemImage: "plus")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .bottomBarBlur()
        }
        .alert("Delete \(deletingHotel?.name ?? "hotel")?", isPresented: Binding(get: { deletingHotel != nil }, set: { if !$0 { deletingHotel = nil } })) {
            Button("Cancel", role: .cancel) { deletingHotel = nil }
            Button("Delete", role: .destructive) {
                if let deletingHotel { withAnimation { context.delete(deletingHotel) } }
                deletingHotel = nil
            }
        } message: {
            Text("Its expense and saved documents are removed too. This can't be undone.")
        }
        .sheet(isPresented: $showingAdd) {
            HotelFormView(trip: trip)
        }
    }

    /// Same card as the Flights page's empty state.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No hotels yet", systemImage: "bed.double")
        } description: {
            Text("Add your bookings with dates, price and confirmation number. The price is added to your budget, and each day's route can start and end at your hotel.")
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// A hotel drawn as a room key card, with an "insert" arrow on the side.
struct HotelCard: View {
    let hotel: Hotel

    /// Text and the arrow use the text colour (black in light mode, white in dark mode).
    private let edge = Color(.separator)
    private let ink = Color.primary
    private let soft = Color.secondary


    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hotel.name)
                            .font(.app(.headline, .bold))
                            .lineLimit(1)
                        Text(hotel.address.isEmpty ? "Room key" : hotel.address)
                            .font(.app(.caption))
                            .foregroundStyle(soft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    statusChip
                }

                Spacer(minLength: 8)

                // Booking details you'd show at the front desk.
                HStack(alignment: .top, spacing: 24) {
                    bookingField("BOOKING REF", hotel.confirmationNumber)
                    bookingField("BOOKED ON", hotel.bookingSite)
                }

                Spacer(minLength: 8)

                Text("\(shortDate(hotel.checkIn)) → \(shortDate(hotel.checkOut))")
                    .font(.poppins(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detailsLine)
                    .font(.app(.caption, .medium))
                    .foregroundStyle(soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
            }
            .padding(.leading, 18)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)

            // The black arrow showing which way the card goes into the door.
            VStack(spacing: 6) {
                ArrowHead()
                    .fill(ink)
                    .frame(width: 22, height: 32)
                Text("INSERT")
                    .font(.poppins(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(soft)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .frame(width: 14, height: 46)
            }
            .frame(width: 64)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(ink)
        // Credit-card proportions; the content fills the card.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1.586, contentMode: .fit)
        // Same teal-to-blue glass as the Budget summary card.
        .glassCard()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// e.g. "4 nights · 4 guests · RM 26 you pay".
    private var detailsLine: String {
        var parts = ["\(hotel.nights) night\(hotel.nights == 1 ? "" : "s")"]
        if hotel.guests > 1 { parts.append("\(hotel.guests) guests") }
        if hotel.price > 0 {
            parts.append(hotel.myCostMYR.formatted(.currency(code: "MYR").precision(.fractionLength(0))))
        }
        return parts.joined(separator: " · ")
    }

    /// "In 3 days", "Staying · night 2" or "Checked out".
    private var statusChip: some View {
        let cal = Calendar.current
        let now = Date.now
        let text: String
        if now < hotel.checkIn {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: hotel.checkIn)).day ?? 0
            text = days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days"
        } else if now < hotel.checkOut {
            let night = (cal.dateComponents([.day], from: cal.startOfDay(for: hotel.checkIn), to: cal.startOfDay(for: now)).day ?? 0) + 1
            text = "Night \(min(night, hotel.nights))"
        } else {
            text = "Checked out"
        }
        return Text(text)
            .font(.app(.caption2, .semibold))
            .foregroundStyle(soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(edge, lineWidth: 1))
    }

    private func bookingField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.poppins(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(soft)
            Text(value.isEmpty ? "—" : value)
                .font(.app(.subheadline, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Solid right-pointing triangle.
private struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
