import SwiftUI

// MARK: - Les repères du Coran (aucun texte : tu lis dans ton Mushaf en papier)

/// Une sourate : son nom et son nombre de versets.
struct Surah: Decodable, Identifiable {
    let n: Int
    let ar: String
    let tr: String
    let count: Int
    var id: Int { n }
}

/// Le fichier quran.json : les sourates, et pour chaque verset sa page, son juz et son quart de hizb.
struct QuranFile: Decodable {
    let source: String
    let surahs: [Surah]
    let page: [Int]
    let juz: [Int]
    /// Quart de hizb (rub‘) de chaque verset : 1…240.
    let rub: [Int]
}

@MainActor
@Observable
final class QuranStore {
    private(set) var surahs: [Surah] = []
    private(set) var loaded = false
    private(set) var error: String?

    // Index du Mushaf de Médine. Chaque verset a un numéro global : 0 (1:1) … 6235 (114:6).
    static let ayahCount = 6236
    private(set) var pageOf: [Int] = []
    private(set) var juzOf: [Int] = []
    private(set) var rubOf: [Int] = []
    private(set) var rubStart: [Int] = []
    private(set) var surahStart: [Int] = []
    private(set) var pageStart: [Int] = []
    private(set) var juzStart: [Int] = []
    /// Part de page de chaque verset (1 ÷ nombre de versets sur sa page).
    private(set) var weight: [Double] = []
    /// L'ordre d'apprentissage : du début (Al-Fâtiha → An-Nâs) ou de la fin (An-Nâs, Al-Falaq… → Al-Fâtiha).
    private(set) var forward: [Int] = []
    private(set) var backward: [Int] = []
    private var forwardIndex: [Int] = []
    private var backwardIndex: [Int] = []


    func load() async {
        guard !loaded else { return }
        guard let url = Bundle.main.url(forResource: "quran", withExtension: "json") else {
            error = "Le fichier des repères du Coran est introuvable dans l’app."
            return
        }
        do {
            let file = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(QuranFile.self, from: Data(contentsOf: url))
            }.value
            // Vérification : 114 sourates et 6 236 versets.
            let count = file.surahs.reduce(0) { $0 + $1.count }
            guard file.surahs.count == 114, count == Self.ayahCount,
                  file.page.count == count, file.juz.count == count, file.rub.count == count else {
                error = "Les repères du Coran sont incomplets."
                return
            }
            buildIndex(file)
            surahs = file.surahs
            loaded = true
        } catch {
            self.error = "Impossible de lire les repères du Coran. Renvoie bien le fichier quran.json de Wird 1.2."
        }
    }

    func surah(_ n: Int) -> Surah? {
        surahs.indices.contains(n - 1) ? surahs[n - 1] : nil
    }

    private func buildIndex(_ mushaf: QuranFile) {
        let list = mushaf.surahs
        var start: [Int] = []
        var g = 0
        for s in list { start.append(g); g += s.count }
        surahStart = start
        pageOf = mushaf.page
        juzOf = mushaf.juz
        rubOf = mushaf.rub
        var rs = Array(repeating: Self.ayahCount, count: 242)
        for i in stride(from: Self.ayahCount - 1, through: 0, by: -1) { rs[mushaf.rub[i]] = i }
        rs[0] = 0
        rubStart = rs
        // pageStart[p] = premier verset de la page p ; pageStart[605] = 6236 (fin).
        var ps = Array(repeating: Self.ayahCount, count: 606)
        var js = Array(repeating: Self.ayahCount, count: 32)
        for i in stride(from: Self.ayahCount - 1, through: 0, by: -1) {
            ps[mushaf.page[i]] = i
            js[mushaf.juz[i]] = i
        }
        ps[0] = 0
        js[0] = 0
        pageStart = ps
        juzStart = js
        var w = Array(repeating: 1.0, count: Self.ayahCount)
        for p in 1...604 {
            let r = ps[p]..<ps[p + 1]
            for g in r { w[g] = 1 / Double(max(1, r.count)) }
        }
        weight = w
        forward = Array(0..<Self.ayahCount)
        var back: [Int] = []
        for n in stride(from: list.count, through: 1, by: -1) {
            let lo = start[n - 1]
            back.append(contentsOf: lo..<(lo + list[n - 1].count))
        }
        backward = back
        forwardIndex = forward
        var bi = Array(repeating: 0, count: Self.ayahCount)
        for (i, g) in back.enumerated() { bi[g] = i }
        backwardIndex = bi
    }

    func sequence(_ d: Direction) -> [Int] { d == .forward ? forward : backward }

    /// Place d'un verset dans l'ordre choisi.
    func index(of g: Int, _ d: Direction) -> Int { d == .forward ? forwardIndex[g] : backwardIndex[g] }

    /// Nombre de pages (avec décimales) d'une suite de versets.
    func pages(_ seq: [Int], _ a: Int, _ b: Int) -> Double {
        guard b > a else { return 0 }
        var t = 0.0
        for i in max(0, a)..<min(b, seq.count) { t += weight[seq[i]] }
        return t
    }

    /// Avance d'environ `p` pages à partir de la position `a` (au moins 1 verset).
    func advance(_ seq: [Int], from a: Int, pages p: Double, limit: Int) -> Int {
        var i = a, t = 0.0
        while i < limit {
            let w = weight[seq[i]]
            if i > a, t + w / 2 > p { break }
            t += w
            i += 1
        }
        return max(min(a + 1, limit), i)
    }

    // MARK: Repères

    /// Numéro global d'un verset (sourate 1…114, verset 1…).
    func global(_ surah: Int, _ ayah: Int) -> Int { surahStart[surah - 1] + ayah - 1 }

    /// Sourate et verset d'un numéro global.
    func ref(_ g: Int) -> (surah: Int, ayah: Int) {
        let g = min(max(0, g), Self.ayahCount - 1)
        var lo = 0, hi = surahStart.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if surahStart[mid] <= g { lo = mid } else { hi = mid - 1 }
        }
        return (lo + 1, g - surahStart[lo] + 1)
    }

    func page(_ g: Int) -> Int { pageOf.indices.contains(g) ? pageOf[g] : 1 }
    func rub(_ g: Int) -> Int { rubOf.indices.contains(g) ? rubOf[g] : 1 }
    func hizb(_ g: Int) -> Int { (rub(g) + 3) / 4 }

    /// Hizb h (1…60) : ses versets.
    func hizbRange(_ h: Int) -> Range<Int> { rubStart[4 * h - 3]..<rubStart[min(241, 4 * h + 1)] }

    func juz(_ g: Int) -> Int { juzOf.indices.contains(g) ? juzOf[g] : 1 }

    func surahRange(_ n: Int) -> Range<Int> {
        let lo = surahStart[n - 1]
        return lo..<(n < 114 ? surahStart[n] : Self.ayahCount)
    }

    func pageRange(_ p: Int) -> Range<Int> { pageStart[p]..<pageStart[p + 1] }
    func juzRange(_ j: Int) -> Range<Int> { juzStart[j]..<juzStart[j + 1] }

    /// Les sourates présentes sur une page.
    func surahs(onPage p: Int) -> [Int] {
        let r = pageRange(p)
        guard !r.isEmpty else { return [] }
        return Array(ref(r.lowerBound).surah...ref(r.upperBound - 1).surah)
    }

    func name(_ surah: Int) -> String { self.surah(surah)?.tr ?? "Sourate \(surah)" }

    /// « Al-Mulk 5 ».
    func label(_ g: Int) -> String {
        let r = ref(g)
        return "\(name(r.surah)) \(r.ayah)"
    }

    /// « Al-Mulk 1 → 5 », ou « Al-Baqara 280 → Âl ‘Imrân 3 ».
    func label(from a: Int, to b: Int) -> String {
        let x = ref(a), y = ref(b)
        if a == b { return label(a) }
        if x.surah == y.surah {
            if x.ayah == 1, y.ayah == surah(x.surah)?.count { return name(x.surah) + " (entière)" }
            return "\(name(x.surah)) \(x.ayah) → \(y.ayah)"
        }
        return "\(name(x.surah)) \(x.ayah) → \(name(y.surah)) \(y.ayah)"
    }

    /// Pages couvertes par une liste de versets (dans l'ordre, sans doublon).
    func pages(of list: [Int]) -> [Int] {
        var out: [Int] = []
        for g in list { let p = page(g); if out.last != p, !out.contains(p) { out.append(p) } }
        return out
    }
}

