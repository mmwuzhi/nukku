import SwiftUI

struct PreferencesView: View {
    @State private var prefs = PreferencesManager.shared
    @State private var launchService = LaunchAtLoginService()
    @State private var selectedTab = 0
    // @AppStorage is the persistence sink (HotkeyService reads the same key via
    // PreferencesManager). UI gating runs off a @State driver instead: @AppStorage
    // propagates async through UserDefaults, landing outside any animation
    // transaction, so the conditional rows wouldn't animate. We mutate the @State
    // synchronously inside withAnimation, which does animate the row insert/removal.
    @AppStorage("hotkeyEnabled") private var hotkeyEnabledStore = false
    @State private var hotkeyEnabled = false

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label(L10n.tr("preferences.general", "通用"), systemImage: "gearshape") }
                .tag(0)

            widgetsTab
                .tabItem { Label(L10n.tr("preferences.widgets", "Widgets"), systemImage: "rectangle.3.group") }
                .tag(1)

            aboutTab
                .tabItem { Label(L10n.tr("preferences.about", "关于"), systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 480, height: 340)
    }

    private var generalTab: some View {
        Form {
            Section(L10n.tr("preferences.launch", "启动")) {
                Toggle(L10n.tr("preferences.launchAtLogin", "登录时自动启动"), isOn: Binding(
                    get: { launchService.isEnabled },
                    set: { _ in launchService.toggle() }
                ))
            }
            Section(L10n.tr("preferences.interaction", "交互")) {
                Picker(L10n.tr("preferences.expandTrigger", "展开方式"), selection: $prefs.expandTrigger) {
                    ForEach(ExpandTrigger.allCases) { trigger in
                        Text(trigger.label).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(L10n.tr("preferences.expandDelay", "展开延迟")) {
                    Slider(value: $prefs.expandDelay, in: 0...0.5, step: 0.05)
                    Text(String(format: "%.2fs", prefs.expandDelay))
                        .frame(width: 36)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L10n.tr("preferences.collapseDelay", "收起延迟")) {
                    Slider(value: $prefs.collapseDelay, in: 0.1...1.0, step: 0.05)
                    Text(String(format: "%.2fs", prefs.collapseDelay))
                        .frame(width: 36)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L10n.tr("preferences.globalHotkey", "全局快捷键")) {
                Toggle(L10n.tr("preferences.enableHotkey", "启用快捷键"), isOn: Binding(
                    get: { hotkeyEnabled },
                    set: { newValue in
                        hotkeyEnabledStore = newValue            // persist for HotkeyService
                        withAnimation(.snappy) { hotkeyEnabled = newValue }
                    }
                ))
                if hotkeyEnabled {
                    Picker(L10n.tr("preferences.hotkey", "快捷键"), selection: $prefs.hotkeyPreset) {
                        ForEach(HotkeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(L10n.tr("preferences.accessibilityHint", "需要在系统设置 › 隐私与安全性 › 辅助功能中授权此 app"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L10n.tr("preferences.diagnostics", "诊断")) {
                Toggle(L10n.tr("preferences.showMediaDiagnostics", "显示媒体诊断"), isOn: $prefs.showMediaDiagnostics)
                Text(L10n.tr("preferences.mediaDiagnosticsDescription", "在媒体 widget 中显示来源、状态和补全信息，并输出诊断日志"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { hotkeyEnabled = hotkeyEnabledStore }
        .formStyle(.grouped)
        .padding()
    }

    private var widgetsTab: some View {
        let registry = WidgetRegistry.shared
        return List {
            ForEach(registry.widgets) { widget in
                HStack {
                    Image(systemName: widget.iconName)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(widget.displayName)
                    Spacer()
                    Toggle("", isOn: Bindable(widget).isEnabled)
                        .labelsHidden()
                }
            }
        }
        .listStyle(.inset)
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("Nukku")
                .font(.largeTitle.bold())
            Text(L10n.tr("preferences.version", "版本 1.0.0"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
