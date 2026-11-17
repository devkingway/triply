import SwiftUI
import SwiftData
import MapKit

struct PlaceDetailView: View {
    @Bindable var place: Place
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @State private var showingAddLink = false
    @State private var showingChangePlace = false
    @State private var showingAddTicket = false
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    var body: some View {
        Form {
            if place.hasLocation {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                        Marker(place.name, coordinate: place.coordinate)
                    }
                    // Re-centre the map when the place is changed.
                    .id("\(place.latitude),\(place.longitude)")
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No location yet")
                            Text(place.trip == nil
                                 ? "Move it to a trip, then use Set location to find it on the map."
                                 : "Use Set location below to find it on the map.")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mappin.slash").foregroundStyle(.orange)
                    }
                }
            }

            if place.trip == nil {
                // Saved to "All" from a shared post: not in a trip yet.
                Section {
                    if trips.isEmpty {
                        Text("Create a trip first, then move this place into it.")
                            .foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(trips) { trip in
                                Button(trip.name) {
                                    withAnimation { place.move(to: trip) }
                                    try? context.save()
                                    Toaster.shared.show("Moved to \(trip.name) · Saved items", systemImage: "suitcase.fill")
                                }
                            }
                        } label: {
                            Label("Move to a trip", systemImage: "suitcase.fill")
                        }
                    }
                } header: {
                    Text("Saved items")
                } footer: {
                    Text("It goes into the trip's Saved items. From there you can put it on a day.")
                }
            }

            Section("Details") {
                TextField("Name", text: $place.name)
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                // Swap for a different place; day, time, notes and saved links stay.
                // Same search as "Save an idea": suggestions, search near the trip, or drop a pin.
                if place.trip != nil {
                    Button {
                        showingChangePlace = true
                    } label: {
                        HStack {
                            Label(place.hasLocation ? "Change place" : "Set location",
                                  systemImage: place.hasLocation ? "arrow.triangle.2.circlepath" : "mappin.and.ellipse")
                                .foregroundStyle(.tint)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let trip = place.trip {
                    Picker("Day", selection: dayBinding(trip)) {
                        Text("Saved item (no day)").tag(Int?.none)
                        ForEach(0..<trip.dayCount, id: \.self) { day in
                            Text(trip.dayTitle(day)).tag(Int?.some(day))
                        }
                    }
                }
                Toggle("Set a time", isOn: hasTimeBinding)
                if place.time != nil {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            }

            if place.trip != nil {
                Section {
                    ForEach(place.sortedTickets) { ticket in
                        NavigationLink {
                            TicketDetailView(ticket: ticket)
                        } label: {
                            BookingRow(
                                icon: "ticket.fill", tint: ExpenseCategory.tickets.color,
                                title: ticket.name,
                                subtitle: [ticket.whenText,
                                           ticket.people > 1 ? "\(ticket.people) people" : nil,
                                           ticket.price > 0 ? ticket.myShareMYR.myr : nil]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                        }
                    }
                    Button {
                        showingAddTicket = true
                    } label: {
                        Label("Add ticket", systemImage: "plus")
                    }
                } header: {
                    Text("Tickets")
                } footer: {
                    Text("Entry, show or tour tickets for this place. Save the e-ticket or QR code to show at the entrance; the price goes in your budget under Tickets.")
                }
            }

            Section("Notes") {
                // Return starts a new line; Done above the keyboard closes it.
                NotesEditor(placeholder: "e.g. must try the tonkotsu, open 10am–9pm", text: $place.notes, minHeight: 100)
            }

            Section {
                ForEach(place.sortedLinks) { link in
                    Button {
                        if let url = link.url { openURL(url) }
                    } label: {
                        LinkRow(link: link)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(link)
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .tint(.red)
                    }
                }
                Button {
                    showingAddLink = true
                } label: {
                    Label("Add Instagram / Facebook link", systemImage: "plus")
                }
            } header: {
                Text("Saved posts & links")
            } footer: {
                Text("Tip: in Instagram or Facebook tap Share → Triply to save a post straight from there. Or copy the link and add it here. Tap a saved link to open the post.")
            }

            if place.hasLocation {
            Section {
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                    item.name = place.name
                    item.openInMaps()
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                }
            }
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChangePlace) {
            if let trip = place.trip {
                PlaceSearchView(trip: trip, dayIndex: place.dayIndex, replacing: place)
            }
        }
        .sheet(isPresented: $showingAddTicket) {
            if let trip = place.trip { TicketFormView(trip: trip, place: place) }
        }
        .sheet(isPresented: $showingAddLink) {
            AddLinkView(place: place)
        }
    }

    private func dayBinding(_ trip: Trip) -> Binding<Int?> {
        Binding {
            place.dayIndex
        } set: { newDay in
            guard newDay != place.dayIndex else { return }
            place.order = trip.nextOrder(forDay: newDay)
            place.dayIndex = newDay
        }
    }

    private var hasTimeBinding: Binding<Bool> {
        Binding {
            place.time != nil
        } set: { on in
            if on {
                let base = place.trip.flatMap { trip in place.dayIndex.map { trip.date(forDay: $0) } } ?? .now
                place.time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: base)
            } else {
                place.time = nil
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding { place.time ?? .now } set: { place.time = $0 }
    }
}

struct LinkRow: View {
    let link: SavedLink

    var body: some View {
        HStack(spacing: 12) {
            // The post's preview picture, or the platform icon until it loads (or if there's none).
            LinkThumbnail(url: link.url, size: 44) {
                Image(systemName: link.platform.systemImage)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(link.platform.color.gradient))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(link.note.isEmpty ? "\(link.platform.name) post" : link.note)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(link.urlString)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.secondary)
        }
    }
}

struct AddLinkView: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var note = ""

    private var detectedURL: URL? { Self.extractURL(from: text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first }
                    }
                    TextField("https://www.instagram.com/p/…", text: $text, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Link")
                } footer: {
                    if let url = detectedURL {
                        Label("\(LinkPlatform(url: url).name) link detected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if !text.isEmpty {
                        Text("No link found in the pasted text.")
                            .foregroundStyle(.red)
                    }
                }
                Section("Note (optional)") {
                    TextField("e.g. the matcha dessert reel", text: $note)
                }
            }
            .navigationTitle("Add link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let url = detectedURL else { return }
                        let link = SavedLink(urlString: url.absoluteString, note: note.trimmingCharacters(in: .whitespaces))
                        context.insert(link)
                        link.place = place
                        Toaster.shared.show("\(link.platform.name) link saved", systemImage: link.platform.systemImage)
                        dismiss()
                    }
                    .disabled(detectedURL == nil)
                }
            }
        }
    }

    /// Pulls the first web link out of pasted text (shared posts often include a caption).
    static func extractURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let match = detector.firstMatch(in: trimmed, range: range)
        guard let url = match?.url, url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }
}
