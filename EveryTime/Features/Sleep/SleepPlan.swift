import Foundation

/// What the idle page offers: bed and wake from the picks, else the usual hours, else from now.
struct SleepPlan {
    /// Nap or Sleep after the nap block: inside the usual sleep hours it's always Sleep.
    let kind: SleepKind
    let choice: WakeChoice
    let sleepNow: SleepNow
    /// Why Nap is off right now; nil when it's allowed.
    let napBlocked: String?

    /// `pickedBed` at or before now means "now", for as long as `pickedWake` is still ahead.
    static func resolve(now: Date, kind: SleepKind, napMinutes: Int, pickedBed: Date?, pickedWake: Date?,
                        profile: JetLagProfile, nights: [PastNight], naps: [Nap] = [], calendar: Calendar = .current) -> SleepPlan {
        let advice = NapAdvice(profile: profile, calendar: calendar)
        let lastNight = nights.first { $0.end <= now }
        // Going back to sleep after the night keeps it going: just up is from the last of those.
        let resleeps = lastNight.map { night in naps.filter { $0.resleep == true && $0.start >= night.end && $0.end <= now } } ?? []
        let up = resleeps.map(\.end).max() ?? lastNight?.end
        let justWoke = up.map { (0..<PastNight.resleepWindow).contains(now.timeIntervalSince($0)) } ?? false
        let resleptAsleep = resleeps.reduce(0) { $0 + max(0, $1.duration - WakeCheck.fallBackAsleep) }
        let slept = nights.contains { $0.end <= now && now.timeIntervalSince($0.end) < 14 * 3600 }
        let blocked = napBlocked(profile, now: now, slept: slept, calendar: calendar)
        let kind = blocked == nil ? kind : .sleep

        let usualWake = { SleepSuggestion.nextOccurrence(ofMinutes: profile.usualWake, after: $0, calendar: calendar) }
        let tonight = SleepSuggestion.nextOccurrence(ofMinutes: profile.usualBedtime, after: now, calendar: calendar)
        let inUsualHours = usualWake(now) < tonight
        let longest = Double(SleepRing.lengths.upperBound) * 60
        let picked = pickedBed.flatMap { bed in
            bed.timeIntervalSince(now) >= 60 ? bed : pickedWake.map { (1...longest).contains($0.timeIntervalSince(now)) } == true ? now : nil
        }
        let bed = kind == .nap ? now : SleepRing.snap(picked ?? (justWoke || (inUsualHours && !slept) ? now : tonight))

        let resleep = kind == .sleep && justWoke && bed.timeIntervalSince(now) <= Double(SleepRing.step) * 30
        let shortfall = resleep ? lastNight.map { SleepTrend.need(profile) - $0.asleep - resleptAsleep } : nil
        let sleepNow = SleepNow(advice: advice, start: bed, resleepShortfall: shortfall)
        let shortest = WakeChoice(now: now, bed: bed, wake: bed, resleep: resleep).minLength
        let fits = { (wake: Date) in (shortest...longest).contains(wake.timeIntervalSince(bed)) ? wake : nil }
        let usual = fits(SleepRing.snap(usualWake(bed)))
        let long = sleepNow.pick.flatMap { fits(SleepRing.snap($0.time)) }
        let wake = kind == .nap ? bed.addingTimeInterval(Double(napMinutes) * 60)
            : SleepRing.snap(pickedWake.flatMap { (shortest - 60...longest).contains($0.timeIntervalSince(bed)) ? $0 : nil }
                ?? (resleep ? long ?? usual : usual ?? long) ?? bed.addingTimeInterval(8 * 3600))
        return SleepPlan(kind: kind, choice: WakeChoice(now: now, bed: bed, wake: wake, resleep: resleep),
                         sleepNow: sleepNow, napBlocked: blocked)
    }

    /// Within an hour of the usual bedtime, or inside the usual night before having slept.
    static func napBlocked(_ profile: JetLagProfile, now: Date, slept: Bool, calendar: Calendar = .current) -> String? {
        let minute = calendar.minutesOfDay(now)
        let (bed, wake) = (profile.usualBedtime, profile.usualWake)
        let from = (bed - 60 + 24 * 60) % (24 * 60)
        let nearBed = from <= bed ? (from..<bed).contains(minute) : (minute >= from || minute < bed)
        let inNight = bed <= wake ? (bed...wake).contains(minute) : (minute >= bed || minute <= wake)
        guard nearBed || (inNight && !slept) else { return nil }
        return "It's within an hour of, or inside, your usual sleep hours (\(bed.timeOfDayText) – \(wake.timeOfDayText)). Use Sleep instead."
    }
}
