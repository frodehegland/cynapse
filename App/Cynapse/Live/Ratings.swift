// Ratings.swift — the colours of the ratings (ModelCheck's Assessment):
// green good, yellow acceptable, orange questionable, red wrong or a
// serious warning. A position on a contested question is never rated, and
// shows in a soft neutral light.

import SwiftUI
import ModelCheck

extension Assessment {
    var color: Color {
        switch self {
        case .good: Color(red: 0.32, green: 0.86, blue: 0.45)
        case .ok: Color(red: 1.0, green: 0.84, blue: 0.28)
        case .questionable: Color(red: 1.0, green: 0.56, blue: 0.18)
        case .wrong: Color(red: 1.0, green: 0.27, blue: 0.25)
        case .neutral: Color(red: 0.80, green: 0.80, blue: 0.95)
        }
    }
}

extension LiveState {
    /// Each scored result's rating, by item, situation and asking.
    func assessments(bank: Bank?) -> [String: Assessment] {
        var result: [String: Assessment] = [:]
        for entry in outcomes {
            result["\(entry.outcome.itemId)|\(entry.outcome.condition)|\(entry.outcome.pass)"] = entry.outcome.assessment(item: bank?.item(entry.outcome.itemId))
        }
        return result
    }
}

extension Exchange {
    /// The key its result is rated under: item, situation and asking.
    var outcomeKey: String {
        // key = item | part | date | context | depth | pass
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return key }
        return ([parts[0]] + parts[2..<(parts.count - 1)] + [parts[parts.count - 1]]).joined(separator: "|")
    }
}
