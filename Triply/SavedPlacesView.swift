import SwiftUI
import SwiftData

/// Places shared to "All" (not in a trip yet). Move each into a trip when you're ready.
struct SavedPlacesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Place> { $0.trip == nil }, sort: \Place.createdAt, order: .reverse)
    private var places: [Place]
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var moving: Place?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if places.isEmpty {
                ContentUnavailableView {
                    Label("No saved items", systemImage: "tray")
                } description: {
                    Text("Share a post to Triply and choose All to keep it here until you pick a trip.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(places) { place in
                NavigationLink(value: place) {
                    SavedPlaceRow(place: place)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        moving = place
                    } label: {
                        Label("Move to a trip", systemImage: "suitcase.fill")
                            .labelStyle(.iconOnly)
                    }
                    .tint(Theme.teal)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation { context.delete(place) }
                        try? context.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.red)
                }
            }
        }
        .navigationTitle("Saved items")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Place.self) { place in
            PlaceDetailView(place: place)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog("Move \(moving?.name ?? "place") to…",
                            isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
                            titleVisibility: .visible) {
            ForEach(trips) { trip in
                Button(trip.name) {
                    if let moving {
                        withAnimation { moving.move(to: trip) }
                        try? context.save()
                        Toaster.shared.show("Moved to \(trip.name) · Saved items", systemImage: "suitcase.fill")
                    }
                    moving = nil
                }
            }
            Button("Cancel", role: .cancel) { moving = nil }
        } message: {
            Text(trips.isEmpty ? "Create a trip first." : "It goes into the trip's Saved items.")
        }
    }
}

private struct SavedPlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            // The shared post's preview picture; the pin icon until it loads (or if there's none).
            LinkThumbnail(url: place.sortedLinks.first?.url, size: 44) {
                Image(systemName: place.hasLocation ? "mappin.circle.fill" : "mappin.slash.circle.fill")
                    .font(.app(.title2))
                    .foregroundStyle(place.hasLocation ? Theme.teal : .orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if !place.hasLocation { Text("No location yet") }
                    else if !place.address.isEmpty { Text(place.address).lineLimit(1) }
                    if !place.links.isEmpty {
                        Label("\(place.links.count)", systemImage: "link")
                    }
                }
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            }
        }
    }
}
