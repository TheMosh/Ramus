import Charts
import SwiftUI

struct SystemMemorySection: View {
    let system: SystemMemory
    let history: [UsageSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ramus")
                    .font(.headline)
                Spacer()
                PressureBadge(pressure: system.pressure)
            }

            summary
            breakdownBar
            legend
            HistoryChart(history: history, total: system.total)
        }
    }

    private var summary: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MemoryFormat.string(system.available))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(MemoryFormat.string(system.used)) used")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(MemoryFormat.capacity(system.total))")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .animation(.smooth, value: system)
    }

    private var segments: [MemorySegment] {
        [
            MemorySegment(kind: .app, bytes: system.appMemory),
            MemorySegment(kind: .wired, bytes: system.wired),
            MemorySegment(kind: .compressed, bytes: system.compressed),
            MemorySegment(kind: .cached, bytes: system.cachedFiles),
            MemorySegment(kind: .free, bytes: system.free),
        ]
    }

    private var breakdownBar: some View {
        Chart(segments) { segment in
            BarMark(x: .value("Memory", MemoryFormat.gigabytes(segment.bytes)))
                .foregroundStyle(segment.kind.color)
                .accessibilityLabel(segment.kind.title)
                .accessibilityValue(MemoryFormat.string(segment.bytes))
        }
        .chartXScale(domain: 0...MemoryFormat.gigabytes(system.total))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 12)
        .clipShape(.rect(cornerRadius: 4))
        .animation(.smooth, value: system)
    }

    private var legend: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                LegendItem(kind: .app, bytes: system.appMemory)
                LegendItem(kind: .cached, bytes: system.cachedFiles)
            }
            GridRow {
                LegendItem(kind: .wired, bytes: system.wired)
                LegendItem(kind: .free, bytes: system.free)
            }
            GridRow {
                LegendItem(kind: .compressed, bytes: system.compressed)
                LegendItem(kind: .swap, bytes: system.swapUsed)
            }
        }
        .font(.callout)
    }
}

struct MemorySegment: Identifiable {
    enum Kind {
        case app, wired, compressed, cached, free, swap

        var title: LocalizedStringKey {
            switch self {
            case .app: "App Memory"
            case .wired: "Wired"
            case .compressed: "Compressed"
            case .cached: "Cached Files"
            case .free: "Free"
            case .swap: "Swap Used"
            }
        }

        var color: Color {
            switch self {
            case .app: .blue
            case .wired: .orange
            case .compressed: .purple
            case .cached: .teal
            case .free, .swap: .primary.opacity(0.12)
            }
        }
    }

    let kind: Kind
    let bytes: UInt64
    var id: Kind { kind }
}

private struct LegendItem: View {
    let kind: MemorySegment.Kind
    let bytes: UInt64

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if kind == .swap {
                    // Swap lives on disk, so it gets an outline instead of a slot in the bar.
                    Circle().strokeBorder(.secondary, lineWidth: 1)
                } else {
                    Circle().fill(kind.color)
                }
            }
            .frame(width: 8, height: 8)

            Text(kind.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(MemoryFormat.string(bytes))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PressureBadge: View {
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
        .help("How hard macOS is working to keep memory available")
    }

    private var title: LocalizedStringKey {
        switch pressure {
        case .normal: "Normal Pressure"
        case .warning: "High Pressure"
        case .critical: "Critical Pressure"
        }
    }

    private var color: Color {
        switch pressure {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

private struct HistoryChart: View {
    let history: [UsageSample]
    let total: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(history) { sample in
                AreaMark(
                    x: .value("Time", sample.date),
                    y: .value("Used", MemoryFormat.gigabytes(sample.used))
                )
                .foregroundStyle(.linearGradient(
                    colors: [.blue.opacity(0.35), .blue.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Used", MemoryFormat.gigabytes(sample.used))
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
            .chartXScale(domain: timeWindow)
            .chartYScale(domain: 0...MemoryFormat.gigabytes(total))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, MemoryFormat.gigabytes(total) / 2, MemoryFormat.gigabytes(total)]) { _ in
                    AxisGridLine()
                }
            }
            .frame(height: 44)
            .accessibilityLabel("Memory used over the last 3 minutes")

            Text("Memory used, last 3 minutes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var timeWindow: ClosedRange<Date> {
        let end = history.last?.date ?? .now
        return end.addingTimeInterval(-MemoryMonitor.historyDuration)...end
    }
}
