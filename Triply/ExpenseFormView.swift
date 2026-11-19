import SwiftUI
import SwiftData

struct ExpenseFormView: View {
    let trip: Trip
    var expense: Expense?
    /// Pre-filled description for a new expense (e.g. the place it was spent at).
    var prefillTitle: String = ""
    /// Category for a new expense (e.g. Tickets when added from the Booking tab).
    var prefillCategory: ExpenseCategory? = nil
    /// Open as a copy of `expense`: Save adds a new expense and leaves the original as it is.
    var startAsCopy = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var amount: Double?
    @State private var currency = "MYR"
    @State private var rate: Double = 1
    @State private var rateStatus: RateStatus = .ready
    @State private var category: ExpenseCategory = .food
    @State private var date = Date.now
    @State private var notes = ""
    @State private var loaded = false
    /// Copying: the form is filled from `expense`, but Save creates a new one.
    @State private var isCopy = false
    // Optional tax refund (e.g. tax-free shopping): a percentage or a fixed amount.
    @State private var claimTax = false
    @State private var taxType: TaxType = .percent
    @State private var taxValue: Double? = 10

    /// `items` copies the items' tax deductions; it's saved as an amount.
    enum TaxType: String, CaseIterable { case percent, amount, items }

    // Optional discount on the whole bill: a percentage, an amount, or copied from the items.
    // The amount above is the price before discount; the list and budget use the price after it.
    @State private var giveDiscount = false
    @State private var discountType: TaxType = .percent
    @State private var discountValue: Double?

    // Bought on behalf of a friend: recorded, but not counted in your spending.
    @State private var forSomeoneElse = false
    @State private var friendName = ""
    @State private var isRepaid = false
    @FocusState private var amountFocused: Bool
    // Split bill: how many people share it, and how many portions you pay.
    @State private var sharedBy = 1
    @State private var paidPortions = 1
    /// Or split by your percentage / exact amount, for bills that don't divide evenly.
    @State private var splitMode: SplitMode = .people
    /// Receipt lines, for your records only (they don't change the amount or budget).
    @State private var lineItems: [ExpenseLineItem] = []
    @State private var editingItem: ExpenseLineItem?
    /// How every item's discount and tax deduction are worked out (one choice for the whole receipt).
    @State private var itemsFormula: LineItemFormula = .discountFirst
    /// Tax charged on every item (one choice for the whole receipt). Recorded only.
    @State private var itemsTaxKind: ItemTaxKind = .none
    @State private var itemsTaxRate: Double?
    @State private var itemsTaxIncluded = true
    @State private var shareValue: Double?
    /// "Split the bill" switch: the split options only show when it's on.
    @State private var splitOn = false

    enum RateStatus { case ready, loading, unavailable }

    /// The discount in the bill's currency.
    private var discountAmount: Double {
        guard giveDiscount else { return 0 }
        let gross = amount ?? 0
        switch discountType {
        case .percent: return gross * min(max(discountValue ?? 0, 0), 100) / 100
        case .amount: return min(max(discountValue ?? 0, 0), gross)
        case .items: return min(itemsDiscount, gross)
        }
    }
    /// The bill after discount: what was actually paid.
    private var netAmount: Double { max((amount ?? 0) - discountAmount, 0) }
    /// The bill after discount, in MYR.
    private var amountMYR: Double { netAmount * rate }
    /// Your part of the bill (1 when not shared).
    private var shareFraction: Double {
        // Percent / amount with nothing entered yet counts as the whole bill.
        if splitMode != .people, (shareValue ?? 0) <= 0 { return 1 }
        return SplitMode.fraction(mode: splitMode, sharedBy: sharedBy, paidPortions: paidPortions,
                                  shareValue: shareValue ?? 0, billAmount: netAmount)
    }
    private var isSplitting: Bool { shareFraction < 1 }
    private var myShareMYR: Double { amountMYR * shareFraction }
    /// Hotel and flight expenses are split on their own forms.
    private var isLinked: Bool { !isCopy && (expense?.linkedHotel != nil || expense?.linkedFlight != nil || expense?.linkedTicket != nil) }
    /// The expense Save updates; `nil` adds a new one (new expense or a copy).
    private var target: Expense? { isCopy ? nil : expense }

    /// Flights and Hotel are left out: those costs come from the Flights and Hotels tabs.
    /// (An older expense already saved as Flights/Hotel keeps its category so it isn't changed by accident.)
    private var selectableCategories: [ExpenseCategory] {
        ExpenseCategory.allCases.filter { ($0 != .flight && $0 != .hotel) || $0 == expense?.category }
    }

    /// Tax coming back on this item, in MYR (same maths as Expense.taxRefundMYR).
    private var taxBackMYR: Double {
        guard claimTax else { return 0 }
        if taxType == .items { return min(itemsTax, netAmount) * rate * shareFraction }
        guard let taxValue, taxValue > 0 else { return 0 }
        switch taxType {
        case .percent: return myShareMYR * min(taxValue, 100) / 100
        case .amount: return min(taxValue, netAmount) * rate * shareFraction
        case .items: return min(itemsTax, netAmount) * rate * shareFraction
        }
    }

    /// e.g. "¥1,200 (≈ RM 30.68)", or just "RM 30.68" for a ringgit expense.
    private func inBoth(_ valueMYR: Double) -> String {
        guard currency != "MYR", rate > 0 else { return valueMYR.myr }
        return "\((valueMYR / rate).money(currency)) (≈ \(valueMYR.myr))"
    }

    /// Discount on the whole bill: a % or amount, or copied from the items' discounts.
    private var discountSection: some View {
        Section {
            Toggle(isOn: $giveDiscount.animation()) {
                Label("Discount", systemImage: "tag.fill")
            }
            .tint(.green)
            if giveDiscount {
                Picker("Discount as", selection: $discountType) {
                    Text("Percent").tag(TaxType.percent)
                    Text("Amount").tag(TaxType.amount)
                    // Shown once an item has a discount.
                    if itemsDiscount > 0 { Text("From items").tag(TaxType.items) }
                }
                .pickerStyle(.segmented)
                if discountType == .items {
                    LabeledContent("Items' discount") {
                        Text(itemsDiscount.money(currency)).fontWeight(.semibold)
                    }
                } else {
                    HStack {
                        Text(discountType == .percent ? "%" : currency)
                            .foregroundStyle(.secondary)
                        TextField(discountType == .percent ? "10" : "0", value: $discountValue, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                    }
                }
            }
        } header: {
            Text("Discount (optional)")
        } footer: {
            if giveDiscount, discountAmount > 0 {
                Text("\(discountAmount.money(currency)) off · you paid \(netAmount.money(currency))\(currency != "MYR" ? " (≈ \(amountMYR.myr))" : ""). The list and budget use the price after discount.")
                    .foregroundStyle(.green)
            } else {
                Text("Enter the price before discount at the top, then the discount here (a percentage, an amount, or the items' discounts).")
            }
        }
    }

    /// Keeps the discount valid when the items' discounts change.
    private func itemsDiscountChanged() {
        if discountType == .items && itemsDiscount <= 0 { discountType = .amount }
    }

    /// The items' discounts added up in the bill's currency.
    private var itemsDiscount: Double { lineItems.reduce(0) { $0 + $1.discountInBill(currency: currency, rate: rate) } }


    /// Split the bill, bought for someone else, discount and tax refund (shown on the Additional features page).
    @ViewBuilder private var additionalFeatureSections: some View {
        if !isLinked {
            Section {
                Toggle(isOn: Binding(
                    get: { splitOn },
                    set: { on in
                        withAnimation { splitOn = on }
                        // Off: back to just you paying the whole bill.
                        if !on {
                            sharedBy = 1
                            paidPortions = 1
                            splitMode = .people
                            shareValue = nil
                        } else if sharedBy == 1 && splitMode == .people {
                            sharedBy = 2
                        }
                    }
                )) {
                    Label("Split the bill", systemImage: "person.3.fill")
                }
                .tint(Theme.teal)
                if splitOn {
                    Picker("Split by", selection: $splitMode.animation()) {
                        ForEach(SplitMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)

                    switch splitMode {
                    case .people:
                        Stepper(value: $sharedBy, in: 1...30) {
                            LabeledContent("People sharing", value: sharedBy == 1 ? "Just me" : "\(sharedBy) people")
                        }
                        if sharedBy > 1 {
                            Picker("I pay for", selection: $paidPortions) {
                                ForEach(0...sharedBy, id: \.self) { n in
                                    Text(n == 0 ? "Nothing (0)" : n == 1 ? "Just me (1)" : n == sharedBy ? "Everyone (\(n))" : "\(n) people").tag(n)
                                }
                            }
                        }
                    case .percent:
                        HStack {
                            Text("My share")
                            Spacer()
                            TextField("40", value: $shareValue, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text("%").foregroundStyle(.secondary)
                        }
                    case .amount:
                        HStack {
                            Text("My share")
                            Spacer()
                            Text(currency).foregroundStyle(.secondary)
                            TextField("0", value: $shareValue, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                        }
                    }
                }
            } footer: {
                if splitOn {
                    splitFooter
                } else {
                    Text("Sharing a meal or a taxi? Turn on to split it by people, percent or exact amount.")
                }
            }
        }

        Section {
            Toggle(isOn: $forSomeoneElse.animation()) {
                Label("Bought for someone else", systemImage: "person.2.fill")
            }
            .tint(.orange)
            if forSomeoneElse {
                TextField("Who is it for? (e.g. Ali)", text: $friendName)
                    .textInputAutocapitalization(.words)
            }
        } header: {
            Text("Who is it for?")
        } footer: {
            if forSomeoneElse {
                Text(isRepaid
                     ? "Paid back, so it's no longer counted in your spending."
                     : "Counted in your spending until they pay you back. Then switch on Paid me back on the expense.")
                    .foregroundStyle(isRepaid ? .green : .orange)
            } else {
                Text("Turn on if you paid for a friend's item. It counts until they pay you back.")
            }
        }

        discountSection

        taxRefundSection
    }

    /// The additional features switched on for this expense, e.g. ["Split", "Discount"].
    private var activeFeatures: [String] {
        var list: [String] = []
        if !isLinked && splitOn { list.append(isSplitting ? "Split · your \(myShareMYR.myr)" : "Split") }
        if forSomeoneElse { list.append(friendName.trimmingCharacters(in: .whitespaces).isEmpty ? "For someone else" : "For \(friendName.trimmingCharacters(in: .whitespaces))") }
        if giveDiscount { list.append("Discount") }
        if claimTax { list.append("Tax refund") }
        return list
    }

    private var additionalFeaturesSummary: String {
        guard activeFeatures.isEmpty else { return activeFeatures.joined(separator: " · ") }
        return isLinked ? "Bought for someone else, discount, tax refund"
                        : "Split the bill, bought for someone else, discount, tax refund"
    }

    /// Tax refund: a % or amount, or copied from the items' tax deductions.
    private var taxRefundSection: some View {
            Section {
                Toggle(isOn: $claimTax.animation()) {
                    Label("Tax refund", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .tint(.green)
                if claimTax {
                    Picker("Refund as", selection: $taxType) {
                        Text("Percent").tag(TaxType.percent)
                        Text("Amount").tag(TaxType.amount)
                        // Shown once an item has a tax deduction.
                        if itemsTax > 0 { Text("From items").tag(TaxType.items) }
                    }
                    .pickerStyle(.segmented)
                    if taxType == .items {
                        LabeledContent("Items' tax deduction") {
                            Text(itemsTax.money(currency)).fontWeight(.semibold)
                        }
                    } else {
                        HStack {
                            Text(taxType == .percent ? "%" : currency)
                                .foregroundStyle(.secondary)
                            TextField(taxType == .percent ? "10" : "0", value: $taxValue, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                        }
                    }
                }
            } header: {
                Text("Tax refund (optional)")
            } footer: {
                if claimTax, taxBackMYR > 0 {
                    // In the expense's own currency (e.g. JPY) as well as RM.
                    Text("You get back \(inBoth(taxBackMYR)) · this item really costs \(inBoth(myShareMYR - taxBackMYR))")
                        .foregroundStyle(.green)
                } else {
                    Text("For tax-free shopping or VAT/GST refunds. Enter a percentage (e.g. 10%) or the amount on your refund slip.")
                }
            }
    }

    /// Keeps the tax refund valid when the items' tax deductions change.
    private func itemsTaxChanged() {
        if taxType == .items && itemsTax <= 0 { taxType = .amount }
    }

    /// The items' tax deductions added up in the bill's currency.
    private var itemsTax: Double { lineItems.reduce(0) { $0 + $1.taxInBill(currency: currency, rate: rate) } }

    /// The items' totals before tax deduction, in the bill's currency (what the bill should say).
    private var itemsBeforeTax: Double { lineItems.reduce(0) { $0 + $1.beforeTaxInBill(currency: currency, rate: rate) } }

    /// All items added up in the bill's currency (items in other currencies converted).
    private var itemsTotal: Double { lineItems.reduce(0) { $0 + $1.totalInBill(currency: currency, rate: rate) } }
    private var hasOtherCurrencies: Bool { lineItems.contains { $0.currencyCode(bill: currency) != currency } }

    /// Receipt items: each line with its total, and how the items add up against the bill.
    private var itemsSection: some View {
        Section {
            Picker("Tax type", selection: Binding(
                get: { itemsTaxKind },
                set: { kind in
                    itemsTaxKind = kind
                    // Fill in the usual rate (e.g. 8% reduced in Japan).
                    if let usual = kind.usualRate(for: currency) { itemsTaxRate = usual }
                    applyItemsTax()
                }
            )) {
                ForEach(ItemTaxKind.allCases) { Text($0.label).tag($0) }
            }
            if itemsTaxKind.isCharged {
                HStack {
                    Text("Tax rate")
                    Spacer()
                    TextField("10", value: Binding(
                        get: { itemsTaxRate },
                        set: { itemsTaxRate = $0; applyItemsTax() }
                    ), format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                    Text("%").foregroundStyle(.secondary)
                }
                Picker("Prices", selection: Binding(
                    get: { itemsTaxIncluded },
                    set: { itemsTaxIncluded = $0; applyItemsTax() }
                )) {
                    Text("Include tax").tag(true)
                    Text("Tax on top").tag(false)
                }
                .pickerStyle(.segmented)
            }
            ForEach(lineItems) { item in
                Button { editingItem = item } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "Item" : item.name)
                                .foregroundStyle(.primary)
                            if item.tax != 0 || item.discount != 0 || item.count > 1 || item.currencyCode(bill: currency) != currency {
                                Text(lineBreakdown(item))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            if let taxLine = chargedTaxLine(item) {
                                HStack(spacing: 4) {
                                    Image(systemName: "percent")
                                    Text(taxLine)
                                }
                                .font(.app(.caption, .medium))
                                .foregroundStyle(Theme.teal)
                            }
                        }
                        Spacer()
                        Text(item.total.money(item.currencyCode(bill: currency)))
                            .foregroundStyle(.primary)
                    }
                }
                // Normal text colours rather than the button tint.
                .tint(.primary)
            }
            .onDelete { lineItems.remove(atOffsets: $0) }
            Button {
                var newItem = ExpenseLineItem()
                newItem.formula = itemsFormula
                applyItemsTax(to: &newItem)
                editingItem = newItem
            } label: {
                Label("Add item", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Items (optional)")
        } footer: {
            if lineItems.isEmpty {
                Text("Add each item from the receipt to check it against the bill. For your records only; it doesn't change the amount or budget.")
            } else {
                let difference = itemsBeforeTax - netAmount
                VStack(alignment: .leading, spacing: 2) {
                    Text("Items \(hasOtherCurrencies ? "≈ " : "")\(itemsBeforeTax.money(currency))\(itemsTax > 0 ? " before tax deduction" : "") · bill\(discountAmount > 0 ? " after discount" : "") \(netAmount.money(currency))")
                    // Converted totals can be off by rounding, so allow a little slack then.
                    if abs(difference) < (hasOtherCurrencies ? max(0.01, netAmount * 0.005) : 0.005) {
                        Label("Matches the bill", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(abs(difference).money(currency)) \(difference > 0 ? "more" : "less") than the bill")
                            .foregroundStyle(.orange)
                    }
                    receiptTaxSummary
                }
            }
        }
    }

    /// Sets the receipt's tax type, rate and included/on top on every item.
    private func applyItemsTax() {
        for index in lineItems.indices { applyItemsTax(to: &lineItems[index]) }
    }

    private func applyItemsTax(to item: inout ExpenseLineItem) {
        item.chargedTaxKind = itemsTaxKind
        item.chargedTax = itemsTaxKind.isCharged ? itemsTaxRate : nil
        item.chargedTaxIsPercent = itemsTaxKind.isCharged ? true : nil
        item.chargedTaxIncluded = itemsTaxKind.isCharged ? itemsTaxIncluded : nil
    }

    /// e.g. "Reduced 8% · incl. ¥36 tax", "Tax-free".
    private func chargedTaxLine(_ item: ExpenseLineItem) -> String? {
        let code = item.currencyCode(bill: currency)
        switch item.chargedTaxKind {
        case .none: return nil
        case .taxFree, .exempt: return item.chargedTaxKind.label
        case .standard, .reduced:
            guard let rate = item.chargedTaxRateText(bill: currency) else { return item.chargedTaxKind.label }
            let kind = item.chargedTaxKind == .reduced ? "Reduced" : "Standard"
            let how = item.chargedTaxIsPercent == false || item.chargedTaxIncluded != false ? "incl." : "+"
            return "\(kind) \(rate) · \(how) \(item.chargedTaxValue.money(code)) tax"
        }
    }

    /// The tax on the receipt, like the bottom of a real one: tax charged by rate, and the tax deduction.
    @ViewBuilder private var receiptTaxSummary: some View {
        let charged = lineItems.filter { $0.chargedTaxValue > 0 }
        let chargedTotal = charged.reduce(0) { $0 + $1.chargedTaxInBill(currency: currency, rate: rate) }
        if chargedTotal > 0 || itemsTax > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if chargedTotal > 0 {
                    // Grouped by rate, e.g. "10%: ¥200 · 8%: ¥36".
                    let groups = Dictionary(grouping: charged) { $0.chargedTaxRateText(bill: currency).map { $0.hasSuffix("%") ? $0 : "Fixed" } ?? "Fixed" }
                        .map { (label: $0.key, total: $0.value.reduce(0) { $0 + $1.chargedTaxInBill(currency: currency, rate: rate) }) }
                        .sorted { $0.total > $1.total }
                    Text("Tax charged \(hasOtherCurrencies ? "≈ " : "")\(chargedTotal.money(currency))")
                        .fontWeight(.semibold)
                    if groups.count > 1 || groups.first?.label == "Fixed" {
                        Text(groups.map { "\($0.label): \($0.total.money(currency))" }.joined(separator: " · "))
                    } else if let only = groups.first {
                        Text("All at \(only.label)")
                    }
                }
                if itemsTax > 0 {
                    Text("Tax deduction \(hasOtherCurrencies ? "≈ " : "")\(itemsTax.money(currency))")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
            .padding(.top, 6)
        }
    }

    /// e.g. "2 × ¥1,000 − 10% off (¥200) − tax deduction 8% (¥144)".
    private func lineBreakdown(_ item: ExpenseLineItem) -> String {
        let code = item.currencyCode(bill: currency)
        var text = item.count > 1 ? "\(item.count) × \(item.amount.money(code))" : item.amount.money(code)
        var discountPart = ""
        if item.discountValue != 0 {
            discountPart = item.discountIsPercent == true
                ? " − \(percentText(item.discount)) off (\(item.discountValue.money(code)))"
                : " − \(item.discountValue.money(code)) off"
        }
        var taxPart = ""
        if item.taxValue != 0 {
            taxPart = item.taxIsPercent == true
                ? " − tax deduction \(percentText(item.tax)) (\(item.taxValue.money(code)))"
                : " − tax deduction \(item.taxValue.money(code))"
        }
        // Same order as the formula: tax deduction first for formula 2.
        text += item.formula == .taxFirst ? taxPart + discountPart : discountPart + taxPart
        return text
    }

    private func percentText(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2))))%"
    }

    /// Explains your share for the chosen split.
    @ViewBuilder private var splitFooter: some View {
        let others = amountMYR - myShareMYR
        switch splitMode {
        case .people:
            if sharedBy > 1 {
                if paidPortions == 0 {
                    Text("You pay nothing: someone else paid. It stays in the list at RM 0.00.")
                } else if amount != nil {
                    Text("You pay \(min(paidPortions, sharedBy)) of \(sharedBy) portions: ≈ \(myShareMYR.myr) of \(amountMYR.myr). Only your part goes in the budget.")
                } else {
                    Text("Enter the whole bill above. Only your part goes in the budget.")
                }
            } else {
                Text("Sharing a meal or a taxi? Add how many people split it, or split by percent or exact amount.")
            }
        case .percent:
            if let value = shareValue, value > 100 {
                Text("Your share can't be more than 100%.").foregroundStyle(.red)
            } else if (shareValue ?? 0) > 0, amount != nil {
                Text("You pay ≈ \(myShareMYR.myr) of \(amountMYR.myr); the others pay \(others.myr). Only your part goes in the budget.")
            } else {
                Text("Enter the whole bill above and the percentage you pay.")
            }
        case .amount:
            if let value = shareValue, let amount, value > amount {
                Text("Your share is more than the bill.").foregroundStyle(.red)
            } else if (shareValue ?? 0) > 0, amount != nil {
                Text("You pay \(myShareMYR.myr) of \(amountMYR.myr); the others pay \(others.myr). Only your part goes in the budget.")
            } else {
                Text("Enter the whole bill above and exactly how much you pay, for bills that don't split evenly.")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        // Category beside the name: tap the icon to change it.
                        Menu {
                            Picker("Category", selection: $category) {
                                ForEach(selectableCategories) { cat in
                                    Label(cat.name, systemImage: cat.systemImage).tag(cat)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.systemImage)
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(category.color.gradient))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                        .accessibilityLabel("Category: \(category.name)")
                        Divider().frame(height: 30)
                        TextField("What was it? (e.g. Ichiran ramen)", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Menu {
                            Picker("Currency", selection: $currency) {
                                ForEach(currencyOptions, id: \.self) { code in
                                    Text(Currencies.label(code)).tag(code)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(currency).font(.app(.title3, .bold))
                                Image(systemName: "chevron.up.chevron.down").font(.app(.caption))
                            }
                        }
                        TextField("0", value: $amount, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .font(.app(.largeTitle, .bold))
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                        // Duplicate: opens a copy of this expense; Save adds it as a new one.
                        // Only for a saved expense of your own (not a hotel, flight or ticket booking).
                        if let expense = target, expense.linkedHotel == nil, expense.linkedFlight == nil, expense.linkedTicket == nil {
                            Button {
                                withAnimation { isCopy = true }
                                amountFocused = false
                                Haptics.tap()
                                Toaster.shared.show("Copy ready · change anything, then Save", systemImage: "plus.square.on.square", style: .info)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.app(.title3))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Duplicate expense")
                        }
                    }
                    if currency != "MYR" {
                        rateRow
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        // The final amount once a discount or tax back is applied.
                        if amount != nil, discountAmount > 0 || taxBackMYR > 0 {
                            Text("Final\(isSplitting ? " (your share)" : "") \(inBoth(max(myShareMYR - taxBackMYR, 0)))")
                                .font(.app(.headline))
                                .foregroundStyle(.green)
                            Text([discountAmount > 0 ? "after \(discountAmount.money(currency)) discount" : nil,
                                  taxBackMYR > 0 ? "\(inBoth(taxBackMYR)) tax back" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }


                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }

                itemsSection

                // Split the bill, bought for someone else, discount and tax refund, on their own page.
                Section {
                    NavigationLink {
                        Form { additionalFeatureSections }
                            .navigationTitle("Additional features")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.app(.subheadline, .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.teal.gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Additional features")
                                Text(additionalFeaturesSummary)
                                    .font(.app(.caption))
                                    .foregroundStyle(activeFeatures.isEmpty ? Color.secondary : Theme.teal)
                                    .lineLimit(2)
                            }
                        }
                    }
                    // Bought for someone else: tick it off here when they pay you back.
                    if forSomeoneElse {
                        Toggle(isOn: $isRepaid.animation()) {
                            Label {
                                let who = friendName.trimmingCharacters(in: .whitespaces)
                                Text(who.isEmpty ? "Paid me back" : "\(who) paid me back")
                            } icon: {
                                Image(systemName: isRepaid ? "checkmark.circle.fill" : "person.crop.circle.badge.clock")
                                    .foregroundStyle(isRepaid ? Color.green : Color.orange)
                            }
                        }
                        .tint(.green)
                    }
                } footer: {
                    if forSomeoneElse {
                        Text(isRepaid
                             ? "Paid back, so it's no longer counted in your spending."
                             : "Counted in your spending until they pay you back.")
                            .foregroundStyle(isRepaid ? .green : .orange)
                    }
                }

                if let hotel = target?.hotel {
                    Section {
                        Label("From your hotel booking “\(hotel.name)”. Changing the price in Hotels updates this expense.", systemImage: "bed.double.fill")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                if let ticket = target?.linkedTicket {
                    Section {
                        Label("From your ticket “\(ticket.name)”. Changing the price in Booking → Tickets updates this expense.", systemImage: "ticket.fill")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                if let flight = target?.linkedFlight {
                    Section {
                        Label("From your flight \(flight.fromCode) → \(flight.toCode). Changing the price in Flights updates this expense.", systemImage: "airplane")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                if target != nil {
                    Section {
                        Button("Delete expense", role: .destructive) {
                            if let expense { context.delete(expense) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isCopy ? "Duplicate expense" : expense == nil ? "Add expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled((amount ?? 0) <= 0 || rate <= 0)
                }
            }
            .onAppear(perform: load)
            .onChange(of: itemsTax) { _, _ in itemsTaxChanged() }
            .onChange(of: itemsDiscount) { _, _ in itemsDiscountChanged() }
            .sheet(item: $editingItem) { item in
                LineItemEditor(item: item, billCurrency: currency, currencyOptions: currencyOptions,
                               isNew: !lineItems.contains { $0.id == item.id }) { saved in
                    var saved = saved
                    saved.formula = itemsFormula
                    applyItemsTax(to: &saved)
                    if let index = lineItems.firstIndex(where: { $0.id == saved.id }) {
                        lineItems[index] = saved
                    } else {
                        lineItems.append(saved)
                    }
                } onDelete: {
                    lineItems.removeAll { $0.id == item.id }
                }
            }
            .onChange(of: sharedBy) { _, newValue in
                paidPortions = min(paidPortions, newValue)
            }
            .onChange(of: splitMode) { old, new in
                // Carry an equal split over as a starting point (e.g. 1 of 3 → 33.33% or a third of the bill).
                guard old == .people, sharedBy > 1, shareValue == nil else {
                    if old != .people, new != .people { shareValue = nil }
                    return
                }
                let fraction = Double(min(paidPortions, sharedBy)) / Double(sharedBy)
                switch new {
                case .percent: shareValue = (fraction * 10_000).rounded() / 100
                case .amount: if let amount { shareValue = (amount * fraction * 100).rounded() / 100 }
                case .people: break
                }
            }
            .task(id: currency) {
                // Keep the stored rate when opening an existing expense; refresh when the currency changes.
                // A copy keeps the original rate too.
                if let expense, expense.currency == currency, expense.rateToMYR > 0 { return }
                await fetchRate()
            }
        }
    }

    private var currencyOptions: [String] {
        var list = Currencies.common
        for code in [trip.localCurrency, currency] where !list.contains(code) { list.append(code) }
        return list
    }

    private var rateRow: some View {
        HStack {
            Text("1 \(currency) = RM")
                .foregroundStyle(.secondary)
            TextField("rate", value: $rate, format: .number.precision(.significantDigits(1...6)))
                .keyboardType(.decimalPad)
                // As wide as the number, so the refresh button sits right after it.
                .fixedSize()
            switch rateStatus {
            case .loading:
                ProgressView()
            case .unavailable:
                Label("Enter rate", systemImage: "wifi.slash")
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
            case .ready:
                Button {
                    Task { await fetchRate() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            Spacer(minLength: 8)
            // The bill converted to RM, on the same row as the rate.
            if let amount {
                Text("≈ \((amount * rate).myr)")
                    .font(.app(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.app(.subheadline))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        isCopy = startAsCopy
        if let expense {
            title = expense.title
            amount = expense.amount
            currency = expense.currency
            rate = expense.rateToMYR
            category = expense.category
            date = expense.date
            notes = expense.notes
            if let name = expense.paidForName {
                forSomeoneElse = true
                friendName = name
                isRepaid = expense.isRepaid
            }
            sharedBy = max(expense.sharedBy, 1)
            paidPortions = expense.myPortions
            splitMode = expense.splitMode
            lineItems = expense.lineItems
            itemsFormula = lineItems.first?.formula ?? .discountFirst
            if let first = lineItems.first {
                itemsTaxKind = first.chargedTaxKind
                itemsTaxRate = first.chargedTax
                itemsTaxIncluded = first.chargedTaxIncluded ?? true
            }
            shareValue = expense.myShareValue > 0 ? expense.myShareValue : nil
            splitOn = expense.sharedBy > 1 || expense.splitMode != .people
            if let type = expense.taxRefundType.flatMap(TaxType.init(rawValue:)), expense.taxRefundValue > 0 {
                claimTax = true
                taxType = type
                taxValue = expense.taxRefundValue
                // An amount that matches the items' tax deductions was copied from them.
                if type == .amount, itemsTax > 0, abs(itemsTax - expense.taxRefundValue) < 0.005 { taxType = .items }
            }
            if let type = expense.discountType.flatMap(TaxType.init(rawValue:)), expense.discountValue > 0 {
                giveDiscount = true
                discountType = type
                discountValue = expense.discountValue
                // An amount that matches the items' discounts was copied from them.
                if type == .amount, itemsDiscount > 0, abs(itemsDiscount - expense.discountValue) < 0.005 { discountType = .items }
            }
        } else {
            currency = trip.localCurrency
            title = prefillTitle
            if let prefillCategory { category = prefillCategory }
            let cal = Calendar.current
            let start = cal.startOfDay(for: trip.startDate)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.endDate))!
            date = (start..<end).contains(.now) ? .now : trip.startDate
            amountFocused = true
        }
    }

    private func fetchRate() async {
        if currency == "MYR" { rate = 1; rateStatus = .ready; return }
        rateStatus = .loading
        if let value = await ExchangeRates.rateToMYR(currency) {
            rate = value
            rateStatus = .ready
        } else {
            rateStatus = .unavailable
        }
    }

    private func applyFriend(to expense: Expense) {
        if forSomeoneElse {
            expense.paidForName = friendName.trimmingCharacters(in: .whitespaces)
            if expense.isRepaid != isRepaid { expense.setRepaid(isRepaid) }
        } else {
            expense.paidForName = nil
            expense.setRepaid(false)
        }
    }

    private func applySplit(to expense: Expense) {
        guard !isLinked else { return }
        expense.sharedBy = sharedBy
        expense.paidPortions = min(paidPortions, sharedBy)
        if splitMode != .people, let value = shareValue, value > 0 {
            expense.splitMode = splitMode
            // Keep it within the bill (100% / the whole amount).
            expense.myShareValue = splitMode == .percent ? min(value, 100) : min(value, netAmount > 0 ? netAmount : value)
        } else {
            // Percent / amount left empty: an equal split (or just you).
            expense.splitMode = .people
            expense.myShareValue = 0
        }
    }

    private func applyDiscount(to expense: Expense) {
        if giveDiscount, discountType == .items, itemsDiscount > 0 {
            // Copied from the items: stored as an amount in the bill's currency.
            expense.discountType = TaxType.amount.rawValue
            expense.discountValue = (itemsDiscount * 100).rounded() / 100
        } else if giveDiscount, discountType != .items, let discountValue, discountValue > 0 {
            expense.discountType = discountType.rawValue
            expense.discountValue = discountType == .percent ? min(discountValue, 100) : discountValue
        } else {
            expense.discountType = nil
            expense.discountValue = 0
        }
    }

    private func applyTax(to expense: Expense) {
        if claimTax, taxType == .items, itemsTax > 0 {
            // Copied from the items: stored as an amount in the bill's currency.
            expense.taxRefundType = TaxType.amount.rawValue
            expense.taxRefundValue = (itemsTax * 100).rounded() / 100
        } else if claimTax, taxType != .items, let taxValue, taxValue > 0 {
            expense.taxRefundType = taxType.rawValue
            expense.taxRefundValue = taxValue
        } else {
            expense.taxRefundType = nil
            expense.taxRefundValue = 0
        }
    }

    private func save() {
        guard let amount, amount > 0 else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let expense = target {
            expense.title = trimmed
            expense.amount = amount
            expense.currency = currency
            expense.rateToMYR = rate
            expense.category = category
            expense.date = date
            expense.notes = notes
            applyDiscount(to: expense)
            applyTax(to: expense)
            applyFriend(to: expense)
            applySplit(to: expense)
            expense.lineItems = lineItems
        } else {
            let new = Expense(title: trimmed, amount: amount, currency: currency, rateToMYR: rate, category: category, date: date, notes: notes)
            context.insert(new)
            new.trip = trip
            applyDiscount(to: new)
            applyTax(to: new)
            applyFriend(to: new)
            applySplit(to: new)
            new.lineItems = lineItems
        }
        if isCopy {
            Toaster.shared.show("Copy saved · \((isSplitting ? myShareMYR : amount * rate).myr)", systemImage: "plus.square.on.square")
        } else if forSomeoneElse {
            let who = friendName.trimmingCharacters(in: .whitespaces)
            let name = who.isEmpty ? "someone else" : who
            Toaster.shared.show(isRepaid ? "Saved for \(name) · paid back, not counted"
                                         : "Saved for \(name) · counted until paid back",
                                systemImage: "person.2.fill", style: .info)
        } else if trip.budget > 0, trip.remaining < 0 {
            Toaster.shared.show("Over budget by \((-trip.remaining).myr)", systemImage: "exclamationmark.triangle.fill", style: .warning)
        } else {
            Toaster.shared.show(taxBackMYR > 0
                                ? "Expense saved · \(taxBackMYR.myr) tax back"
                                : isSplitting
                                ? "Expense saved · your share \(myShareMYR.myr)"
                                : "Expense saved · \((amount * rate).myr)",
                                systemImage: "banknote.fill")
        }
        dismiss()
    }
}

/// Add or edit one receipt line: name, price, tax and discount, with the total worked out.
private struct LineItemEditor: View {
    @State var item: ExpenseLineItem
    /// The expense's currency (the default for items).
    let billCurrency: String
    let currencyOptions: [String]
    let isNew: Bool
    @State private var rateMissing = false
    @State private var checkedRate = false

    private var currency: String { item.currencyCode(bill: billCurrency) }
    private var currencyBinding: Binding<String> {
        Binding(get: { currency }, set: { item.currency = $0 == billCurrency ? nil : $0 })
    }
    let onSave: (ExpenseLineItem) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name (e.g. Tonkotsu ramen)", text: $item.name)
                    Picker("Currency", selection: currencyBinding) {
                        ForEach(currencyOptions, id: \.self) { Text(Currencies.label($0)).tag($0) }
                    }
                    amountRow("Price (each)", value: $item.amount)
                    quantityRow
                    adjustmentRow("Discount", value: $item.discount, isPercent: $item.discountIsPercent)
                    // Only for items saved with a tax deduction before it was removed, so it can be cleared.
                    if item.tax != 0 {
                        adjustmentRow("Tax deduction", value: $item.tax, isPercent: $item.taxIsPercent)
                    }
                } footer: {
                    Text("For your records only; it doesn't change the expense amount or budget.")
                }
                Section {
                    // The working, then the total, all together.
                    LabeledContent("Subtotal", value: item.subtotal.money(currency))
                    LabeledContent("Total discount", value: "− " + item.discountValue.money(currency))
                    if item.taxValue != 0 {
                        LabeledContent("Total tax deduction", value: "− " + item.taxValue.money(currency))
                    }
                    LabeledContent("Total price") {
                        Text(item.total.money(currency)).fontWeight(.semibold)
                    }
                } footer: {
                    if currency != billCurrency, rateMissing {
                        Text("Couldn't get the \(currency) rate, so this item can't be checked against the \(billCurrency) bill.")
                    } else if currency != billCurrency, let rate = item.rateToMYR {
                        Text("1 \(currency) = RM \(rate.formatted(.number.precision(.significantDigits(1...6)))), used to compare with the \(billCurrency) bill.")
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete item", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Add item" : "Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        item.name = item.name.trimmingCharacters(in: .whitespaces)
                        onSave(item)
                        dismiss()
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty && item.amount == 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // A different currency from the bill: remember its rate so the items can be compared.
        .task(id: currency) {
            rateMissing = false
            guard currency != billCurrency else { item.rateToMYR = nil; return }
            // Opening a saved item: keep the rate it was recorded with.
            if !checkedRate, item.rateToMYR != nil { checkedRate = true; return }
            checkedRate = true
            if currency == "MYR" { item.rateToMYR = 1; return }
            if let rate = await ExchangeRates.rateToMYR(currency) {
                item.rateToMYR = rate
            } else if item.rateToMYR == nil {
                rateMissing = true
            }
        }
    }

    /// Quantity laid out like Discount: − / + in the middle, the number on the right.
    private var quantityRow: some View {
        HStack {
            Text("Quantity")
            Spacer()
            HStack(spacing: 0) {
                Button { item.quantity = max(item.count - 1, 1) } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .disabled(item.count <= 1)
                Divider().frame(height: 16)
                Button { item.quantity = min(item.count + 1, 999) } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .font(.app(.subheadline, .semibold))
            .frame(width: 130, height: 32)
            .background(Color(.tertiarySystemFill), in: Capsule())
            TextField("1", value: Binding<Int?>(
                get: { item.count },
                set: { item.quantity = min(max($0 ?? 1, 1), 999) }
            ), format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 60)
        }
    }

    /// Tax or discount: a value with a % / currency switch. The worked amounts show in the totals below.
    private func adjustmentRow(_ label: String, value: Binding<Double>, isPercent: Binding<Bool?>) -> some View {
        let percent = Binding<Bool>(get: { isPercent.wrappedValue == true }, set: { isPercent.wrappedValue = $0 })
        return HStack {
                Text(label).lineLimit(1).fixedSize()
                Spacer()
                Picker(label, selection: percent) {
                    Text("Percent").tag(true)
                    Text(currency).tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                TextField("0", value: Binding<Double?>(
                    get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                    set: { value.wrappedValue = $0 ?? 0 }
                ), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 60)
        }
    }

    private func amountRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(currency).foregroundStyle(.secondary)
            // Empty (grey "0") rather than a typed 0, so new digits don't get stuck after a zero.
            TextField("0", value: Binding<Double?>(
                get: { value.wrappedValue == 0 ? nil : value.wrappedValue },
                set: { value.wrappedValue = $0 ?? 0 }
            ), format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }
}
