import SwiftUI

// MARK: - Objectifs : la liste, le détail jour par jour, et la création

struct PlansView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @State private var newPlan = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if tracker.plans.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "target").font(.system(size: 46)).foregroundStyle(Color.brand)
                        Text("Aucun objectif pour l’instant").font(.title3.bold())
                        Text("Par exemple : apprendre Juz Amma avant l’été, réviser tout ce que tu connais en 2 semaines, ou lire tout le Coran pendant le Ramadan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button { newPlan = true } label: { Label("Créer un objectif", systemImage: "plus") }
                            .buttonStyle(BigButtonStyle())
                    }
                    .padding(24)
                    .glass(26)
                }
                ForEach(tracker.plans) { p in
                    NavigationLink { PlanDetail(planID: p.id) } label: { PlanCard(plan: p) }
                        .buttonStyle(PressStyle())
                }
            }
            .padding(20)
        }
        .background { AppBackground() }
        .navigationTitle("Objectifs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newPlan = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nouvel objectif")
            }
        }
        .sheet(isPresented: $newPlan) { PlanEditor() }
    }
}

struct PlanCard: View {
    let plan: Plan
    @Environment(QuranStore.self) private var store

    var body: some View {
        let t = plan.task(store)
        HStack(spacing: 16) {
            ZStack {
                Ring(value: plan.progress, color: plan.kind.color, width: 7)
                Image(systemName: plan.kind.symbol).font(.headline).foregroundStyle(plan.kind.color)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Text(t.finished ? "Terminé" : "\(plan.unit.count(t.perDay)) par jour · fin le \(Dates.short(plan.finishDate(store)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: plan.progress).tint(plan.kind.color)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .glass(24)
    }
}

/// Un objectif en détail : chiffres, calendrier jour par jour, réglages.
struct PlanDetail: View {
    let planID: UUID
    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var month = Day.start(.now)
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        if let plan = tracker.plan(planID) {
            content(plan)
        } else {
            ContentUnavailableView("Objectif supprimé", systemImage: "trash")
        }
    }

    private func content(_ plan: Plan) -> some View {
        let t = plan.task(store)
        let seq = plan.sequence
        let doneUnits = plan.units(seq, from: 0, to: min(plan.position, seq.count), store)
        let totalUnits = plan.units(seq, from: 0, to: seq.count, store)
        return ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    ZStack {
                        Ring(value: plan.progress, color: plan.kind.color, width: 14)
                        VStack(spacing: 0) {
                            Text("\(Int((plan.progress * 100).rounded())) %").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("\(doneUnits) / \(totalUnits) \(plan.unit.label.lowercased())").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 160, height: 160)
                    if let a = seq.first, let b = seq.last {
                        Text(store.label(from: a, to: b)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)

                HStack(spacing: 0) {
                    stat(plan.unit.count(t.perDay), "par jour")
                    stat(t.finished ? "—" : "\(t.studyDays)", "jours de travail")
                    stat(Dates.short(plan.finishDate(store)), plan.mode == .deadline ? "date choisie" : "fin estimée")
                }
                .padding(.vertical, 14)
                .glass(22)

                if !t.finished, !t.rest, !t.isEmpty {
                    let ayat = Array(seq[t.from..<min(t.to, seq.count)])
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AUJOURD’HUI").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(store.label(from: ayat.first ?? 0, to: ayat.last ?? 0)).font(.headline)
                        Text("\(ayat.count) verset\(ayat.count > 1 ? "s" : "") · \(t.done ? "fait ✓" : "à faire")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glass(22)
                }

                MonthCalendar(plan: plan, month: $month)

                if plan.repeats {
                    Label("Tours terminés : \(plan.cycles)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glass(22)
                }

                VStack(spacing: 10) {
                    Button { editing = true } label: { Label("Modifier le rythme ou la date", systemImage: "slider.horizontal.3") }
                        .buttonStyle(BigButtonStyle(color: plan.kind.color))
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Supprimer l’objectif").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .background { AppBackground(tint: plan.kind.color) }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { PlanEditor(editing: plan) }
        .confirmationDialog("Supprimer cet objectif ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                tracker.delete(plan.id)
                dismiss()
            }
        } message: {
            Text("Ce que tu as appris reste dans ta progression.")
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

/// Le calendrier du mois : fait, raté, repos, prévu.
struct MonthCalendar: View {
    let plan: Plan
    @Binding var month: Date
    @Environment(QuranStore.self) private var store

    var body: some View {
        let cal = Day.calendar
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        let finish = plan.finishDate(store)
        let today = Day.start(.now)
        let created = Day.start(plan.created)

        VStack(spacing: 12) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: first) ?? month } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                Text(first.formatted(.dateTime.month(.wide).year().locale(Dates.fr)).capitalized(with: Dates.fr))
                    .font(.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: first) ?? month } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Day.week, id: \.0) { d in
                    Text(d.1).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                ForEach(0..<offset, id: \.self) { i in Color.clear.frame(height: 36).id("blank\(i)") }
                ForEach(1...count, id: \.self) { d in
                    let date = cal.date(byAdding: .day, value: d - 1, to: first) ?? first
                    cell(d, state(date, today: today, created: created, finish: finish))
                }
            }
            HStack(spacing: 14) {
                legend(Color.brand, "Fait")
                legend(Color.primary.opacity(0.3), "Raté")
                legend(plan.kind.color.opacity(0.25), "Prévu")
                legend(Color.primary.opacity(0.08), "Repos")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .glass(24)
    }

    enum CellState { case done, missed, planned, rest, empty }

    private func state(_ date: Date, today: Date, created: Date, finish: Date) -> CellState {
        if (plan.log[Day.key(date)] ?? 0) > 0 { return .done }
        let rest = plan.restDays.contains(Day.weekday(date))
        if date < today {
            if date >= created && !rest { return .missed }
            return .empty
        }
        if rest { return .rest }
        if date <= finish || plan.repeats { return .planned }
        return .empty
    }

    private func cell(_ day: Int, _ s: CellState) -> some View {
        let isToday = Day.key(Day.calendar.date(byAdding: .day, value: day - 1,
                                                to: Day.calendar.date(from: Day.calendar.dateComponents([.year, .month], from: month)) ?? month) ?? month) == Day.key(.now)
        return Text("\(day)")
            .font(.footnote.weight(isToday ? .heavy : .medium).monospacedDigit())
            .foregroundStyle(s == .done ? Color.onBrand : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                switch s {
                case .done: Circle().fill(Color.brand.gradient)
                case .missed: Circle().strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                case .planned: Circle().fill(plan.kind.color.opacity(0.18))
                case .rest: Circle().fill(Color.primary.opacity(0.06))
                case .empty: Color.clear
                }
            }
            .overlay { if isToday { Circle().strokeBorder(Color.primary, lineWidth: 1.5).padding(-2) } }
    }

    private func legend(_ c: Color, _ l: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 9, height: 9)
            Text(l)
        }
    }
}

// MARK: - Créer (ou modifier) un objectif, avec le calcul en direct

struct PlanEditor: View {
    enum Scope: String, CaseIterable, Identifiable {
        case surahs, juz, hizb, pages
        var id: String { rawValue }
        var label: String {
            switch self {
            case .surahs: return "Sourates"
            case .juz: return "Juz"
            case .hizb: return "Hizb"
            case .pages: return "Pages"
            }
        }
    }

    var editing: Plan?
    var surah: Int?

    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PlanKind = .memorize
    @State private var scope: Scope = .surahs
    @State private var fromSurah = 1
    @State private var toSurah = 1
    @State private var fromJuz = 30
    @State private var toJuz = 30
    @State private var fromHizb = 1
    @State private var toHizb = 60
    @State private var fromPage = 1
    @State private var toPage = 604
    @State private var reversed = false
    @State private var unit: PlanUnit = .ayahs
    @State private var mode: PlanMode = .deadline
    @State private var deadline = Day.add(90, to: .now)
    @State private var pace = 5
    @State private var restDays: Set<Int> = []
    @State private var repeats = false
    @State private var title = ""
    @State private var ready = false

    init(editing: Plan? = nil, surah: Int? = nil) {
        self.editing = editing
        self.surah = surah
    }

    var body: some View {
        NavigationStack {
            Form {
                if editing == nil {
                    Section {
                        Picker("Type", selection: $kind) {
                            ForEach(PlanKind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text(kindHelp)
                    }

                    Section("Idées rapides") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(presets, id: \.0) { preset in
                                    Button(preset.0) { withAnimation { preset.1() } }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .frame(height: 36)
                                        .glassCapsule(interactive: true)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }

                    Section {
                        Picker("Par", selection: $scope) {
                            ForEach(Scope.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch scope {
                        case .surahs:
                            Picker("De", selection: $fromSurah) { surahOptions }
                            Picker("À", selection: $toSurah) { surahOptions }
                        case .juz:
                            Stepper("Du juz \(fromJuz)", value: $fromJuz, in: 1...30)
                            Stepper("Au juz \(toJuz)", value: $toJuz, in: 1...30)
                        case .hizb:
                            Stepper("Du hizb \(fromHizb)", value: $fromHizb, in: 1...60)
                            Stepper("Au hizb \(toHizb)", value: $toHizb, in: 1...60)
                        case .pages:
                            Stepper("De la page \(fromPage)", value: $fromPage, in: 1...604)
                            Stepper("À la page \(toPage)", value: $toPage, in: 1...604)
                        }
                        if scope != .pages {
                            Toggle("Commencer par la fin", isOn: $reversed)
                        }
                    } header: {
                        Text("Quoi ?")
                    } footer: {
                        if reversed && scope != .pages {
                            Text("Sourate par sourate en partant de la dernière, comme on apprend souvent Juz Amma (An-Nâs, Al-Falaq, Al-Ikhlâs…).")
                        }
                    }
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(PlanUnit.allCases) { u in
                            Button {
                                unit = u
                                pace = min(pace, u.maxPerDay)
                            } label: {
                                VStack(spacing: 1) {
                                    Text(u.label).font(.subheadline.weight(.bold))
                                    Text(u.hint).font(.caption2)
                                        .foregroundStyle(unit == u ? Color.onBrand.opacity(0.75) : Color.secondary)
                                }
                                .foregroundStyle(unit == u ? Color.onBrand : Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(unit == u ? Color.primary : Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    Picker("Je choisis", selection: $mode) {
                        Text("Une date de fin").tag(PlanMode.deadline)
                        Text("Un rythme").tag(PlanMode.pace)
                    }
                    if mode == .deadline {
                        DatePicker(kind == .review && repeats ? "Un tour en" : "Finir avant le", selection: $deadline,
                                   in: Day.start(.now)..., displayedComponents: .date)
                            .environment(\.locale, Dates.fr)
                    } else {
                        Stepper("\(unit.count(pace)) par jour", value: $pace, in: 1...unit.maxPerDay)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jours de repos").font(.subheadline)
                        HStack(spacing: 6) {
                            ForEach(Day.week, id: \.0) { d in
                                let day = d.0, label = d.1
                                let on = restDays.contains(day)
                                Button {
                                    if on { restDays.remove(day) } else { restDays.insert(day) }
                                } label: {
                                    Text(label)
                                        .font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .foregroundStyle(on ? Color.onBrand : Color.primary)
                                        .background(Circle().fill(on ? Color.primary : Color.primary.opacity(0.07)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if kind != .memorize {
                        Toggle("Recommencer quand c’est fini", isOn: $repeats)
                    }
                } header: {
                    Text("Comment ?")
                }

                Section {
                    landmarks
                } header: {
                    Text("Repères")
                }

                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Nom") {
                    TextField(autoTitle, text: $title)
                }
            }
            .navigationTitle(editing == nil ? "Nouvel objectif" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Créer" : "Enregistrer") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.total == 0)
                }
            }
            .onAppear(perform: setup)
        }
    }

    private var kindHelp: String {
        switch kind {
        case .memorize: return "Apprendre par cœur de nouveaux versets. Ils entrent ensuite dans tes révisions."
        case .review: return "Repasser ce que tu connais déjà, en un nombre de jours choisi."
        case .read: return "Lire (sans apprendre), par exemple tout le Coran pendant le Ramadan."
        }
    }

    private var surahOptions: some View {
        ForEach(store.surahs) { s in Text("\(s.n). \(s.tr)").tag(s.n) }
    }

    private var presets: [(String, () -> Void)] {
        [
            ("1 hizb par jour", { kind = .review; scope = .hizb; fromHizb = 1; toHizb = 60; reversed = false; unit = .hizb; mode = .pace; pace = 1; repeats = true }),
            ("Juz Amma", { kind = .memorize; scope = .juz; fromJuz = 30; toJuz = 30; reversed = true; unit = .ayahs }),
            ("Juz Tabarak", { kind = .memorize; scope = .juz; fromJuz = 29; toJuz = 29; reversed = false; unit = .ayahs }),
            ("Al-Kahf", { kind = .memorize; scope = .surahs; fromSurah = 18; toSurah = 18; reversed = false }),
            ("Al-Mulk", { kind = .memorize; scope = .surahs; fromSurah = 67; toSurah = 67; reversed = false }),
            ("Tout le Coran", { kind = .memorize; scope = .juz; fromJuz = 1; toJuz = 30; reversed = false; unit = .pages; mode = .pace; pace = 1 }),
            ("Khatm du Ramadan", { kind = .read; scope = .juz; fromJuz = 1; toJuz = 30; reversed = false; unit = .pages; mode = .deadline; deadline = Day.add(29, to: .now) }),
            ("Réviser en 2 semaines", { kind = .review; scope = .juz; fromJuz = 30; toJuz = 30; reversed = false; unit = .pages; mode = .deadline; repeats = true; deadline = Day.add(13, to: .now) })
        ]
    }

    // Les versets choisis, dans l'ordre.
    private var segments: [ClosedRange<Int>] {
        let range: Range<Int>
        switch scope {
        case .surahs:
            let a = min(fromSurah, toSurah), b = max(fromSurah, toSurah)
            range = store.surahRange(a).lowerBound..<store.surahRange(b).upperBound
        case .juz:
            let a = min(fromJuz, toJuz), b = max(fromJuz, toJuz)
            range = store.juzRange(a).lowerBound..<store.juzRange(b).upperBound
        case .hizb:
            let a = min(fromHizb, toHizb), b = max(fromHizb, toHizb)
            range = store.hizbRange(a).lowerBound..<store.hizbRange(b).upperBound
        case .pages:
            let a = min(fromPage, toPage), b = max(fromPage, toPage)
            range = store.pageRange(a).lowerBound..<store.pageRange(b).upperBound
        }
        guard !range.isEmpty else { return [] }
        if reversed && scope != .pages {
            // Sourate par sourate, de la dernière à la première.
            let first = store.ref(range.lowerBound).surah, last = store.ref(range.upperBound - 1).surah
            return stride(from: last, through: first, by: -1).compactMap { s in
                let r = store.surahRange(s).clamped(to: range)
                return r.isEmpty ? nil : r.lowerBound...(r.upperBound - 1)
            }
        }
        return [range.lowerBound...(range.upperBound - 1)]
    }

    private var autoTitle: String {
        let k = kind == .memorize ? "Apprendre" : kind == .review ? "Réviser" : "Lire"
        switch scope {
        case .surahs:
            let a = min(fromSurah, toSurah), b = max(fromSurah, toSurah)
            return a == b ? "\(k) \(store.name(a))" : "\(k) \(store.name(a)) → \(store.name(b))"
        case .juz:
            let a = min(fromJuz, toJuz), b = max(fromJuz, toJuz)
            if a == 1 && b == 30 { return kind == .read ? "Lire tout le Coran" : "\(k) tout le Coran" }
            if a == b && a == 30 { return "\(k) Juz Amma" }
            if a == b && a == 29 { return "\(k) Juz Tabarak" }
            return a == b ? "\(k) le juz \(a)" : "\(k) les juz \(a) à \(b)"
        case .hizb:
            let a = min(fromHizb, toHizb), b = max(fromHizb, toHizb)
            if a == 1 && b == 60 { return kind == .read ? "Lire tout le Coran" : "\(k) tout le Coran" }
            return a == b ? "\(k) le hizb \(a)" : "\(k) les hizb \(a) à \(b)"
        case .pages:
            return "\(k) les pages \(min(fromPage, toPage)) à \(max(fromPage, toPage))"
        }
    }

    private var draft: Plan {
        var p = editing ?? Plan(kind: kind, title: "", segments: segments)
        if editing == nil {
            p.kind = kind
            p.segments = segments
            p.repeats = kind != .memorize && repeats
        } else {
            p.repeats = p.kind != .memorize && repeats
        }
        p.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? (editing?.title ?? autoTitle) : title
        p.unit = unit
        p.mode = mode
        p.deadline = deadline
        p.pace = pace
        p.restDays = restDays.sorted()
        p.cycleDays = max(1, Day.calendar.dateComponents([.day], from: Day.start(.now), to: Day.start(deadline)).day.map { $0 + 1 } ?? 30)
        return p
    }

    /// Les équivalences : juz, hizb, nisf, rub‘, pages, et ce que fait ta sélection.
    private var landmarks: some View {
        let seq = draft.sequence
        return VStack(alignment: .leading, spacing: 10) {
            landmark("1 juz", "2 hizb · 4 nisf · 8 rub‘ · ≈ 20 pages")
            landmark("1 hizb", "2 nisf · 4 rub‘ · ≈ 10 pages")
            landmark("1 nisf", "2 rub‘ · ≈ 5 pages")
            landmark("1 rub‘", "¼ de hizb · ≈ 2,5 pages")
            landmark("1 page", "15 lignes du Mushaf de Médine")
            if !seq.isEmpty {
                Divider()
                Text("TA SÉLECTION").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(selectionText(seq)).font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }

    private func landmark(_ a: String, _ b: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(a).font(.subheadline.weight(.bold)).frame(width: 64, alignment: .leading)
            Text("= " + b).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func selectionText(_ seq: [Int]) -> String {
        let rubs = store.count(seq, in: .rub)
        let pages = store.count(seq, in: .pages)
        var parts: [String] = []
        if rubs >= 8 { parts.append("≈ " + quarters(Double(rubs) / 8, "juz")) }
        if rubs >= 4 { parts.append("≈ " + quarters(Double(rubs) / 4, "hizb")) }
        parts.append("\(rubs) rub‘")
        parts.append(PlanUnit.pages.count(pages))
        parts.append(PlanUnit.ayahs.count(seq.count))
        return parts.joined(separator: " · ")
    }

    /// « 2,5 hizb ».
    private func quarters(_ v: Double, _ unit: String) -> String {
        let r = (v * 4).rounded() / 4
        let text = r == r.rounded() ? "\(Int(r))" : String(format: "%.2f", r).replacingOccurrences(of: ".", with: ",")
            .replacingOccurrences(of: ",50", with: ",5")
        return "\(text) \(unit)"
    }

    private var preview: some View {
        let p = draft
        let t = p.task(store)
        let seq = p.sequence
        let rest = Array(seq[min(p.position, seq.count)...])
        let units = p.units(seq, from: min(p.position, seq.count), to: seq.count, store)
        let perUnitAyahs = units > 0 ? Double(rest.count) / Double(units) : 0
        let perUnitPages = units > 0 ? Double(store.count(rest, in: .pages)) / Double(units) : 0
        return VStack(spacing: 6) {
            if p.total == 0 {
                Text("Choisis ce que tu veux faire.").foregroundStyle(.secondary)
            } else {
                Text(p.unit.count(t.perDay))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("par jour").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(perDayText(p.unit, t.perDay, perUnitPages, perUnitAyahs))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Divider().padding(.vertical, 6)
                HStack {
                    VStack(spacing: 2) {
                        Text("\(units)").font(.headline.monospacedDigit())
                        Text(p.unit.label.lowercased()).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Text("\(p.mode == .deadline ? t.studyDays : p.studyDays(from: .now, to: p.finishDate(store)))").font(.headline.monospacedDigit())
                        Text("jours de travail").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Text(Dates.short(p.finishDate(store))).font(.headline)
                        Text(p.mode == .deadline ? "fin" : "fin estimée").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .glass(24)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: t.perDay)
    }

    /// « ≈ 10 pages · ≈ 90 versets par jour ».
    private func perDayText(_ unit: PlanUnit, _ n: Int, _ pages: Double, _ ayahs: Double) -> String {
        var parts: [String] = []
        if unit != .pages && unit != .ayahs, pages > 0 {
            let v = pages * Double(n)
            parts.append("≈ " + (v < 10 ? String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") : "\(Int(v.rounded()))") + " pages")
        }
        if unit != .ayahs, ayahs > 0 { parts.append("≈ \(Int((ayahs * Double(n)).rounded())) versets") }
        if unit == .ayahs, pages > 0, ayahs > 0 {
            let v = Double(n) / ayahs * pages
            parts.append("≈ " + String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") + " page")
        }
        return parts.isEmpty ? "" : parts.joined(separator: " · ") + " par jour"
    }

    private func setup() {
        guard !ready else { return }
        ready = true
        if let e = editing {
            kind = e.kind
            unit = e.unit
            mode = e.mode
            deadline = max(e.deadline, Day.start(.now))
            pace = e.pace
            restDays = Set(e.restDays)
            repeats = e.repeats
            title = e.title
        } else if let s = surah {
            scope = .surahs
            fromSurah = s
            toSurah = s
            unit = .ayahs
        } else {
            fromSurah = 78
            toSurah = 114
            scope = .juz
            reversed = true
        }
    }

    private func save() {
        var p = draft
        if editing != nil {
            // Le nouveau rythme compte à partir d'aujourd'hui.
            p.initialPerDay = 0
            let today = Day.key(.now)
            if p.dayKey == today, (p.log[today] ?? 0) == 0 { p.dayKey = "" }
            p.initialPerDay = p.task(store).perDay
            tracker.update(p)
        } else {
            tracker.add(p, store)
        }
        dismiss()
    }
}
