import SwiftUI
import SwiftData
import MapKit

struct TicketDetailView: View {
    @Bindable var ticket: Ticket
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var copied = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TicketCard(ticket: ticket)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if let place = ticket.place {
                    NavigationLink {
                        PlaceDetailView(place: place)
                    } label: {
                        LabeledContent("For place") {
                            Text([place.dayIndex.map { "Day \($0 + 1)" }, place.name].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                }
                LabeledContent("When", value: ticket.whenText)
                if !ticket.venue.isEmpty {
                    Button {
                        openInMaps()
                    } label: {
                        LabeledContent("Venue") {
                            HStack(spacing: 6) {
                                Text(ticket.venue).foregroundStyle(.primary).multilineTextAlignment(.trailing)
                                Image(systemName: "map")
                            }
                        }
                    }
                }
                if !ticket.seat.isEmpty { LabeledContent("Seat / slot", value: ticket.seat) }
            }

            Section("Booking") {
                if !ticket.bookingReference.isEmpty {
                    Button {
                        UIPasteboard.general.string = ticket.bookingReference
                        copied = true
                        Toaster.shared.show("Booking reference copied", systemImage: "doc.on.doc.fill", style: .info)
                    } label: {
                        LabeledContent("Booking reference") {
                            HStack {
                                Text(ticket.bookingReference).foregroundStyle(.primary).font(.app(.body))
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            }
                        }
                    }
                }
                if !ticket.bookingSite.isEmpty { LabeledContent("Booked on", value: ticket.bookingSite) }
                if ticket.price > 0 {
                    LabeledContent(ticket.isShared ? "Total price" : "Price") {
                        VStack(alignment: .trailing) {
                            Text(ticket.priceMYR.myr)
                            if ticket.currency != "MYR" {
                                Text(ticket.price.money(ticket.currency)).font(.app(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if ticket.people > 1 {
                        LabeledContent("You pay") {
                            VStack(alignment: .trailing) {
                                Text(ticket.myShareMYR.myr).fontWeight(.semibold)
                                Text("\(ticket.shareText) · \(ticket.perPersonMYR.myr) each")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !ticket.notes.isEmpty {
                    Text(ticket.notes).font(.app(.subheadline)).foregroundStyle(.secondary)
                }
            }

            if !ticket.guestExpenses.isEmpty {
                Section {
                    ForEach(Array(ticket.sortedGuestExpenses.enumerated()), id: \.element.persistentModelID) { index, guest in
                        GuestPaybackRow(guest: guest, placeholder: "Person \(index + 2) name")
                    }
                } header: {
                    Text("Paying you back")
                } footer: {
                    let count = ticket.guestExpenses.count
                    Text(count == ticket.paidBackCount
                         ? "Everyone has paid you back. These tickets cost you \(ticket.myCostMYR.myr)."
                         : "You covered \(count) other \(count == 1 ? "person" : "people") (\(ticket.perPersonMYR.myr) each). Tick them off when they pay you back; it's recorded in Expenses.")
                }
            }

            AttachmentsSection(
                title: "E-tickets & QR codes",
                footer: "Saved on your phone so you can show them at the entrance, even offline. Long-press to remove.",
                attachments: ticket.sortedAttachments
            ) { data, fileName, isPDF in
                let attachment = HotelAttachment(data: data, fileName: fileName, isPDF: isPDF)
                context.insert(attachment)
                attachment.ticket = ticket
            }

            Section {
                Button("Delete ticket", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(ticket.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if ticket.needsGuestSync { ticket.syncExpense(in: context) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let trip = ticket.trip { TicketFormView(trip: trip, ticket: ticket) }
        }
        .alert("Delete \(ticket.name)?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                context.delete(ticket)
                dismiss()
            }
        } message: {
            Text("Its expense and saved e-tickets are removed too. This can't be undone.")
        }
    }

    /// Searches Maps for the venue, near the trip's destination.
    private func openInMaps() {
        let query = [ticket.venue, ticket.trip?.mainDestination ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}

/// A ticket drawn like an admission stub: name and time on top, booking details on the stub.
struct TicketCard: View {
    let ticket: Ticket

    private let topHeight: CGFloat = 112

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Ticket", systemImage: "ticket.fill")
                        .font(.app(.subheadline, .bold))
                        .foregroundStyle(ExpenseCategory.tickets.color)
                    Spacer()
                    Text(ticket.whenText)
                        .font(.app(.subheadline, .medium))
                        .opacity(0.85)
                }
                Text(ticket.name)
                    .font(.poppins(size: 24, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let place = ticket.place {
                    Label(place.dayIndex.map { "Day \($0 + 1) · \(place.name)" } ?? place.name, systemImage: "mappin.and.ellipse")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !ticket.venue.isEmpty {
                    Label(ticket.venue, systemImage: "mappin.and.ellipse")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .frame(height: topHeight, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(colors: [ExpenseCategory.tickets.color.opacity(0.18), Theme.blue.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }

            DashedDivider().padding(.horizontal, 18)

            HStack(alignment: .top) {
                detail("PEOPLE", ticket.people <= 1 ? "1" : "\(ticket.people)")
                Spacer()
                detail("SEAT / SLOT", ticket.seat)
                Spacer()
                detail("BOOKING", ticket.bookingReference)
                Spacer()
                detail("PRICE", ticket.price > 0 ? ticket.priceMYR.formatted(.currency(code: "MYR").precision(.fractionLength(0))) : "")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(TicketShape(notchY: topHeight), style: FillStyle(eoFill: true))
        .overlay(
            TicketShape(notchY: topHeight)
                .stroke(ExpenseCategory.tickets.color.opacity(0.35), lineWidth: 1)
                .clipShape(Rectangle())
        )
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
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
