import SwiftUI
import WidgetKit

// MARK: - Envoie aux widgets ce qu'il y a à faire aujourd'hui et demain

@MainActor
enum WidgetBridge {
    static func publish(_ j: Journal, _ q: QuranStore) {
        guard q.loaded else { return }
        let now = Date()
        // Demain à 0 h 01 : ce que le widget affichera après minuit.
        let tomorrow = Day.add(1, to: Day.start(now)).addingTimeInterval(60)
        var snap = WidgetSnapshot(today: day(j, q, now), tomorrow: day(j, q, tomorrow))
        snap.hasLearning = j.learning != nil
        if let c = j.course {
            let ayat = j.learnedSinceCourse(q, now: now)
            let seq = ayat
            snap.course = WidgetCourse(
                weekday: c.weekday, hour: c.hour ?? 19, minute: c.minute ?? 0,
                goal: j.learning?.pagesPerWeek ?? 0,
                done: q.pages(seq, 0, seq.count),
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
        return WidgetPart(title: Passage.label(ayat, q), detail: Passage.detail(ayat, q.pages(of: ayat)), done: c.done)
    }
}
