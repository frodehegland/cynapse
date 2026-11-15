// WeeklyChecks.swift — the probation that never ends (brief, 2.8).
//
// Each week, for every downloaded model and Apple's, a short re-check: the
// repeated questions and a random draw. It runs only on mains power, one
// model at a time, while Cynapse is open (Settings can open it at login).
// The person hears about it only if the answers changed: two or more
// repeated questions in a week, or a values or candour question two weeks
// running. Cloud models aren't re-checked automatically, since each check
// costs the person money; they are profiled centrally each month instead.

import Foundation
import IOKit.ps
import UserNotifications
import ServiceManagement
import ModelCheck

struct WatchEntry: Codable, Hashable {
    var date: Date
    var changed: [String]
    var alert: Bool
}

@MainActor
enum WeeklyChecks {

    static let enabledKey = "WeeklyChecksEnabled"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static let interval: TimeInterval = 7 * 24 * 3600

    static func start(_ app: AppModel) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            while true {
                tick(app)
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    /// Starts the next re-check that is due, if any and if it's a good time.
    static func tick(_ app: AppModel) {
        guard enabled, app.runningEntry == nil, onMainsPower else { return }
        for entry in app.entries {
            if case .cloud = entry.kind { continue }
            // The Analysis Check is asked once, never re-checked weekly.
            guard let latest = app.profiles[entry.id]?.first(where: { $0.profile.run.kind != .analysis }), Date().timeIntervalSince(latest.date) > interval else { continue }
            // A model whose files changed needs a full check, not a re-check.
            if app.status(of: entry) == "changed" { continue }
            app.startCheck(entry, mode: .weekly)
            return
        }
    }

    /// The seed for this week's draw for this model, so the draw can be
    /// repeated by anyone with the same week and model.
    static func seed(for entry: ModelEntry, date: Date = Date()) -> UInt64 {
        let week = UInt64(date.timeIntervalSince1970 / interval)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in entry.id.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash ^ week
    }

    static var onMainsPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return true }
        return type == kIOPMACPowerKey
    }

    // MARK: After a re-check

    static func watchURL(for entry: ModelEntry) -> URL {
        ProfileStore.folder(for: entry).appendingPathComponent("watch.json")
    }

    static func watchLog(for entry: ModelEntry) -> [WatchEntry] {
        guard let data = try? Data(contentsOf: watchURL(for: entry)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([WatchEntry].self, from: data)) ?? []
    }

    /// Compares a finished re-check with the model's last full or quick
    /// check, records it, and tells the person if the answers changed.
    static func finished(_ weekly: StoredProfile, entry: ModelEntry, profiles: [StoredProfile], bank: Bank) {
        guard let install = profiles.first(where: { $0.profile.run.kind == .quick || $0.profile.run.kind == .full }) else { return }
        let before = Scorer.outcomes(ProfileStore.records(of: install), bank: bank)
        let now = Scorer.outcomes(ProfileStore.records(of: weekly), bank: bank)
        let changed = Drift.changed(since: before, now: now, sentinels: bank.sentinels,
                                    noise: install.profile.consistency.noiseFloorItems)
        var log = watchLog(for: entry)
        let alert = Drift.alerts(changedThisWeek: changed, changedLastWeek: log.last?.changed ?? [], bank: bank)
        log.append(WatchEntry(date: Date(), changed: changed, alert: alert))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(log).write(to: watchURL(for: entry))
        if alert { notify(entry: entry, count: changed.count) }
    }

    static func notify(entry: ModelEntry, count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(entry.name)'s answers have changed"
            content.body = "Since you checked it, it answered \(count) of the repeated questions differently. Open Cynapse to see before and after."
            center.add(UNNotificationRequest(identifier: "cynapse-\(entry.storeKey)-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
        }
    }

    // MARK: Opening at login

    static var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
