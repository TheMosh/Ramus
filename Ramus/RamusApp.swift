import SwiftUI

@main
struct RamusApp: App {
    @State private var monitor = MemoryMonitor()

    var body: some Scene {
        MenuBarExtra {
            MemoryPanel()
                .environment(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case available
    case usedPercentage
    case iconOnly

    static let storageKey = "menuBarDisplay"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .available: "Available Memory"
        case .usedPercentage: "Memory Used (%)"
        case .iconOnly: "Icon Only"
        }
    }
}

struct MenuBarLabel: View {
    let monitor: MemoryMonitor
    @AppStorage(MenuBarDisplay.storageKey) private var display = MenuBarDisplay.available

    var body: some View {
        if let summary = monitor.menuBarSummary, let text = text(for: summary) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                Text(text).monospacedDigit()
            }
            .accessibilityLabel("Memory: \(summary.available) available")
        } else {
            Image(systemName: "memorychip")
                .accessibilityLabel("Ramus")
        }
    }

    private func text(for summary: MenuBarSummary) -> String? {
        switch display {
        case .available: summary.available
        case .usedPercentage: summary.usedPercentage
        case .iconOnly: nil
        }
    }
}
