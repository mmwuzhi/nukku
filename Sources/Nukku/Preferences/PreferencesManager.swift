import AppKit
import SwiftUI
import Observation

enum ExpandTrigger: String, CaseIterable, Identifiable {
    case hover = "hover"
    case click = "click"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hover:
            L10n.tr("preferences.expandTrigger.hover", "鼠标悬停")
        case .click:
            L10n.tr("preferences.expandTrigger.click", "点击")
        }
    }
}

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case cmdShiftN     = "cmdShiftN"
    case cmdOptionN    = "cmdOptionN"
    case ctrlShiftN    = "ctrlShiftN"
    case cmdShiftSpace = "cmdShiftSpace"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cmdShiftN:     return "⌘⇧N"
        case .cmdOptionN:    return "⌘⌥N"
        case .ctrlShiftN:    return "⌃⇧N"
        case .cmdShiftSpace: return "⌘⇧Space"
        }
    }
    var components: (NSEvent.ModifierFlags, UInt16) {
        switch self {
        case .cmdShiftN:     return ([.command, .shift], 45)
        case .cmdOptionN:    return ([.command, .option], 45)
        case .ctrlShiftN:    return ([.control, .shift], 45)
        case .cmdShiftSpace: return ([.command, .shift], 49)
        }
    }
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

    @ObservationIgnored
    @AppStorage("hotkeyEnabled") private var hotkeyEnabledRaw: Bool = false
    var hotkeyEnabled: Bool {
        get { hotkeyEnabledRaw }
        set { hotkeyEnabledRaw = newValue }
    }

    @ObservationIgnored
    @AppStorage("hotkeyPreset") private var hotkeyPresetRaw: String = HotkeyPreset.cmdShiftN.rawValue
    var hotkeyPreset: HotkeyPreset {
        get { HotkeyPreset(rawValue: hotkeyPresetRaw) ?? .cmdShiftN }
        set { hotkeyPresetRaw = newValue.rawValue }
    }

    @ObservationIgnored
    @AppStorage("showMediaDiagnostics") private var showMediaDiagnosticsRaw: Bool = false
    var showMediaDiagnostics: Bool {
        get { showMediaDiagnosticsRaw }
        set { showMediaDiagnosticsRaw = newValue }
    }

    // Calendar identifiers the user has hidden in the calendar widget. Stored as a
    // newline-joined string because @AppStorage cannot hold a Set.
    @ObservationIgnored
    @AppStorage("hiddenCalendarIDs") private var hiddenCalendarIDsRaw: String = ""
    var hiddenCalendarIDs: Set<String> {
        get { Set(hiddenCalendarIDsRaw.split(separator: "\n").map(String.init)) }
        set { hiddenCalendarIDsRaw = newValue.sorted().joined(separator: "\n") }
    }

    func hotkeyComponents() -> (NSEvent.ModifierFlags, UInt16) {
        hotkeyPreset.components
    }

    private init() {}
}
