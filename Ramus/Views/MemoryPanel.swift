import SwiftUI

struct MemoryPanel: View {
    @Environment(MemoryMonitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let system = monitor.system {
                SystemMemorySection(system: system, history: monitor.history)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            Divider()

            AppMemorySection(apps: monitor.apps)

            Divider()

            PanelFooter()
        }
        .padding(16)
        .frame(width: 360)
        .onAppear { monitor.isPanelVisible = true }
        // MenuBarExtra can keep its content alive between openings, so follow the panel's
        // key state too; it is the only window Ramus shows.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            monitor.isPanelVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            monitor.isPanelVisible = false
        }
    }
}
