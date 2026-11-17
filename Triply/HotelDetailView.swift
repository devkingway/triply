import SwiftUI
import SwiftData
import MapKit

struct HotelDetailView: View {
    @Bindable var hotel: Hotel
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var copied = false
    @State private var confirmDelete = false

    /// Hides the Booking heading when there's nothing to show under it.
    private var hasBookingInfo: Bool {
        !hotel.confirmationNumber.isEmpty || !hotel.bookingSite.isEmpty || !hotel.address.isEmpty
            || !hotel.phone.isEmpty || !hotel.notes.isEmpty || hotel.coordinate != nil
    }

    var body: some View {
        Form {
            if let coordinate = hotel.coordinate {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700))) {
                        Marker(hotel.name, systemImage: "bed.double.fill", coordinate: coordinate)
                            .tint(.purple)
                    }
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                LabeledContent("Check-in", value: hotel.checkIn.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                LabeledContent("Check-out", value: hotel.checkOut.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                LabeledContent("Nights", value: "\(hotel.nights)")
                if hotel.price > 0 {
                    LabeledContent(hotel.isShared ? "Total price" : "Price") {
                        VStack(alignment: .trailing) {
                            Text(hotel.priceMYR.myr)
                            if hotel.currency != "MYR" {
                                Text(hotel.price.money(hotel.currency))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Per night", value: (hotel.priceMYR / Double(hotel.nights)).myr)
                }
                LabeledContent("Guests", value: hotel.guests <= 1 ? "1 person" : "\(hotel.guests) people")
                if hotel.price > 0 && hotel.guests > 1 {
                    LabeledContent("You pay") {
                        VStack(alignment: .trailing) {
                            Text(hotel.myShareMYR.myr).fontWeight(.semibold)
                            Text("\(hotel.shareText) · \((hotel.myShareMYR / Double(hotel.nights)).myr) per night")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !hotel.guestExpenses.isEmpty {
                Section {
                    ForEach(Array(hotel.sortedGuestExpenses.enumerated()), id: \.element.persistentModelID) { index, guest in
                        GuestPaybackRow(guest: guest, placeholder: "Guest \(index + 2) name")
                    }
                } header: {
                    Text("Paying you back")
                } footer: {
                    let left = hotel.guestExpenses.count - hotel.paidBackCount
                    Text(left == 0
                         ? "Everyone has paid you back. This room costs you \(hotel.myCostMYR.myr)."
                         : "You covered \(hotel.guestExpenses.count) other \(hotel.guestExpenses.count == 1 ? "guest" : "guests") (\(hotel.perGuestMYR.myr) each). Tick them off when they pay you back; it's recorded in Expenses.")
                }
            }

            if hasBookingInfo {
            Section("Booking") {
                if !hotel.confirmationNumber.isEmpty {
                    Button {
                        UIPasteboard.general.string = hotel.confirmationNumber
                        copied = true
                        Toaster.shared.show("Confirmation number copied", systemImage: "doc.on.doc.fill", style: .info)
                    } label: {
                        LabeledContent("Confirmation") {
                            HStack {
                                Text(hotel.confirmationNumber).foregroundStyle(.primary)
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            }
                        }
                    }
                }
                if !hotel.bookingSite.isEmpty {
                    LabeledContent("Booked on", value: hotel.bookingSite)
                }
                if !hotel.address.isEmpty {
                    Text(hotel.address).font(.app(.subheadline))
                }
                if !hotel.phone.isEmpty, let url = URL(string: "tel:\(hotel.phone.filter { $0.isNumber || $0 == "+" })") {
                    Button {
                        openURL(url)
                    } label: {
                        Label(hotel.phone, systemImage: "phone.fill")
                    }
                }
                if !hotel.notes.isEmpty {
                    Text(hotel.notes).font(.app(.subheadline)).foregroundStyle(.secondary)
                }
                if let coordinate = hotel.coordinate {
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                        item.name = hotel.name
                        item.openInMaps()
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                    }
                }
            }
            }

            AttachmentsSection(
                title: "Confirmation documents",
                footer: "Saved on your phone so you can show them at check-in, even offline. Long-press to remove.",
                attachments: hotel.sortedAttachments
            ) { data, fileName, isPDF in
                let attachment = HotelAttachment(data: data, fileName: fileName, isPDF: isPDF)
                context.insert(attachment)
                attachment.hotel = hotel
            }

            Section {
                Button("Delete hotel", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(hotel.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Older bookings: create the guest rows for "I pay for" if they're missing.
            if hotel.needsGuestSync { hotel.syncExpense(in: context) }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let trip = hotel.trip { HotelFormView(trip: trip, hotel: hotel) }
        }
        .alert("Delete \(hotel.name)?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                context.delete(hotel)
                dismiss()
            }
        } message: {
            Text("Its expense and saved documents are removed too. This can't be undone.")
        }
    }
}

/// One guest or passenger you paid for: a tick box for "paid me back" and their name.
struct GuestPaybackRow: View {
    @Bindable var guest: Expense
    let placeholder: String
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { guest.setRepaid(!guest.isRepaid) }
                try? context.save()
                Haptics.tap()
                if guest.isRepaid {
                    Toaster.shared.show("\(guest.paidForLabel) paid you back · \(guest.amountMYR.myr)",
                                        systemImage: "checkmark.circle.fill")
                }
            } label: {
                Image(systemName: guest.isRepaid ? "checkmark.circle.fill" : "circle")
                    .font(.app(.title2))
                    .foregroundStyle(guest.isRepaid ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(guest.isRepaid ? "Paid back" : "Not paid back")

            VStack(alignment: .leading, spacing: 2) {
                TextField(placeholder, text: Binding(
                    get: { guest.paidForName ?? "" },
                    set: { guest.paidForName = $0 }
                ))
                .textInputAutocapitalization(.words)
                .strikethrough(guest.isRepaid, color: .secondary)
                Group {
                    if guest.isRepaid {
                        if let date = guest.repaidAt {
                            Text("Paid back \(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                        } else {
                            Text("Paid back")
                        }
                    } else {
                        Text("Owes you")
                    }
                }
                .font(.app(.caption, .semibold))
                .foregroundStyle(guest.isRepaid ? .green : .orange)
            }

            Spacer()
            Text(guest.amountMYR.myr)
                .font(.app(.subheadline, .semibold))
                .foregroundStyle(guest.isRepaid ? .secondary : .primary)
        }
    }
}
