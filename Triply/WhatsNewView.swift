import SwiftUI

/// One app update: when it came out and what changed.
struct UpdateNote: Identifiable {
    struct Item: Identifiable {
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        var id: String { title }
    }

    /// Unique and increasing ("2026-11-15"); used to tell whether the user has seen it.
    let id: String
    let title: String
    let date: String
    let items: [Item]
}

enum UpdateNotes {
    /// Newest first. Add a new entry at the top for each update.
    static let all: [UpdateNote] = [
        UpdateNote(
            id: "2026-11-15",
            title: "Packing, tickets & more",
            date: "15 Nov 2026",
            items: [
                .init(icon: "point.bottomleft.forward.to.point.topright.scurvepath", tint: .teal,
                      title: "Multiple destinations",
                      detail: "Going to more than one place? Add each city or country to a trip, in the order you visit them."),
                .init(icon: "suitcase.fill", tint: Theme.teal,
                      title: "Packing list",
                      detail: "A packing list for each trip, at the top of More. Start from a starter list or copy another trip's, tick things off as they go in the bag, and long-press an item to drag it into place."),
                .init(icon: "square.grid.2x2.fill", tint: .indigo,
                      title: "New More tab",
                      detail: "Flights, hotels, tickets and the shared album now live together in the More tab, one tap away."),
                .init(icon: "ticket.fill", tint: ExpenseCategory.tickets.color,
                      title: "Tickets for places",
                      detail: "Add entry, show or train tickets to a place in your itinerary, with the time, venue, booking reference, split bill and your e-tickets or QR codes saved offline."),
                .init(icon: "rectangle.stack.badge.person.crop.fill", tint: .orange,
                      title: "Shared album",
                      detail: "Link an iCloud Shared Album to a trip and see everyone's photos in Triply."),
                .init(icon: "airplane.departure", tint: .blue,
                      title: "Connecting flights",
                      detail: "Add a connecting flight in one tap. The layover shows between flights, in orange when it's under an hour."),
                .init(icon: "person.2.fill", tint: .purple,
                      title: "Split flights & pay for nothing",
                      detail: "Split a flight between passengers like hotels. You can now choose to pay for 0 when someone else covered it."),
                .init(icon: "chart.pie.fill", tint: .green,
                      title: "Cleaner expenses summary",
                      detail: "Tax back and items bought for friends moved to their own card. Swipe the summary to see them, with how much friends have paid you back."),
            ]
        ),
    ]

    static var latestID: String { all.first?.id ?? "" }
}

/// The update notes, newest first.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(UpdateNotes.all.enumerated()), id: \.element.id) { index, note in
                        section(note, isLatest: index == 0)
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ note: UpdateNote, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(note.date)
                        .font(.app(.caption, .semibold))
                        .foregroundStyle(.secondary)
                    if isLatest {
                        Text("LATEST")
                            .font(.app(.caption2, .heavy))
                            .foregroundStyle(Theme.teal)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.teal.opacity(0.15), in: Capsule())
                    }
                }
                Text(note.title)
                    .font(.poppins(size: 24, weight: .bold))
            }
            VStack(spacing: 0) {
                ForEach(Array(note.items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < note.items.count - 1 {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func row(_ item: UpdateNote.Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.icon)
                .font(.app(.subheadline, .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(item.tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.app(.headline))
                Text(item.detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
