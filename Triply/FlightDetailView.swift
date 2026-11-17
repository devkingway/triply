import SwiftUI
import SwiftData

struct FlightDetailView: View {
    @Bindable var flight: Flight
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingReturn = false
    @State private var showingConnecting = false
    @State private var copied = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                FlightCard(flight: flight)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Departure") {
                LabeledContent(flight.fromCity, value: "\(flight.departureDateText), \(flight.departureTimeText)")
                if !flight.fromTerminal.isEmpty {
                    LabeledContent("Terminal", value: flight.fromTerminal)
                }
            }

            Section("Arrival") {
                LabeledContent(flight.toCity, value: "\(flight.arrivalDateText), \(flight.arrivalTimeText)")
                if !flight.toTerminal.isEmpty {
                    LabeledContent("Terminal", value: flight.toTerminal)
                }
                LabeledContent("Flight time", value: flight.durationText)
            }

            if flight.previousLeg != nil || flight.connectingFlight != nil {
                Section("Transfer") {
                    if let previous = flight.previousLeg, let gap = previous.layover(before: flight) {
                        LabeledContent("From \(previous.title.isEmpty ? "\(previous.fromCode) → \(previous.toCode)" : previous.title)",
                                       value: "\(Flight.layoverText(gap)) layover")
                    }
                    if let next = flight.connectingFlight, let gap = flight.layover(before: next) {
                        LabeledContent("Next: \(next.title.isEmpty ? "\(next.fromCode) → \(next.toCode)" : next.title) to \(next.toCity)",
                                       value: "\(Flight.layoverText(gap)) in \(flight.toCity)")
                    }
                }
            }

            Section("Booking") {
                if !flight.bookingReference.isEmpty {
                    Button {
                        UIPasteboard.general.string = flight.bookingReference
                        copied = true
                        Toaster.shared.show("Booking reference copied", systemImage: "doc.on.doc.fill", style: .info)
                    } label: {
                        LabeledContent("Booking reference") {
                            HStack {
                                Text(flight.bookingReference).foregroundStyle(.primary).font(.app(.body))
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            }
                        }
                    }
                }
                if !flight.seat.isEmpty { LabeledContent("Seat", value: flight.seat) }
                if !flight.baggage.isEmpty { LabeledContent("Baggage", value: flight.baggage) }
                if !flight.bookingSite.isEmpty { LabeledContent("Booked on", value: flight.bookingSite) }
                if flight.price > 0 {
                    LabeledContent(flight.isShared ? "Total price" : "Price") {
                        VStack(alignment: .trailing) {
                            Text(flight.priceMYR.myr)
                            if flight.currency != "MYR" {
                                Text(flight.price.money(flight.currency)).font(.app(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if flight.passengers > 1 {
                        LabeledContent("You pay") {
                            VStack(alignment: .trailing) {
                                Text(flight.myShareMYR.myr).fontWeight(.semibold)
                                Text("\(flight.shareText) · \(flight.perPassengerMYR.myr) each")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !flight.notes.isEmpty {
                    Text(flight.notes).font(.app(.subheadline)).foregroundStyle(.secondary)
                }
            }

            if !flight.passengerExpenses.isEmpty {
                Section {
                    ForEach(Array(flight.sortedPassengerExpenses.enumerated()), id: \.element.persistentModelID) { index, passenger in
                        GuestPaybackRow(guest: passenger, placeholder: "Passenger \(index + 2) name")
                    }
                } header: {
                    Text("Paying you back")
                } footer: {
                    let count = flight.passengerExpenses.count
                    Text(count == flight.paidBackCount
                         ? "Everyone has paid you back. This flight costs you \(flight.myCostMYR.myr)."
                         : "You covered \(count) other \(count == 1 ? "passenger" : "passengers") (\(flight.perPassengerMYR.myr) each). Tick them off when they pay you back; it's recorded in Expenses.")
                }
            }

            Section {
                if !flight.flightNumber.isEmpty, let url = URL(string: "https://www.flightradar24.com/data/flights/\(flight.flightNumber.lowercased())") {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Check flight status", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                if flight.connectingFlight == nil {
                    Button {
                        showingConnecting = true
                    } label: {
                        Label("Add connecting flight (from \(flight.toCode))", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                }
                Button {
                    showingReturn = true
                } label: {
                    Label("Add return flight (\(flight.toCode) → \(flight.fromCode))", systemImage: "arrow.uturn.left")
                }
            }

            Section {
                if flight.remindersOn {
                    ForEach(FlightReminders.reminders(for: flight), id: \.id) { reminder in
                        HStack {
                            Image(systemName: reminder.id.hasSuffix("checkin") ? "checkmark.seal" : "figure.walk.departure")
                                .foregroundStyle(Theme.teal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.id.hasSuffix("checkin") ? "Check-in opens" : "Leave for the airport")
                                    .font(.app(.subheadline, .semibold))
                                Text(reminder.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if reminder.date < .now {
                                Text("Passed").font(.app(.caption)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    Label("Reminders are off for this flight", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Times shown in your phone's time zone. Change in Edit.")
            }

            AttachmentsSection(
                title: "Boarding passes & e-tickets",
                footer: "Saved on your phone so you can open them at the airport, even offline. Long-press to remove.",
                attachments: flight.sortedAttachments
            ) { data, fileName, isPDF in
                let attachment = HotelAttachment(data: data, fileName: fileName, isPDF: isPDF)
                context.insert(attachment)
                attachment.flight = flight
            }

            Section {
                Button("Delete flight", role: .destructive) { confirmDelete = true }
            }
        }
        .onAppear {
            if flight.needsPassengerSync { flight.syncExpense(in: context) }
        }
        .navigationTitle(flight.title.isEmpty ? "\(flight.fromCode) → \(flight.toCode)" : flight.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let trip = flight.trip { FlightFormView(trip: trip, flight: flight) }
        }
        .sheet(isPresented: $showingConnecting) {
            if let trip = flight.trip { FlightFormView(trip: trip, connectingFrom: flight) }
        }
        .sheet(isPresented: $showingReturn) {
            if let trip = flight.trip { FlightFormView(trip: trip, returnOf: flight) }
        }
        .alert("Delete this flight?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                context.delete(flight)
                Task { await FlightReminders.sync(in: context) }
                dismiss()
            }
        } message: {
            Text("Its expense and saved documents are removed too. This can't be undone.")
        }
    }
}
