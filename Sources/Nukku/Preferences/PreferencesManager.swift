import SwiftUI
import Observation

enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover = "hover"
    case click = "click"
    var id: String { rawValue }
    var label: String { self == .hover ? "鼠标悬停" : "点击" }
}

@Observable
@MainActor
final class PreferencesManager {
    static let shared = PreferencesManager()

    @ObservationIgnored
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = true

    @ObservationIgnored
    @AppStorage("expandTrigger") private var expandTriggerRaw: String = ExpandTrigger.hover.rawValue
    var expandTrigger: ExpandTrigger {
        get { ExpandTrigger(rawValue: expandTriggerRaw) ?? .hover }
        set { expandTriggerRaw = newValue.rawValue }
    }

    @ObservationIgnored
    @AppStorage("expandDelay") var expandDelay: Double = 0.1

    @ObservationIgnored
    @AppStorage("collapseDelay") var collapseDelay: Double = 0.3

    private init() {}
}
