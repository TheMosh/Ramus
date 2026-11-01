import ServiceManagement
import SwiftUI

struct PanelFooter: View {
    @AppStorage(MenuBarDisplay.storageKey) private var display = MenuBarDisplay.available
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Button("Activity Monitor", systemImage: "gauge.with.dots.needle.33percent", action: openActivityMonitor)
                .buttonStyle(.borderless)

            Spacer()

            Menu {
                Picker("Show in Menu Bar", selection: $display) {
                    ForEach(MenuBarDisplay.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Divider()
                Button("Quit Ramus") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Settings")
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
