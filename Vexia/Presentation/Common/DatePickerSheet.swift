import SwiftUI

/// Compact calendar sheet: tapping a day picks it and closes (month paging doesn't change the date).
struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date

    init(date: Binding<Date>) {
        _date = date
        _picked = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Fecha", selection: $picked, in: ...Date.now.addingTimeInterval(86_400 * 365), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                .navigationTitle("Elegir fecha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cerrar", systemImage: "xmark") { dismiss() } }
                }
                .onChange(of: picked) { _, new in
                    // Keep the time of day; only the calendar day changes.
                    date = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: date),
                                                 minute: Calendar.current.component(.minute, from: date), second: 0, of: new) ?? new
                    dismiss()
                }
        }
        .presentationDetents([.height(500)])
        .sensoryFeedback(.selection, trigger: picked)
    }
}
