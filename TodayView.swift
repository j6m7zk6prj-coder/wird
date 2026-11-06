import SwiftUI

// MARK: - Aujourd'hui : ton wird du jour (apprendre, révision récente, ancienne révision)

struct TodayView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @AppStorage("oldPerDay") private var oldPerDay = 2
    @State private var settings = false
    @State private var newPlan = false
    @State private var knownPicker = false

    var body: some View {
        let memorize = tracker.plans.filter { $0.kind == .memorize }
        let others = tracker.plans.filter { $0.kind != .memorize }
        let recent = tracker.recentPages()
        let old = tracker.oldPages(limit: oldPerDay)
        let summary = progress(memorize + others, recent + old)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(summary)

                if tracker.plans.isEmpty && tracker.known.isEmpty {
                    welcome
                }

                if !memorize.isEmpty {
                    section("À apprendre", "sparkles") {
                        ForEach(memorize) { TaskCard(plan: $0) }
                    }
                }

                if !recent.isEmpty {
                    section("Révision récente", "clock.arrow.circlepath", note: "Ce que tu as appris ces 7 derniers jours") {
                        ForEach(recent, id: \.self) { PageRow(page: $0) }
                    }
                }

                if !old.isEmpty {
                    section("Ancienne révision", "arrow.triangle.2.circlepath", note: "Les pages que tu risques d’oublier") {
                        ForEach(old, id: \.self) { PageRow(page: $0) }
                    }
                } else if !tracker.memory.isEmpty {
                    section("Ancienne révision", "arrow.triangle.2.circlepath") {
                        Label("Rien à revoir aujourd’hui, tout est solide.", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .glass(22)
                    }
                }

                if !others.isEmpty {
                    section("Réviser et lire", "book") {
                        ForEach(others) { TaskCard(plan: $0) }
                    }
                }

                Text("« Le meilleur d’entre vous est celui qui apprend le Coran et l’enseigne. »\nRapporté par al-Bukhârî")
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Aujourd’hui")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Réglages")
            }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $newPlan) { PlanEditor() }
        .sheet(isPresented: $knownPicker) { NavigationStack { KnownPicker() } }
    }

    private func progress(_ plans: [Plan], _ pages: [Int]) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for p in plans {
            let t = p.task(store)
            if t.finished || (t.rest && !t.done) { continue }
            total += 1
            if t.done { done += 1 }
        }
        for page in pages {
            total += 1
            if tracker.reviewedToday(page) { done += 1 }
        }
        return (done, total)
    }

    private func header(_ s: (done: Int, total: Int)) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Ring(value: s.total == 0 ? 0 : Double(s.done) / Double(s.total), width: 9)
                if s.total > 0 && s.done == s.total {
                    Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(Color.brand)
                } else {
                    Text("\(s.done)/\(s.total)").font(.headline.monospacedDigit())
                }
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 3) {
                Text(Dates.long(.now).capitalized(with: Dates.fr)).font(.headline)
                Text(Dates.hijri(.now)).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                    Text(tracker.streak == 0 ? "Commence ta série aujourd’hui" : "\(tracker.streak) jour\(tracker.streak > 1 ? "s" : "") d’affilée")
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .glass(26)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bienvenue dans Wird").font(.title2.bold())
            Text("Fixe-toi un objectif : Wird calcule combien de versets faire chaque jour, te rappelle tes révisions et suit ta progression.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button { newPlan = true } label: { Label("Créer mon premier objectif", systemImage: "target") }
                .buttonStyle(BigButtonStyle())
            Button { knownPicker = true } label: {
                Label("Indiquer ce que je connais déjà", systemImage: "checkmark.seal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .glassCapsule(interactive: true)
            }
            .buttonStyle(PressStyle())
        }
        .padding(20)
        .glass(26)
    }

    private func section<Content: View>(_ title: String, _ symbol: String, note: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol).font(.title3.bold())
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
    }
}

/// La tâche du jour d'un objectif : le passage, et « c'est fait ».
struct TaskCard: View {
    let plan: Plan
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var partial = false

    var body: some View {
        let t = plan.task(store)
        let seq = plan.sequence
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: plan.kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.onBrand)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(plan.kind.color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan.title).font(.headline).lineLimit(1)
                    Text("\(Int((plan.progress * 100).rounded())) % · \(plan.kind.label)\(plan.cycles > 0 ? " · tour \(plan.cycles + 1)" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if t.done {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.brand)
                }
            }

            if t.finished {
                Label("Objectif terminé, machAllah !", systemImage: "party.popper.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brand)
            } else if t.done {
                HStack {
                    Text("C’est fait pour aujourd’hui").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Annuler") { tracker.undo(plan.id) }.font(.subheadline)
                }
            } else if t.rest {
                HStack {
                    Label("Jour de repos", systemImage: "leaf.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Avancer quand même") { tracker.complete(plan.id, store) }.font(.subheadline)
                }
            } else if !t.isEmpty {
                let ayat = Array(seq[t.from..<min(t.to, seq.count)])
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.label(from: ayat.first ?? 0, to: ayat.last ?? 0))
                        .font(.title3.weight(.semibold))
                    let pages = store.pages(of: ayat)
                    Text(detail(ayat, pages))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if plan.mode == .deadline, plan.initialPerDay > 0, t.perDay > plan.initialPerDay {
                        Label("Un peu de retard : \(plan.unit.count(t.perDay)) par jour au lieu de \(plan.initialPerDay)", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    NavigationLink {
                        StudyView(ayat: ayat, title: plan.title, mode: .task(plan.id))
                    } label: {
                        Label(plan.kind == .read ? "Lire" : "Commencer", systemImage: plan.kind == .read ? "book.fill" : "play.fill")
                    }
                    .buttonStyle(BigButtonStyle(color: plan.kind.color))
                    Menu {
                        Button(plan.kind.doneLabel, systemImage: "checkmark") { tracker.complete(plan.id, store) }
                        if ayat.count > 1 {
                            Button("J’en ai fait une partie", systemImage: "slider.horizontal.3") { partial = true }
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(plan.kind.color)
                            .frame(width: 52, height: 52)
                            .glassCircle()
                    }
                    .accessibilityLabel("Marquer comme fait")
                }
            }
        }
        .padding(16)
        .glass(24)
        .sheet(isPresented: $partial) {
            PartialSheet(plan: plan, ayat: Array(seq[t.from..<min(max(t.from, t.to), seq.count)]))
        }
    }

    private func detail(_ ayat: [Int], _ pages: [Int]) -> String {
        var parts: [String] = []
        if plan.unit != .ayahs, plan.unit != .pages {
            parts.append(plan.unit.count(max(1, store.count(ayat, in: plan.unit))))
        }
        parts.append(PlanUnit.ayahs.count(ayat.count))
        parts.append((pages.count > 1 ? "pages " : "page ") + pageText(pages))
        return parts.joined(separator: " · ")
    }

    private func pageText(_ pages: [Int]) -> String {
        guard let a = pages.first, let b = pages.last else { return "" }
        return a == b ? "\(a)" : "\(a)–\(b)"
    }
}

/// « J'en ai fait une partie » : jusqu'à quel verset.
struct PartialSheet: View {
    let plan: Plan
    let ayat: [Int]
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var count = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Jusqu’où es-tu allé ?").font(.title3.bold())
                if !ayat.isEmpty {
                    Text(store.label(from: ayat[0], to: ayat[min(count, ayat.count) - 1]))
                        .font(.headline)
                        .foregroundStyle(Color.brand)
                }
                Stepper("\(count) verset\(count > 1 ? "s" : "") sur \(ayat.count)", value: $count, in: 1...max(1, ayat.count))
                    .padding(16)
                    .glass(20)
                Button("Enregistrer") {
                    let start = plan.task(store).from
                    tracker.complete(plan.id, store, upTo: start + count)
                    dismiss()
                }
                .buttonStyle(BigButtonStyle())
                Spacer()
            }
            .padding(20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .onAppear { count = max(1, ayat.count / 2) }
    }
}

/// Une page à réviser : sa solidité, l'ouvrir, se noter.
struct PageRow: View {
    let page: Int
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker

    var body: some View {
        let s = tracker.strength(page, store)
        let done = tracker.reviewedToday(page)
        let range = store.pageRange(page)
        HStack(spacing: 12) {
            NavigationLink {
                StudyView(ayat: Array(range), title: "Page \(page)", mode: .review([page]))
            } label: {
                HStack(spacing: 12) {
                    Text("\(page)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.07)))
                        .overlay(alignment: .bottomTrailing) { StrengthDot(strength: s).offset(x: 3, y: 3) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.surahs(onPage: page).map { store.name($0) }.joined(separator: ", "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(done ? "Révisée aujourd’hui" : "\(s.label) · juz \(store.juz(range.lowerBound))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(PressStyle())
            if done {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Color.brand)
            } else {
                Menu {
                    ForEach(Grade.allCases.reversed()) { g in
                        Button(g.label, systemImage: g.symbol) { tracker.grade(page, g) }
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(Color.brand)
                        .frame(width: 42, height: 42)
                        .glassCircle()
                }
                .accessibilityLabel("Révisée")
            }
        }
        .padding(12)
        .glass(22)
    }
}
