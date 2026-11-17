import SwiftUI
import SwiftData

/// What to pack before departure: items grouped by kind, ticked off as they go in the bag.
struct PackingListView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate, order: .reverse) private var allTrips: [Trip]

    @State private var hidePacked = false
    @State private var adding: PackingCategory?
    @State private var editing: PackingItem?
    @State private var confirmClear = false

    /// Other trips that have a packing list to copy.
    private var copyableTrips: [Trip] {
        allTrips.filter { $0.persistentModelID != trip.persistentModelID && !$0.packingItems.isEmpty }
    }

    private func items(in category: PackingCategory) -> [PackingItem] {
        trip.packingItems
            .filter { $0.packingCategory == category && !(hidePacked && $0.isPacked) }
            .sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    var body: some View {
        List {
            Section {
                PackingProgressCard(trip: trip)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if trip.packingItems.isEmpty {
                startSection
            } else {
                ForEach(PackingCategory.allCases) { category in
                    let rows = items(in: category)
                    let total = trip.packingItems.filter { $0.packingCategory == category }
                    if !total.isEmpty {
                        Section {
                            ForEach(rows) { item in
                                PackingRow(item: item)
                                    .swipeActions {
                                        Button(role: .destructive) { context.delete(item) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button { editing = item } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Theme.blue)
                                    }
                            }
                            // Long-press a row and drag to reorder it (off while packed items are hidden).
                            .onMove { from, to in move(in: category, from: from, to: to) }
                            .moveDisabled(hidePacked)
                            Button {
                                adding = category
                            } label: {
                                Label("Add to \(category.rawValue)", systemImage: "plus")
                                    .font(.app(.subheadline))
                            }
                        } header: {
                            HStack {
                                Label(category.rawValue, systemImage: category.icon)
                                Spacer()
                                Text("\(total.filter(\.isPacked).count)/\(total.count)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                // Groups with nothing in them yet.
                let unused = PackingCategory.allCases.filter { c in !trip.packingItems.contains { $0.packingCategory == c } }
                if !unused.isEmpty {
                    Section {
                        ForEach(unused) { category in
                            Button {
                                adding = category
                            } label: {
                                Label("Add to \(category.rawValue)", systemImage: category.icon)
                                    .font(.app(.subheadline))
                            }
                        }
                    } header: {
                        Text("More groups")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: hidePacked)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { adding = .other } label: { Label("Add item", systemImage: "plus") }
                    if !trip.packingItems.isEmpty {
                        Toggle(isOn: $hidePacked) { Label("Hide packed", systemImage: "eye.slash") }
                        Button { uncheckAll() } label: {
                            Label("Untick all (pack for home)", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(trip.packedCount == 0)
                    }
                    Button { addStarterItems() } label: { Label("Add starter items", systemImage: "sparkles") }
                    if !copyableTrips.isEmpty {
                        Menu {
                            ForEach(copyableTrips) { other in
                                Button("\(other.name) (\(other.packingItems.count))") { copy(from: other) }
                            }
                        } label: {
                            Label("Copy from a trip", systemImage: "doc.on.doc")
                        }
                    }
                    if !trip.packingItems.isEmpty {
                        Divider()
                        Button(role: .destructive) { confirmClear = true } label: {
                            Label("Clear list", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $adding) { category in
            PackingItemForm(trip: trip, item: nil, category: category)
        }
        .sheet(item: $editing) { item in
            PackingItemForm(trip: trip, item: item, category: item.packingCategory)
        }
        .alert("Clear the packing list?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                for item in trip.packingItems { context.delete(item) }
            }
        } message: {
            Text("All \(trip.packingItems.count) items are removed from this trip.")
        }
    }

    private var startSection: some View {
        Section {
            Button { addStarterItems() } label: {
                Label("Start with a starter list", systemImage: "sparkles")
            }
            if !copyableTrips.isEmpty {
                Menu {
                    ForEach(copyableTrips) { other in
                        Button("\(other.name) (\(other.packingItems.count))") { copy(from: other) }
                    }
                } label: {
                    Label("Copy from another trip", systemImage: "doc.on.doc")
                }
            }
            Button { adding = .other } label: {
                Label("Add my own items", systemImage: "plus")
            }
        } header: {
            Text("Get started")
        } footer: {
            Text("The starter list has passport, chargers, adapter, medicine and more. Change or delete anything after.")
        }
    }

    private func addStarterItems() {
        let existing = Set(trip.packingItems.map { $0.name.lowercased() })
        var added = 0
        for category in PackingCategory.allCases {
            for (index, name) in category.starterItems.enumerated() where !existing.contains(name.lowercased()) {
                insert(PackingItem(name: name, category: category, order: 1000 + index))
                added += 1
            }
        }
        Toaster.shared.show(added == 0 ? "Starter items are already in" : "\(added) items added", systemImage: "suitcase.fill")
    }

    /// Copies another trip's list, unticked.
    private func copy(from other: Trip) {
        let existing = Set(trip.packingItems.map { $0.name.lowercased() })
        var added = 0
        for source in other.packingItems.sorted(by: { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) })
        where !existing.contains(source.name.lowercased()) {
            insert(PackingItem(name: source.name, category: source.packingCategory,
                               quantity: source.quantity, order: source.order))
            added += 1
        }
        Toaster.shared.show("\(added) items copied from \(other.name)", systemImage: "doc.on.doc.fill")
    }

    private func insert(_ item: PackingItem) {
        context.insert(item)
        item.trip = trip
    }

    /// Saves the new order of a group after a drag.
    private func move(in category: PackingCategory, from: IndexSet, to: Int) {
        var rows = items(in: category)
        rows.move(fromOffsets: from, toOffset: to)
        for (index, item) in rows.enumerated() { item.order = index }
        Haptics.tap()
    }

    private func uncheckAll() {
        for item in trip.packingItems { item.isPacked = false }
        Toaster.shared.show("All unticked", systemImage: "arrow.uturn.backward", style: .info)
    }
}

/// Countdown to departure and how much is packed.
struct PackingProgressCard: View {
    let trip: Trip

    private var total: Int { trip.packingItems.count }
    private var packed: Int { trip.packedCount }
    private var fraction: Double { total == 0 ? 0 : Double(packed) / Double(total) }

    private var countdown: String {
        if trip.isDraft { return "No dates yet" }
        let days = trip.daysUntilDeparture
        switch days {
        case ..<0: return "Trip has started"
        case 0: return "Departs today"
        case 1: return "Departs tomorrow"
        default: return "Departs in \(days) days"
        }
    }

    private var message: String {
        if total == 0 { return "Add what you need to bring." }
        if packed == total { return "All packed. Have a great trip!" }
        let left = total - packed
        return "\(left) item\(left == 1 ? "" : "s") left to pack"
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.teal.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(packed == total && total > 0 ? Color.green : Theme.teal,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: fraction)
                Image(systemName: packed == total && total > 0 ? "checkmark" : "suitcase.fill")
                    .font(.app(.title3, .bold))
                    .foregroundStyle(packed == total && total > 0 ? Color.green : Theme.teal)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(countdown)
                    .font(.app(.caption, .semibold))
                    .foregroundStyle(.secondary)
                Text(total == 0 ? "Packing list" : "\(packed) of \(total) packed")
                    .font(.app(.title3, .bold))
                Text(message)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassCard()
    }
}

/// One item: tap to tick it off.
private struct PackingRow: View {
    @Bindable var item: PackingItem

    var body: some View {
        Button {
            withAnimation(.snappy) { item.isPacked.toggle() }
            Haptics.tap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isPacked ? Theme.teal : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(item.name)
                    .strikethrough(item.isPacked)
                    .foregroundStyle(item.isPacked ? .secondary : .primary)
                Spacer()
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.app(.subheadline, .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Add or edit one packing item.
private struct PackingItemForm: View {
    let trip: Trip
    let item: PackingItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var category: PackingCategory
    @State private var quantity = 1
    @State private var addedCount = 0
    @FocusState private var focused: Bool

    init(trip: Trip, item: PackingItem?, category: PackingCategory) {
        self.trip = trip
        self.item = item
        _category = State(initialValue: category)
        _name = State(initialValue: item?.name ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item (e.g. Sunglasses)", text: $name)
                        .focused($focused)
                        .submitLabel(item == nil ? .next : .done)
                        .onSubmit { item == nil ? addAndContinue() : save() }
                    Stepper(value: $quantity, in: 1...30) {
                        LabeledContent("How many", value: "\(quantity)")
                    }
                    Picker("Group", selection: $category) {
                        ForEach(PackingCategory.allCases) { c in
                            Label(c.rawValue, systemImage: c.icon).tag(c)
                        }
                    }
                } footer: {
                    if item == nil {
                        Text(addedCount == 0
                             ? "Press return to add it and type the next one."
                             : "\(addedCount) added. Keep typing, or tap Done.")
                    }
                }
            }
            .navigationTitle(item == nil ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(item == nil && addedCount > 0 ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func write() {
        let target: PackingItem
        if let item {
            target = item
        } else {
            target = PackingItem(name: "", category: category,
                                 order: (trip.packingItems.map(\.order).max() ?? 0) + 1)
            context.insert(target)
            target.trip = trip
        }
        target.name = trimmed
        target.packingCategory = category
        target.quantity = quantity
    }

    /// Adds the item and clears the field for the next one.
    private func addAndContinue() {
        guard !trimmed.isEmpty else { return }
        write()
        addedCount += 1
        name = ""
        quantity = 1
        Haptics.tap()
        focused = true
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        write()
        dismiss()
    }
}
