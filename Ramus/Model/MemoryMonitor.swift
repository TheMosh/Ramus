import AppKit
import Observation

struct AppMemoryUsage: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let bytes: UInt64
    let processCount: Int

    /// Chart key; pids keep two apps with the same name apart.
    var key: String { String(id) }
}

struct UsageSample: Identifiable {
    let date: Date
    let used: UInt64
    var id: Date { date }
}

/// The text the menu bar can show, kept separately so the status item only redraws when it changes.
struct MenuBarSummary: Equatable {
    var available: String
    var usedPercentage: String
}

@MainActor
@Observable
final class MemoryMonitor {
    static let historyDuration: TimeInterval = 180

    private(set) var menuBarSummary: MenuBarSummary?

    // The panel's views can stay alive while it is closed, so these are only published while it is open.
    private(set) var system: SystemMemory?
    private(set) var apps: [AppMemoryUsage] = []
    private(set) var history: [UsageSample] = []

    /// Walking every process is the expensive part, so per-app sampling only runs while the panel is open.
    @ObservationIgnored var isPanelVisible = false {
        didSet {
            guard isPanelVisible && !oldValue else { return }
            publishPanelData()
            Task { await refresh() }
        }
    }

    @ObservationIgnored private var latestSystem: SystemMemory?
    @ObservationIgnored private var recentSamples: [UsageSample] = []
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsAnotherRefresh = false

    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                // Each redraw of the menu bar item has a cost, so update it at Activity Monitor's
                // pace in the background and faster while the panel is being watched.
                try? await Task.sleep(for: self.isPanelVisible ? .seconds(2) : .seconds(5))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        repeat {
            needsAnotherRefresh = false
            await sample()
        } while needsAnotherRefresh
        isRefreshing = false
    }

    private func sample() async {
        let runningApps = isPanelVisible ? trackedApps() : nil
        let identities = runningApps?.map { AppIdentity(pid: $0.processIdentifier, bundlePath: $0.bundleURL?.path) }

        let (system, footprints) = await Task.detached(priority: .utility) {
            (MemorySampler.systemMemory(), identities.map(MemorySampler.appFootprints(for:)))
        }.value

        if let system {
            latestSystem = system
            let now = Date.now
            recentSamples.append(UsageSample(date: now, used: system.used))
            recentSamples.removeAll { now.timeIntervalSince($0.date) > Self.historyDuration }

            let summary = MenuBarSummary(
                available: MemoryFormat.string(system.available),
                usedPercentage: MemoryFormat.percent(system.usedFraction)
            )
            if summary != menuBarSummary { menuBarSummary = summary }
        }

        if isPanelVisible { publishPanelData() }

        if let runningApps, let footprints {
            let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
            apps = footprints
                .compactMap { footprint in
                    guard let app = appsByPID[footprint.pid] else { return nil }
                    return AppMemoryUsage(
                        id: footprint.pid,
                        name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                        icon: app.icon ?? NSImage(named: NSImage.applicationIconName)!,
                        bytes: footprint.bytes,
                        processCount: footprint.processCount
                    )
                }
                .sorted { $0.bytes > $1.bytes }
        }
    }

    private func publishPanelData() {
        system = latestSystem
        history = recentSamples
    }

    private func trackedApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { !$0.isTerminated && $0.activationPolicy != .prohibited }
    }
}
