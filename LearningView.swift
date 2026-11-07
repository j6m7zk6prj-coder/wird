import SwiftUI

// MARK: - Apprentissage : ton objectif de la semaine, et où il te mène

struct LearningView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var setup = false

    var body: some View {
        ScrollView {
            if let l = journal.learning {
                content(l)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "book.closed").font(.system(size: 44))
                    Text("Ton objectif d’apprentissage").font(.title2.bold())
                    Text("Dis où tu en es et combien de pages tu veux apprendre par semaine. Wird calcule combien de versets faire chaque jour.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Commencer") { setup = true }.buttonStyle(BigButtonStyle())
                }
                .padding(24)
                .glass(26)
                .padding(20)
            }
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Apprentissage")
        .toolbar {
            if journal.learning != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { setup = true }
                }
            }
        }
        .sheet(isPresented: $setup) { LearningSetup() }
    }

    private func content(_ l: Learning) -> some View {
        let seq = store.sequence(l.direction)
        let knownPages = journal.knownPages(store)
        let perDay = l.pagesPerWeek / 7
        let chunk = journal.learningChunk(store)
        let weekPages = weekDone(l, seq)
        return VStack(alignment: .leading, spacing: 18) {
            // Ce que tu connais.
            VStack(alignment: .leading, spacing: 10) {
                Text("TU CONNAIS").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.star)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Num.pages(knownPages)).font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("pages sur 604").font(.headline).foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, knownPages / 604)).tint(Color.star)
                Text("≈ \(Num.pages(knownPages / 20)) juz · \(percent(knownPages / 604)) du Coran")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)

            // L'objectif.
            VStack(alignment: .leading, spacing: 12) {
                Text("TON OBJECTIF").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.star)
                Text("\(Num.pagesLabel(l.pagesPerWeek)) par semaine").font(.title2.bold())
                Text("Soit environ \(versesPerDay(l, seq)) versets par jour (≈ \(Num.pagesLabel(perDay))).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Cette semaine").font(.subheadline)
                    Spacer()
                    Text("\(Num.pages(weekPages)) / \(Num.pages(l.pagesPerWeek)) pages").font(.subheadline.weight(.semibold).monospacedDigit())
                }
                ProgressView(value: min(1, weekPages / max(0.1, l.pagesPerWeek))).tint(Color.star)
                if let chunk, !chunk.isEmpty {
                    Divider()
                    Text("Prochain passage").font(.caption).foregroundStyle(.secondary)
                    Text(Passage.label(Array(chunk.ayat), store)).font(.headline)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)

            // Projection.
            VStack(alignment: .leading, spacing: 12) {
                Text("SI TU TIENS CE RYTHME").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Color.star)
                ForEach(horizons, id: \.0) { h in
                    projection(h.1, days: h.0, l, seq, knownPages)
                    if h.0 != horizons.last?.0 { Divider() }
                }
                Divider()
                finish(l, seq)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)
        }
        .padding(20)
    }

    private var horizons: [(Int, String)] {
        [(7, "Dans 1 semaine"), (30, "Dans 1 mois"), (91, "Dans 3 mois"), (182, "Dans 6 mois"), (365, "Dans 1 an")]
    }

    private func projection(_ title: String, days: Int, _ l: Learning, _ seq: [Int], _ known: Double) -> some View {
        let gained = l.pagesPerWeek * Double(days) / 7
        let pos = store.advance(seq, from: min(l.position, seq.count), pages: gained, limit: seq.count)
        let total = min(604, known + gained)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(pos >= seq.count ? "Tout est appris" : "Tu seras à " + store.label(seq[max(0, pos - 1)]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(Num.pages(min(gained, 604 - known))) p.").font(.subheadline.weight(.semibold).monospacedDigit())
                Text("\(Num.pages(total)) pages · \(percent(total / 604))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func finish(_ l: Learning, _ seq: [Int]) -> some View {
        let remaining = store.pages(seq, l.position, seq.count)
        let weeks = remaining / max(0.1, l.pagesPerWeek)
        let date = Day.add(Int((weeks * 7).rounded(.up)), to: .now)
        return HStack {
            Text("Tout le Coran").font(.subheadline.weight(.semibold))
            Spacer()
            Text(remaining <= 0 ? "Terminé" : "vers " + Dates.monthYear(date) + " (\(duration(weeks)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func duration(_ weeks: Double) -> String {
        if weeks < 8 { return "\(Int(weeks.rounded(.up))) semaines" }
        if weeks < 104 { return "\(Int((weeks / 4.345).rounded())) mois" }
        let years = weeks / 52.18
        return String(format: "%.1f", years).replacingOccurrences(of: ".", with: ",") + " ans"
    }

    private func percent(_ v: Double) -> String {
        if v > 0 && v < 0.01 { return "< 1 %" }
        return "\(Int((v * 100).rounded())) %"
    }

    /// Versets par jour au début de ce qui reste.
    private func versesPerDay(_ l: Learning, _ seq: [Int]) -> Int {
        let start = min(l.position, seq.count)
        let end = store.advance(seq, from: start, pages: l.pagesPerWeek / 7 * 30, limit: seq.count)
        return max(1, Int((Double(end - start) / 30).rounded()))
    }

    /// Pages apprises depuis lundi.
    private func weekDone(_ l: Learning, _ seq: [Int]) -> Double {
        let cal = Day.calendar
        guard let monday = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        var ayat = 0
        var d = monday
        while d <= Day.start(.now) {
            ayat += l.log[Day.key(d)] ?? 0
            d = Day.add(1, to: d)
        }
        let end = min(l.position, seq.count)
        return store.pages(seq, max(0, end - ayat), end)
    }
}

/// Régler l'apprentissage : le sens, où tu en es, ce que tu connais, l'objectif.
struct LearningSetup: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @Environment(\.dismiss) private var dismiss

    @State private var direction: Direction = .backward
    @State private var surah = 114
    @State private var ayah = 1
    @State private var knowsBefore = true
    @State private var pagesPerWeek = 3.0
    @State private var ready = false
    @State private var pendingAyah: Int?

    var body: some View {
        let seq = store.sequence(direction)
        let g = store.global(surah, min(ayah, store.surah(surah)?.count ?? 1))
        let pos = store.index(of: g, direction)
        NavigationStack {
            Form {
                Section {
                    Picker("Sens", selection: $direction) {
                        ForEach(Direction.allCases) { d in Text(d.label).tag(d) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Dans quel sens tu apprends ?")
                } footer: {
                    Text(direction.hint)
                }

                Section {
                    Picker("Sourate", selection: $surah) {
                        ForEach(orderedSurahs) { s in Text("\(s.n). \(s.tr)").tag(s.n) }
                    }
                    Stepper("À partir du verset \(ayah)", value: $ayah, in: 1...(store.surah(surah)?.count ?? 1))
                    Toggle("Je connais déjà tout ce qui vient avant", isOn: $knowsBefore)
                } header: {
                    Text("Que vas-tu apprendre maintenant ?")
                } footer: {
                    Text(knowsBefore
                         ? "Déjà appris : ≈ \(Num.pagesLabel(store.pages(seq, 0, pos))). Ça compte dans ta révision."
                         : "Seul ce que tu cocheras dans Wird comptera comme appris.")
                }

                Section {
                    Stepper(value: $pagesPerWeek, in: 0.5...30, step: 0.5) {
                        Text("\(Num.pagesLabel(pagesPerWeek)) par semaine").font(.headline)
                    }
                    let end = store.advance(seq, from: pos, pages: pagesPerWeek / 7 * 30, limit: seq.count)
                    let perDay = max(1, Int((Double(end - pos) / 30).rounded()))
                    LabeledContent("Par jour", value: "≈ \(perDay) verset\(perDay > 1 ? "s" : "")")
                    LabeledContent("En 1 mois", value: "≈ \(Num.pagesLabel(pagesPerWeek * 30 / 7))")
                    LabeledContent("En 1 an", value: "≈ \(Num.pagesLabel(pagesPerWeek * 365 / 7))")
                } header: {
                    Text("Ton objectif")
                } footer: {
                    Text("1 page du Mushaf = 15 lignes. 1 hizb ≈ 10 pages, 1 juz ≈ 20 pages.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackground() }
            .navigationTitle("Mon apprentissage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save(pos) }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .onChange(of: surah) {
                ayah = pendingAyah ?? 1
                pendingAyah = nil
            }
        }
    }

    /// Les sourates dans l'ordre d'apprentissage.
    private var orderedSurahs: [Surah] {
        direction == .backward ? store.surahs.reversed() : store.surahs
    }

    private func load() {
        guard !ready else { return }
        ready = true
        guard let l = journal.learning else { return }
        let seq = store.sequence(l.direction)
        direction = l.direction
        pagesPerWeek = l.pagesPerWeek
        knowsBefore = l.knownFrom == 0
        if l.position < seq.count {
            let r = store.ref(seq[l.position])
            if r.surah == surah { ayah = r.ayah } else { pendingAyah = r.ayah; surah = r.surah }
        }
    }

    private func save(_ pos: Int) {
        var l = journal.learning ?? Learning()
        let changedPlace = l.direction != direction || l.position != pos
        if changedPlace {
            l.direction = direction
            l.position = pos
            l.dayKey = ""
            l.dayCount = nil
            l.knownFrom = knowsBefore ? 0 : pos
        } else if knowsBefore {
            l.knownFrom = 0
        }
        l.pagesPerWeek = pagesPerWeek
        if l.dayKey == journal.today, l.log[journal.today] == nil { l.dayKey = ""; l.dayCount = nil }
        journal.setLearning(l, store)
        dismiss()
    }
}
