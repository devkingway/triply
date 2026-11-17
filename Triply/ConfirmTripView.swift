import SwiftUI

/// Turns a draft trip into a planned trip by choosing its real start date.
struct ConfirmTripView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Calendar.current.startOfDay(for: .now)

    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: trip.dayCount - 1, to: startDate) ?? startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    LabeledContent("Ends", value: endDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    LabeledContent("Length", value: "\(trip.dayCount) day\(trip.dayCount == 1 ? "" : "s")")
                } footer: {
                    Text("Your day-by-day plan stays the same. Day 1 becomes \(startDate.formatted(.dateTime.weekday(.wide).day().month(.wide))). To change the number of days, use Edit.")
                }
            }
            .navigationTitle("Confirm \(trip.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        let days = trip.dayCount
        trip.startDate = startDate
        trip.endDate = Calendar.current.date(byAdding: .day, value: days - 1, to: startDate) ?? startDate
        trip.isDraft = false
        Toaster.shared.show("\(trip.name) confirmed ✈️", systemImage: "calendar.badge.checkmark")
        dismiss()
    }
}
