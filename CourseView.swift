import SwiftUI

// MARK: - Cours : ce que tu récites au cours (par exemple le vendredi)

struct CourseView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var learningSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if journal.learning == nil {
                    intro("Indique d’abord où tu en es dans l’apprentissage : le cours reprend ce que tu apprends.",
                          button: "Indiquer où j’en suis") { learningSetup = true }
                } else if let course = journal.course {
                    CourseCard()
                    dayPicker(course)
                    history(course)
                } else {
                    intro("Tu vas en cours chaque semaine ? Choisis le jour : Wird te montre ce que tu as appris depuis le dernier cours, à réciter à ton professeur.",
                          button: "Activer le cours du vendredi") { journal.startCourse(weekday: 6) }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Cours")
        .sheet(isPresented: $learningSetup) { LearningSetup() }
    }

    private func intro(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2").font(.system(size: 44))
            Text("Ton cours").font(.title2.bold())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(BigButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glass(26)
    }

    private func dayPicker(_ c: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOUR DU COURS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            Picker("Jour", selection: Binding(get: { c.weekday }, set: { journal.setCourseDay($0) })) {
                ForEach(Day.names, id: \.0) { d in Text(d.1).tag(d.0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Arrêter le suivi du cours", role: .destructive) { journal.stopCourse() }
                .font(.subheadline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(26)
    }

    @ViewBuilder
    private func history(_ c: Course) -> some View {
        if !c.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("MES COURS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                ForEach(c.sessions) { s in
                    SessionRow(session: s)
                    if s.id != c.sessions.last?.id { Divider() }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)
        }
    }
}

/// Le prochain cours : ce qu'il y a à réciter, et « validé » ou « à revoir ».
struct CourseCard: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var noting = false

    var body: some View {
        let ayat = journal.courseAyat(store)
        let next = journal.nextCourseDate()
        let isToday = next.map { Day.key($0) == journal.today } ?? false
        let done = journal.courseDoneToday()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isToday ? "Cours aujourd’hui" : "Prochain cours", systemImage: "person.2")
                    .font(.title3.bold())
                Spacer()
                if let next, !isToday {
                    Text(Dates.dayShort(next).capitalized(with: Dates.fr))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let done {
                Label(done.validated ? "Validé aujourd’hui" : "À revoir pour la prochaine fois",
                      systemImage: done.validated ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                    .font(.headline)
                if !done.note.isEmpty {
                    Text("« \(done.note) »").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if ayat.isEmpty {
                Text(done?.validated == true
                     ? "Tout ce que tu as appris est validé. Continue ton apprentissage pour le prochain cours."
                     : "Rien de nouveau depuis le dernier cours. Coche ton apprentissage chaque jour : ça s’ajoute ici.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("À RÉCITER").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                    Text(Passage.label(ayat, store))
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Passage.detail(ayat, store.pages(of: ayat)) + " · " + Num.pagesLabel(store.pages(ayat, 0, ayat.count)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if done == nil {
                    Button { noting = true } label: { Label("Je suis passé au cours", systemImage: "checkmark") }
                        .buttonStyle(BigButtonStyle())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(26)
        .sheet(isPresented: $noting) { CourseResultSheet() }
    }
}

/// Après le cours : validé ou à revoir, et une remarque du professeur.
struct CourseResultSheet: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        journal.recordCourse(validated: true, note: note, store)
                        dismiss()
                    } label: {
                        Label("Validé : je connais tout", systemImage: "checkmark.circle.fill").font(.headline)
                    }
                    Button {
                        journal.recordCourse(validated: false, note: note, store)
                        dismiss()
                    } label: {
                        Label("À revoir pour la prochaine fois", systemImage: "arrow.uturn.backward.circle").font(.headline)
                    }
                } header: {
                    Text("Comment ça s’est passé ?")
                } footer: {
                    Text("« À revoir » : le même passage restera à réciter au prochain cours, avec ce que tu apprendras d’ici là.")
                }
                Section("Remarque du professeur (facultatif)") {
                    TextField("Ex. : attention au madd verset 4", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Mon cours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Un cours passé dans l'historique.
struct SessionRow: View {
    let session: CourseSession
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.validated ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                .font(.title3)
                .foregroundStyle(session.validated ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(Dates.dayShort(session.date).capitalized(with: Dates.fr)).font(.subheadline.weight(.semibold))
                if let a = session.from, let b = session.to {
                    Text(store.label(a) + " → " + store.label(b)).font(.subheadline)
                }
                Text(session.validated ? "Validé · \(session.count) versets" : "À revoir · \(session.count) versets")
                    .font(.caption).foregroundStyle(.secondary)
                if !session.note.isEmpty {
                    Text("« \(session.note) »").font(.caption).italic().foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button("Supprimer", systemImage: "trash", role: .destructive) { journal.deleteSession(session.id) }
        }
    }
}
