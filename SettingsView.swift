import SwiftUI
import UserNotifications

// MARK: - Réglages

struct SettingsView: View {
    @Environment(Journal.self) private var journal
    @Environment(\.dismiss) private var dismiss
    @AppStorage("reminder") private var reminder = false
    @AppStorage("reminderMinutes") private var reminderMinutes = 7 * 60
    @State private var about = false
    @State private var confirmReset = false
    @State private var denied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Me rappeler mon wird", isOn: $reminder)
                    if reminder {
                        DatePicker("Heure", selection: time, displayedComponents: .hourAndMinute)
                            .environment(\.locale, Dates.fr)
                    }
                    if denied {
                        Text("Les notifications sont bloquées. Autorise-les dans Réglages › Wird.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Rappel")
                } footer: {
                    Text("Une notification chaque jour, par exemple après la prière du Fajr.")
                }

                Section {
                    Button("Sources") { about = true }
                    Button("Tout effacer", role: .destructive) { confirmReset = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $about) { AboutView() }
            .confirmationDialog("Effacer ton apprentissage, ta révision et ton journal ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) { journal.resetAll() }
            }
            .onChange(of: reminder) { schedule() }
            .onChange(of: reminderMinutes) { schedule() }
        }
    }

    private var time: Binding<Date> {
        Binding(get: {
            Day.calendar.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
        }, set: { d in
            let c = Day.calendar.dateComponents([.hour, .minute], from: d)
            reminderMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
        })
    }

    private func schedule() {
        Task { denied = !(await Reminder.schedule(on: reminder, minutes: reminderMinutes)) }
    }
}

enum Reminder {
    /// Programme (ou retire) le rappel quotidien. Renvoie false si les notifications sont refusées.
    static func schedule(on: Bool, minutes: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["wird.daily"])
        guard on else { return true }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Ton wird du jour"
        content.body = "Ouvre ton Mushaf : ton apprentissage et ta révision t’attendent."
        content.sound = .default
        var date = DateComponents()
        date.hour = minutes / 60
        date.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "wird.daily", content: content, trigger: trigger))
        return true
    }
}
