import UIKit

// MARK: - Couleurs du tajwid

/// Couleurs habituelles des Mushaf tajwid (même code que la plupart des éditions et des sites).
enum Tajweed {
    static func color(_ rule: String) -> UIColor {
        switch rule {
        case "hamzat_wasl", "silent", "lam_shamsiyyah": return UIColor(hex: 0x9A9A9A)
        case "madd_2": return UIColor(hex: 0x537FFF)
        case "madd_246": return UIColor(hex: 0x4050FF)
        case "madd_munfasil", "madd_muttasil": return UIColor(hex: 0x2144C1)
        case "madd_6": return UIColor(hex: 0x000EBC)
        case "qalqalah": return UIColor(hex: 0xDD0008)
        case "ikhfa": return UIColor(hex: 0x9400A8)
        case "ikhfa_shafawi": return UIColor(hex: 0xD500B7)
        case "iqlab": return UIColor(hex: 0x26BFFD)
        case "idghaam_ghunnah": return UIColor(hex: 0x169777)
        case "idghaam_no_ghunnah": return UIColor(hex: 0x169200)
        case "idghaam_shafawi": return UIColor(hex: 0x58B800)
        case "idghaam_mutajanisayn", "idghaam_mutaqaribayn": return UIColor(hex: 0xA1A1A1)
        case "ghunnah": return UIColor(hex: 0xFF7E1E)
        default: return Mushaf.ink
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Mise en page du Mushaf

enum Mushaf {
    static let paper = UIColor(hex: 0xF6F0E2)
    static let ink = UIColor(hex: 0x1C1A16)
    static let ornament = UIColor(hex: 0x9C7A3C)
    static let fontSize: CGFloat = 25

    /// Un morceau de page : un verset entier, ou une partie d'un très long verset (mots `from..<to`).
    struct Piece: Hashable {
        let ayah: Int
        let from: Int
        let to: Int
        let total: Int
        var isWhole: Bool { from == 0 && to == total }
    }

    /// Une page : une suite de versets d'une même sourate.
    struct Page: Hashable {
        let surah: Int
        let index: Int
        let opensSurah: Bool
        let pieces: [Piece]
        var firstAyah: Int { pieces.first?.ayah ?? 1 }
    }

    private static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .justified
        p.baseWritingDirection = .rightToLeft
        p.lineHeightMultiple = 1.18
        p.lineSpacing = 6
        return p
    }

    private static var centered: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.baseWritingDirection = .rightToLeft
        p.paragraphSpacing = 6
        return p
    }

    /// Le texte d'un verset (ou d'une partie), coloré selon le tajwid, suivi du numéro du verset.
    static func ayahText(_ ayah: Ayah, number: Int, piece: Piece, rules: [String], tajweed: Bool,
                         size: CGFloat = fontSize, ink: UIColor = Mushaf.ink) -> NSAttributedString {
        let font = Fonts.quran(size)
        let full = ayah.t as NSString
        // Bornes du morceau, en caractères (les mots sont séparés par des espaces).
        var range = NSRange(location: 0, length: full.length)
        if !piece.isWhole {
            let words = ayah.t.components(separatedBy: " ")
            let before = words.prefix(piece.from).reduce(0) { $0 + ($1 as NSString).length + 1 }
            let length = words[piece.from..<piece.to].reduce(0) { $0 + ($1 as NSString).length + 1 } - 1
            range = NSRange(location: before, length: max(0, min(length, full.length - before)))
        }
        let out = NSMutableAttributedString(string: full.substring(with: range),
                                            attributes: [.font: font, .foregroundColor: ink])
        if tajweed {
            for a in ayah.j where a.count == 3 {
                let s = a[0] - range.location, e = a[1] - range.location
                let lo = max(0, s), hi = min(range.length, e)
                guard hi > lo, rules.indices.contains(a[2]) else { continue }
                out.addAttribute(.foregroundColor, value: Tajweed.color(rules[a[2]]), range: NSRange(location: lo, length: hi - lo))
            }
        }
        if piece.to == piece.total {
            // Fin de verset : ۝ suivi du numéro, que la police entoure d'un ornement.
            out.append(NSAttributedString(string: " \u{06DD}" + number.arabicDigits + " ",
                                          attributes: [.font: font, .foregroundColor: ornament]))
        } else {
            out.append(NSAttributedString(string: " ", attributes: [.font: font]))
        }
        return out
    }

    /// La basmala, prise telle quelle dans le texte (1:1) — jamais retapée à la main.
    nonisolated(unsafe) static var basmala = ""

    /// En-tête de sourate : son nom, puis la basmala.
    static func header(_ surah: Surah) -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: "سُورَةُ " + surah.ar + "\n", attributes: [
            .font: Fonts.quran(fontSize + 3), .foregroundColor: ornament, .paragraphStyle: centered
        ]))
        if surah.basmala, !basmala.isEmpty {
            out.append(NSAttributedString(string: basmala + "\n", attributes: [
                .font: Fonts.quran(fontSize), .foregroundColor: ink, .paragraphStyle: centered
            ]))
        }
        return out
    }

    /// Tout le texte d'une page, prêt à afficher.
    static func text(for page: Page, surah: Surah, rules: [String], tajweed: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if page.opensSurah { out.append(header(surah)) }
        let body = NSMutableAttributedString()
        for p in page.pieces where surah.ayat.indices.contains(p.ayah - 1) {
            body.append(ayahText(surah.ayat[p.ayah - 1], number: p.ayah, piece: p, rules: rules, tajweed: tajweed))
        }
        body.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: body.length))
        out.append(body)
        return out
    }

    static func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height.rounded(.up)
    }

    /// Découpe une sourate en pages qui tiennent dans `size` (les versets ne sont coupés que s'ils dépassent une page).
    static func paginate(_ surah: Surah, size: CGSize, rules: [String]) -> [Page] {
        var pages: [Page] = []
        var pieces: [Piece] = []
        let limit = size.height * 0.97
        func flush() {
            guard !pieces.isEmpty else { return }
            pages.append(Page(surah: surah.n, index: pages.count, opensSurah: pages.isEmpty, pieces: pieces))
            pieces = []
        }
        func fits(_ candidate: [Piece]) -> Bool {
            let page = Page(surah: surah.n, index: pages.count, opensSurah: pages.isEmpty, pieces: candidate)
            return height(text(for: page, surah: surah, rules: rules, tajweed: false), width: size.width) <= limit
        }
        for (i, ayah) in surah.ayat.enumerated() {
            let total = ayah.t.components(separatedBy: " ").count
            let whole = Piece(ayah: i + 1, from: 0, to: total, total: total)
            if fits(pieces + [whole]) { pieces.append(whole); continue }
            flush()
            if fits([whole]) { pieces.append(whole); continue }
            // Verset plus long qu'une page : coupé entre deux mots, sur plusieurs pages.
            var from = 0
            while from < total {
                var lo = from + 1, hi = total
                while lo < hi {
                    let mid = (lo + hi + 1) / 2
                    if fits(pieces + [Piece(ayah: i + 1, from: from, to: mid, total: total)]) { lo = mid } else { hi = mid - 1 }
                }
                pieces.append(Piece(ayah: i + 1, from: from, to: lo, total: total))
                from = lo
                if from < total { flush() }
            }
        }
        flush()
        return pages
    }
}
