import SwiftUI
import WidgetKit

// MARK: - Envoie aux widgets ce qu'il y a à faire, et récupère ce qui y a été coché

@MainActor
enum WidgetBridge {
    /// Les cases cochées sur les widgets depuis la dernière ouverture : on les enregistre dans le journal.
    static func applyChecks(_ j: Journal, _ q: QuranStore) {
        guard q.loaded else { return }
        let checks = WidgetCheck.all()
        guard !checks.isEmpty else { return }
        WidgetCheck.save([])
        j.applyWidgetChecks(checks, q)
    }

    static func publish(_ j: Journal, _ q: QuranStore) {
        guard q.loaded else { return }
        let now = Date()
        // Demain à 0 h 01 : ce que le widget affichera après minuit.
        let tomorrow = Day.add(1, to: Day.start(now)).addingTimeInterval(60)
        var snap = WidgetSnapshot(today: day(j, q, now), tomorrow: day(j, q, tomorrow))
        snap.hasLearning = j.learning != nil

        // Demain, si tu coches (ou décoches) aujourd'hui depuis le widget.
        if let l = j.learningFlipped(q, now: now) {
            snap.tomorrowLearningAlt = part(j.learningChunk(q, now: tomorrow, using: l), q)
        }
        if let r = j.revisionFlipped(q, now: now) {
            snap.tomorrowRevisionAlt = part(j.revisionChunk(q, now: tomorrow, using: r), q)
        }

        // Le planning des prochains jours.
        snap.week = j.learningForecast(q, from: now, days: 8).dropFirst().map { f -> WidgetPlanDay in
            let ayat = Array(f.chunk.ayat)
            return WidgetPlanDay(key: Day.key(f.date), date: f.date,
                                 title: Passage.label(ayat, q).replacingOccurrences(of: "\n", with: " · "),
                                 count: ayat.count)
        }

        if let c = j.course {
            let ayat = j.learnedSinceCourse(q, now: now)
            snap.course = WidgetCourse(
                weekday: c.weekday, hour: c.hour ?? 19, minute: c.minute ?? 0,
                goal: j.learning?.pagesPerWeek ?? 0,
                done: q.pages(ayat, 0, ayat.count),
                forDate: j.nextCourse(after: now) ?? now,
                recite: ayat.isEmpty ? nil : Passage.label(ayat, q).replacingOccurrences(of: "\n", with: " · ")
            )
        }
        snap.activeDays = (0..<120).map { Day.add(-$0, to: Day.start(now)) }.filter { j.active($0) }.map { Day.key($0) }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func day(_ j: Journal, _ q: QuranStore, _ date: Date) -> WidgetDay {
        var d = WidgetDay(key: Day.key(date))
        d.learning = part(j.learningChunk(q, now: date), q)
        d.revision = part(j.revisionChunk(q, now: date), q)
        if let plan = j.coursePlan(q, now: date) {
            let when = plan.daysLeft == 1 ? "Cours demain" : "Cours dans \(plan.daysLeft) j"
            d.plan = plan.reached ? "\(when) · objectif atteint" : "\(when) · ≈ \(Num.pagesLabel(plan.today))/jour"
        }
        return d
    }

    private static func part(_ c: DayChunk?, _ q: QuranStore) -> WidgetPart? {
        guard let c, !c.isEmpty else { return nil }
        let ayat = Array(c.ayat)
        let pages = q.pages(of: ayat)
        var place = ""
        if let lo = pages.min(), let hi = pages.max() {
            place = lo == hi ? "page \(lo)" : "pages \(lo)–\(hi)"
        }
        return WidgetPart(title: Passage.label(ayat, q), detail: Passage.detail(ayat, pages), done: c.done,
                          count: ayat.count, from: c.from, to: c.to, place: place)
    }
}
