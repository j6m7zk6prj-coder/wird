import SwiftUI

// MARK: - Révision : tout ce que tu connais, en X jours, et où tu en es

struct RevisionView: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @State private var pickStart = false
    @State private var learningSetup = false

    var body: some View {
        ScrollView {
            if let known = journal.known(store), !known.isEmpty, let r = journal.revision {
                content(known, r)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 44))
                    Text("Ton programme de révision").font(.title2.bold())
                    Text("Wird révise tout ce que tu connais. Commence par indiquer où tu en es dans l’apprentissage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Indiquer où j’en suis") { learningSetup = true }.buttonStyle(BigButtonStyle())
                }
                .padding(24)
                .glass(26)
                .padding(20)
            }
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle("Révision")
        .sheet(isPresented: $pickStart) { RevisionStartPicker() }
        .sheet(isPresented: $learningSetup) { LearningSetup() }
    }

    private func content(_ known: [Int], _ r: Revision) -> some View {
        let total = store.pages(known, 0, known.count)
        let perDay = journal.revisionPerDay(store)
        let start = min(r.position, known.count)
        let done = store.pages(known, 0, start)
        let left = total - done
        let daysLeft = Int((left / max(0.1, perDay)).rounded(.up))
        let chunk = journal.revisionChunk(store)
        return VStack(alignment: .leading, spacing: 18) {
            // Le programme.
            VStack(alignment: .leading, spacing: 12) {
                Text("TON PROGRAMME").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text("Tout réviser en \(r.days) jours").font(.title2.bold())
                Text("\(Num.pagesLabel(total)) à réviser, soit ≈ \(Num.pagesLabel(perDay)) par jour.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Stepper(value: Binding(get: { r.days }, set: { journal.setRevision(days: $0) }), in: 1...120) {
                    Text("\(r.days) jours").font(.headline.monospacedDigit())
                }
                HStack(spacing: 8) {
                    ForEach([7, 14, 30], id: \.self) { d in
                        Button("\(d) jours") { journal.setRevision(days: d) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(r.days == d ? Color.onBrand : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(r.days == d ? Color.primary : Color.primary.opacity(0.07)))
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)

            // Le tour en cours.
            VStack(alignment: .leading, spacing: 12) {
                Text(r.tours == 0 ? "PREMIER TOUR" : "TOUR \(r.tours + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(percent(done / max(0.1, total)))").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("révisé").font(.headline).foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, done / max(0.1, total))).tint(.primary)
                Text(tourText(left, daysLeft))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if r.tours > 0 {
                    Text("Tours terminés : \(r.tours)").font(.subheadline.weight(.semibold))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)

            // Où tu reprends.
            VStack(alignment: .leading, spacing: 12) {
                Text("OÙ TU EN ES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if let chunk, !chunk.isEmpty {
                    Text(chunk.done ? "Fait aujourd’hui" : "Prochain passage").font(.caption).foregroundStyle(.secondary)
                    Text(Passage.label(Array(chunk.ayat), store)).font(.title3.weight(.semibold))
                    Text(Passage.detail(Array(chunk.ayat), store.pages(of: Array(chunk.ayat))))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button { pickStart = true } label: {
                    Label("Je me suis arrêté ailleurs", systemImage: "bookmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(PressStyle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(26)
        }
        .padding(20)
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    private func tourText(_ left: Double, _ daysLeft: Int) -> String {
        if left <= 0.01 { return "Tour terminé" }
        let end = Day.add(max(0, daysLeft - 1), to: .now)
        return "Encore " + Num.pagesLabel(left) + " · fin du tour vers le " + Dates.short(end)
    }
}

/// « Je me suis arrêté à… » : choisir la sourate (et le verset) où reprendre la révision.
struct RevisionStartPicker: View {
    @Environment(QuranStore.self) private var store
    @Environment(Journal.self) private var journal
    @Environment(\.dismiss) private var dismiss
    @State private var surah = 0
    @State private var ayah = 1

    var body: some View {
        let known = journal.known(store) ?? []
        let surahs = knownSurahs(known)
        let ayahs = known.filter { store.ref($0).surah == surah }.map { store.ref($0).ayah }
        NavigationStack {
            Form {
                Section {
                    Picker("Sourate", selection: $surah) {
                        ForEach(surahs, id: \.self) { s in Text("\(s). \(store.name(s))").tag(s) }
                    }
                    if let lo = ayahs.min(), let hi = ayahs.max(), hi > lo {
                        Stepper("À partir du verset \(ayah)", value: $ayah, in: lo...hi)
                    }
                } header: {
                    Text("Où reprends-tu ta révision ?")
                } footer: {
                    Text("Seules les sourates que tu connais sont proposées.")
                }
            }
            .navigationTitle("Reprendre à")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let g = store.global(surah, ayah)
                        if let i = known.firstIndex(of: g) ?? known.firstIndex(where: { store.ref($0).surah == surah }) {
                            journal.setRevisionStart(i)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(surah == 0)
                }
            }
            .onAppear {
                if surah == 0, let first = surahs.first {
                    if let r = journal.revision, r.position < known.count {
                        let ref = store.ref(known[r.position])
                        surah = ref.surah
                        ayah = ref.ayah
                    } else {
                        surah = first
                    }
                }
            }
            .onChange(of: surah) { old, new in
                if old != 0 { ayah = known.filter { store.ref($0).surah == new }.map { store.ref($0).ayah }.min() ?? 1 }
            }
        }
        .presentationDetents([.medium])
    }

    private func knownSurahs(_ known: [Int]) -> [Int] {
        var out: [Int] = []
        for g in known {
            let s = store.ref(g).surah
            if out.last != s { out.append(s) }
        }
        return out
    }
}
