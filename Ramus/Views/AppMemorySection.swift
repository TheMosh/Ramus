import Charts
import SwiftUI

struct AppMemorySection: View {
    let apps: [AppMemoryUsage]

    @State private var hoveredKey: String?

    private let visibleCount = 10
    private let rowHeight: CGFloat = 26

    private var topApps: [AppMemoryUsage] { Array(apps.prefix(visibleCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Apps")
                    .font(.headline)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if topApps.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: rowHeight * 3)
            } else {
                chart
            }
        }
    }

    private var detail: String {
        if let hovered = topApps.first(where: { $0.key == hoveredKey }) {
            let processes = hovered.processCount == 1 ? "1 process" : "\(hovered.processCount) processes"
            return "\(hovered.name) · \(processes)"
        }
        let total = apps.reduce(0) { $0 + $1.bytes }
        return "\(MemoryFormat.string(total)) across \(apps.count) apps"
    }

    private var chart: some View {
        // Leave room past the longest bar for its value label.
        let maxGigabytes = MemoryFormat.gigabytes(topApps.first?.bytes ?? 0)

        return HStack(alignment: .top, spacing: 8) {
            // Names sit beside the chart rather than in its axis so app icons render reliably;
            // each row matches one band of the chart's categorical scale.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(topApps) { app in
                    AppRowLabel(app: app)
                        .frame(height: rowHeight)
                        .opacity(isDimmed(app) ? 0.45 : 1)
                }
            }
            .frame(width: 120, alignment: .leading)

            Chart(topApps) { app in
                BarMark(
                    x: .value("Memory", MemoryFormat.gigabytes(app.bytes)),
                    y: .value("App", app.key),
                    height: .fixed(14)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(4)
                .opacity(isDimmed(app) ? 0.35 : 1)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text(MemoryFormat.string(app.bytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(app.name)
                .accessibilityValue(MemoryFormat.string(app.bytes))
            }
            .chartXScale(domain: 0...max(maxGigabytes * 1.35, 0.01))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
        .frame(height: CGFloat(topApps.count) * rowHeight)
        .contentShape(.rect)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let row = Int(location.y / rowHeight)
                hoveredKey = topApps.indices.contains(row) ? topApps[row].key : nil
            case .ended:
                hoveredKey = nil
            }
        }
        .animation(.smooth, value: topApps.map(\.bytes))
    }

    private func isDimmed(_ app: AppMemoryUsage) -> Bool {
        hoveredKey != nil && hoveredKey != app.key
    }
}

private struct AppRowLabel: View {
    let app: AppMemoryUsage

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(app.name)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
