import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / Lock Screen button: one tap opens Triply's Add expense form.
struct QuickAddExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.kingway.tripple.quick-add-expense") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "tripple://add-expense")!)) {
                Label("Add expense", systemImage: "banknote.fill")
            }
        }
        .displayName("Triply expense")
        .description("Log a travel expense in two taps.")
    }
}
