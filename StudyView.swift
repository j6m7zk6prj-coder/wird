import SwiftUI

// MARK: - Apprendre / réviser : verset par verset, avec l'audio, le mode test et l'enregistrement

enum StudyMode: Hashable {
    /// Libre (depuis la liste des sourates).
    case free
    /// La tâche du jour d'un objectif.
    case task(UUID)
    /// Révision de pages : on se note à la fin.
    case review([Int])
}

struct StudyView: View {
    let ayat: [Int]
    let title: String
    let mode: StudyMode

    @Environment(QuranStore.self) private var store
    @Environment(Tracker.self) private var tracker
    @Environment(Recitation.self) private var recitation
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tajweed") private var tajweed = false
    @AppStorage("quranSize") private var size = 30.0
    @AppStorage("reciter") private var reciterID = Reciter.all[0].id
    @State private var testMode = false
    @State private var revealed: Set<Int> = []
    @State private var showRecorder = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    ForEach(Array(ayat.enumerated()), id: \.element) { i, g in
                        if store.ref(g).ayah == 1, let s = store.surah(store.ref(g).surah) {
                            surahHeader(s)
                        }
                        AyahCard(g: g, size: size, tajweed: tajweed,
                                 hidden: testMode && !revealed.contains(g),
                                 playing: recitation.current?.g == g) {
                            if testMode {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    if revealed.contains(g) { revealed.remove(g) } else { revealed.insert(g) }
                                }
                            } else {
                                play(from: i)
                            }
                        }
                        .id(g)
                    }
                    finish
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 130)
            }
            .onChange(of: recitation.current?.g) { _, g in
                guard let g, ayat.contains(g) else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(g, anchor: .center) }
            }
        }
        .background { AppBackground() }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Couleurs du tajwid", systemImage: "paintpalette", isOn: $tajweed)
                    Section("Taille du texte") {
                        Button("Plus grand", systemImage: "textformat.size.larger") { size = min(48, size + 3) }
                        Button("Plus petit", systemImage: "textformat.size.smaller") { size = max(20, size - 3) }
                    }
                } label: { Image(systemName: "textformat") }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .sheet(isPresented: $showRecorder) { RecorderSheet(title: title) }
        .onDisappear { recitation.stop() }
    }

    // En haut : le passage, et le mode test.
    private var header: some View {
        VStack(spacing: 12) {
            if let first = ayat.first, let last = ayat.last {
                Text(store.label(from: first, to: last))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                let pages = store.pages(of: ayat)
                Text("\(ayat.count) verset\(ayat.count > 1 ? "s" : "") · page\(pages.count > 1 ? "s" : "") \(pages.map { String($0) }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        testMode.toggle()
                        revealed = []
                    }
                } label: {
                    Label(testMode ? "Mode test activé" : "Mode test", systemImage: testMode ? "eye.slash.fill" : "eye.slash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .foregroundStyle(testMode ? Color.onBrand : Color.primary)
                        .background { if testMode { Capsule().fill(Color.brand.gradient) } }
                        .glassCapsule(interactive: true)
                }
                .buttonStyle(PressStyle())
                if testMode {
                    Button {
                        withAnimation { revealed = revealed.count == ayat.count ? [] : Set(ayat) }
                    } label: {
                        Text(revealed.count == ayat.count ? "Tout cacher" : "Tout montrer")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .glassCapsule(interactive: true)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            if testMode {
                Text("Récite de mémoire, puis touche un verset pour vérifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func surahHeader(_ s: Surah) -> some View {
        VStack(spacing: 4) {
            Text("سُورَةُ " + s.ar).font(.custom(Fonts.quranName, size: 26)).foregroundStyle(.secondary)
            if s.basmala, !Mushaf.basmala.isEmpty {
                Text(Mushaf.basmala).font(.custom(Fonts.quranName, size: 22))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(20)
    }

    // En bas : terminer (et se noter si c'est une révision).
    @ViewBuilder private var finish: some View {
        switch mode {
        case .free:
            EmptyView()
        case .task(let id):
            if let plan = tracker.plan(id) {
                let t = plan.task(store)
                if !t.done {
                    Button {
                        tracker.complete(id, store, upTo: nil)
                        dismiss()
                    } label: {
                        Label(plan.kind.doneLabel, systemImage: "checkmark")
                    }
                    .buttonStyle(BigButtonStyle(color: plan.kind.color))
                    .padding(.top, 10)
                }
            }
        case .review(let pages):
            VStack(spacing: 10) {
                Text("Comment ça s’est passé ?").font(.headline)
                HStack(spacing: 10) {
                    ForEach(Grade.allCases.reversed()) { g in
                        Button {
                            for p in pages { tracker.grade(p, g) }
                            tracker.message = "Révision notée : \(g.label.lowercased())"
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: g.symbol).font(.title3)
                                Text(g.label).font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.onBrand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(g.color.gradient))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            .padding(16)
            .glass(24)
            .padding(.top, 10)
        }
    }

    // La barre de lecture.
    private var controls: some View {
        @Bindable var rec = recitation
        let playingHere = recitation.current.map { c in ayat.contains(c.g) } ?? false
        return VStack(spacing: 8) {
            if let error = recitation.error {
                Text(error).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            HStack(spacing: 14) {
                Menu {
                    Picker("Récitateur", selection: $reciterID) {
                        ForEach(Reciter.all) { r in
                            Text(r.name).tag(r.id)
                        }
                    }
                } label: {
                    Image(systemName: "person.wave.2.fill").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Récitateur")

                Menu {
                    Picker("Répéter chaque verset", selection: $rec.repeatEach) {
                        Text("1 fois").tag(1)
                        Text("3 fois").tag(3)
                        Text("5 fois").tag(5)
                        Text("10 fois").tag(10)
                        Text("20 fois").tag(20)
                        Text("Sans fin").tag(0)
                    }
                    Toggle("Reprendre au début à la fin", systemImage: "repeat", isOn: $rec.loopAll)
                } label: {
                    ZStack {
                        Image(systemName: "repeat")
                        Text(recitation.repeatEach == 0 ? "∞" : "\(recitation.repeatEach)")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(3)
                            .background(Circle().fill(Color.brand))
                            .foregroundStyle(Color.onBrand)
                            .offset(x: 11, y: -10)
                    }
                    .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Répétition")

                Button {
                    if playingHere { recitation.toggle() } else { play(from: 0) }
                } label: {
                    Group {
                        if recitation.loading && playingHere {
                            ProgressView().tint(Color.onBrand)
                        } else {
                            Image(systemName: recitation.isPlaying && playingHere ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                    }
                    .foregroundStyle(Color.onBrand)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Color.brand.gradient))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(recitation.isPlaying ? "Pause" : "Écouter")

                Menu {
                    Picker("Vitesse", selection: $rec.speed) {
                        Text("0,5×").tag(Float(0.5))
                        Text("0,75×").tag(Float(0.75))
                        Text("Normale").tag(Float(1))
                        Text("1,25×").tag(Float(1.25))
                        Text("1,5×").tag(Float(1.5))
                    }
                } label: {
                    Text(speedLabel)
                        .font(.footnote.weight(.bold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Vitesse")

                Button { showRecorder = true } label: {
                    Image(systemName: "mic.fill").frame(width: 40, height: 40)
                }
                .accessibilityLabel("M’enregistrer")
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule()
        }
        .padding(.bottom, 6)
    }

    private var speedLabel: String {
        switch recitation.speed {
        case 0.5: return "0,5×"
        case 0.75: return "0,75×"
        case 1.25: return "1,25×"
        case 1.5: return "1,5×"
        default: return "1×"
        }
    }

    private func play(from i: Int) {
        let refs = ayat.map { g -> AyahRef in
            let r = store.ref(g)
            return AyahRef(g: g, surah: r.surah, ayah: r.ayah)
        }
        recitation.play(refs, from: i, title: title)
    }
}

/// Un verset sur une carte « papier » : texte coloré, numéro, et caché en mode test.
struct AyahCard: View {
    let g: Int
    let size: Double
    let tajweed: Bool
    let hidden: Bool
    let playing: Bool
    var onTap: () -> Void
    @Environment(QuranStore.self) private var store

    var body: some View {
        let r = store.ref(g)
        VStack(alignment: .trailing, spacing: 10) {
            HStack {
                Text("\(r.ayah)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                if playing {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brand)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                Spacer()
                Text("p. \(store.page(g))").font(.caption2).foregroundStyle(.tertiary)
            }
            if let ayah = store.ayah(g) {
                if hidden {
                    let words = ayah.t.components(separatedBy: " ").count
                    let first = Mushaf.ayahText(ayah, number: r.ayah, piece: .init(ayah: r.ayah, from: 0, to: 1, total: words),
                                                rules: store.rules, tajweed: tajweed, size: size, ink: .label, ornament: .secondaryLabel)
                    VStack(alignment: .trailing, spacing: 8) {
                        QuranLabel(text: first.rightToLeft())
                        HStack(spacing: 6) {
                            ForEach(0..<min(5, max(1, words - 1)), id: \.self) { i in
                                Capsule().fill(Color.primary.opacity(0.1)).frame(width: CGFloat(28 + (i * 17) % 40), height: 10)
                            }
                            Spacer()
                            Label("Touche pour voir", systemImage: "eye").font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    }
                } else {
                    QuranLabel(text: Mushaf.ayahText(ayah, number: r.ayah,
                                                     piece: .init(ayah: r.ayah, from: 0, to: ayah.t.components(separatedBy: " ").count,
                                                                  total: ayah.t.components(separatedBy: " ").count),
                                                     rules: store.rules, tajweed: tajweed, size: size,
                                                     ink: .label, ornament: .secondaryLabel).rightToLeft())
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(playing ? Color.primary : Color.primary.opacity(0.08), lineWidth: playing ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.25), value: playing)
    }
}

/// S'enregistrer en train de réciter, et se réécouter.
struct RecorderSheet: View {
    let title: String
    @Environment(VoiceRecorder.self) private var recorder
    @Environment(Recitation.self) private var recitation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        Text(recorder.recording ? timeString(recorder.elapsed) : "Récite, puis réécoute-toi")
                            .font(recorder.recording ? .system(size: 40, weight: .semibold, design: .rounded).monospacedDigit() : .headline)
                        Button {
                            if recorder.recording {
                                recorder.stop()
                            } else {
                                if recitation.isPlaying { recitation.toggle() }
                                Task { await recorder.start(title: title) }
                            }
                        } label: {
                            ZStack {
                                Circle().strokeBorder(Color.primary, lineWidth: 3).frame(width: 86, height: 86)
                                RoundedRectangle(cornerRadius: recorder.recording ? 8 : 30, style: .continuous)
                                    .fill(Color.primary)
                                    .frame(width: recorder.recording ? 30 : 60, height: recorder.recording ? 30 : 60)
                            }
                        }
                        .buttonStyle(PressStyle())
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: recorder.recording)
                        .accessibilityLabel(recorder.recording ? "Arrêter" : "Enregistrer")
                        if recorder.denied {
                            Text("Autorise le micro dans Réglages › Wird pour t’enregistrer.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                if !recorder.list.isEmpty {
                    Section("Mes enregistrements") {
                        ForEach(recorder.list) { r in
                            Button { recorder.play(r) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: recorder.playing == r.url ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Color.brand)
                                    Text(r.name).foregroundStyle(.primary).lineLimit(2)
                                }
                            }
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) { recorder.delete(r) }
                                ShareLink(item: r.url) { Label("Partager", systemImage: "square.and.arrow.up") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("M’enregistrer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if recorder.recording { recorder.stop() }
                        recorder.stopPlaying()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
