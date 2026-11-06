import SwiftUI
import UserNotifications

// MARK: - Réglages

struct SettingsView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var theme = 0
    @AppStorage("oldPerDay") private var oldPerDay = 2
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
                        Text("Les notifications sont bloquées. Autorise-les dans Réglages › Wird.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Rappel")
                } footer: {
                    Text("Une notification chaque jour, par exemple après la prière du Fajr.")
                }

                Section("Apparence") {
                    Picker("Thème", selection: $theme) {
                        Text("Auto").tag(0)
                        Text("Clair").tag(1)
                        Text("Sombre").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper("\(oldPerDay) page\(oldPerDay > 1 ? "s" : "") d’ancienne révision par jour", value: $oldPerDay, in: 0...20)
                    NavigationLink("Ce que je connais déjà") { KnownPicker() }
                } header: {
                    Text("Révision")
                } footer: {
                    Text("Wird ramène plus souvent les pages que tu notes « difficile », et espace celles que tu connais bien.")
                }

                Section {
                    Button("Sources et licences") { about = true }
                    Button("Tout effacer", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $about) { AboutView() }
            .confirmationDialog("Effacer tous tes objectifs et ta progression ?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Tout effacer", role: .destructive) { tracker.resetAll() }
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
        content.body = "Quelques minutes avec le Coran : ce que tu apprends et tes révisions t’attendent."
        content.sound = .default
        var date = DateComponents()
        date.hour = minutes / 60
        date.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "wird.daily", content: content, trigger: trigger))
        return true
    }
}

/// « Ce que je connais déjà » : cocher des sourates ou des juz entiers.
struct KnownPicker: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0

    var body: some View {
        List {
            Section {
                Picker("Par", selection: $mode) {
                    Text("Sourates").tag(0)
                    Text("Juz").tag(1)
                    Text("Hizb").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Coche ce que tu sais déjà par cœur : ces pages entrent dans tes révisions. Pour une page précise, va dans Progrès › Juz par juz.")
            }
            if mode == 1 {
                ForEach((1...30).reversed(), id: \.self) { j in
                    row("Juz \(j)", detail: "Commence à \(store.label(store.juzRange(j).lowerBound))", range: store.juzRange(j))
                }
            } else if mode == 2 {
                ForEach((1...60).reversed(), id: \.self) { h in
                    row("Hizb \(h)", detail: "Commence à \(store.label(store.hizbRange(h).lowerBound))", range: store.hizbRange(h))
                }
            } else {
                ForEach(store.surahs.reversed()) { s in
                    row("\(s.n). \(s.tr)", detail: "\(French.surahName(s.n)) · \(s.count) versets", range: store.surahRange(s.n))
                }
            }
        }
        .navigationTitle("Ce que je connais")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() }.fontWeight(.semibold) }
        }
    }

    private func row(_ title: String, detail: String, range: Range<Int>) -> some View {
        let known = tracker.knownCount(in: range)
        let all = known == range.count
        return Button {
            if all { tracker.forget(range, store) } else { tracker.markKnown(range, store) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(known > 0 && !all ? "En partie (\(known)/\(range.count))" : detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: all ? "checkmark.circle.fill" : (known > 0 ? "circle.lefthalf.filled" : "circle"))
                    .font(.title3)
                    .foregroundStyle(all || known > 0 ? Color.brand : Color.secondary)
            }
        }
    }
}
