import WidgetKit
import SwiftUI

@main
struct TriplyWidgetBundle: WidgetBundle {
    init() { AppFont.register() }

    var body: some Widget {
        TripWidget()
        ExpenseWidget()
        QuickAddExpenseControl()
    }
}
