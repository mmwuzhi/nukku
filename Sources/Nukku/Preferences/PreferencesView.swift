import SwiftUI

struct PreferencesView: View {
    @State private var prefs = PreferencesManager.shared
    @State private var launchService = LaunchAtLoginService()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(0)

            widgetsTab
                .tabItem { Label("Widgets", systemImage: "rectangle.3.group") }
                .tag(1)

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(width: 480, height: 340)
    }

    private var generalTab: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { launchService.isEnabled },
                    set: { _ in launchService.toggle() }
                ))
            }
            Section("交互") {
                Picker("展开方式", selection: $prefs.expandTrigger) {
                    ForEach(ExpandTrigger.allCases) { trigger in
                        Text(trigger.label).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("展开延迟") {
                    Slider(value: $prefs.expandDelay, in: 0...0.5, step: 0.05)
                    Text(String(format: "%.2fs", prefs.expandDelay))
                        .frame(width: 36)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("收起延迟") {
                    Slider(value: $prefs.collapseDelay, in: 0.1...1.0, step: 0.05)
                    Text(String(format: "%.2fs", prefs.collapseDelay))
                        .frame(width: 36)
                        .foregroundStyle(.secondary)
                }
            }
            Section("全局快捷键") {
                Toggle("启用快捷键", isOn: $prefs.hotkeyEnabled)
                if prefs.hotkeyEnabled {
                    Picker("快捷键", selection: $prefs.hotkeyPreset) {
                        ForEach(HotkeyPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("需要在系统设置 › 隐私与安全性 › 辅助功能中授权此 app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
            Text("版本 1.0.0")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
