import Darwin
import Foundation

/// A point-in-time breakdown of physical memory, using the same categories as Activity Monitor.
struct SystemMemory: Sendable, Equatable {
    var total: UInt64
    var appMemory: UInt64
    var wired: UInt64
    var compressed: UInt64
    var cachedFiles: UInt64
    var swapUsed: UInt64
    var pressure: MemoryPressure

    /// "Memory Used" in Activity Monitor.
    var used: UInt64 { appMemory + wired + compressed }
    /// Memory apps can claim right now: free pages plus file cache the system can drop.
    var available: UInt64 { total.subtractingClamped(used) }
    var free: UInt64 { available.subtractingClamped(cachedFiles) }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical
}

/// Identifies a running app so its helper processes can be attributed back to it.
struct AppIdentity: Sendable {
    var pid: pid_t
    var bundlePath: String?
}

/// Physical memory used by one app, including its helpers and XPC services.
struct AppFootprint: Sendable {
    var pid: pid_t
    var bytes: UInt64 = 0
    var processCount = 0

    mutating func add(_ processBytes: UInt64) {
        bytes += processBytes
        processCount += 1
    }
}

enum MemorySampler {
    private static let host = mach_host_self()

    static func systemMemory() -> SystemMemory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        let page = UInt64(pageSize)
        let purgeable = UInt64(stats.purgeable_count)

        return SystemMemory(
            total: ProcessInfo.processInfo.physicalMemory,
            appMemory: UInt64(stats.internal_page_count).subtractingClamped(purgeable) * page,
            wired: UInt64(stats.wire_count) * page,
            compressed: UInt64(stats.compressor_page_count) * page,
            cachedFiles: (UInt64(stats.external_page_count) + purgeable) * page,
            swapUsed: swapUsed(),
            pressure: pressure()
        )
    }

    /// Sums the physical footprint (Activity Monitor's "Memory" column) of every process each app owns.
    static func appFootprints(for apps: [AppIdentity]) -> [AppFootprint] {
        let attribution = Attribution(apps: apps)
        var footprints: [pid_t: AppFootprint] = [:]
        for pid in allPIDs() {
            // Fails for processes owned by other users (root daemons), which never belong to an app.
            guard let bytes = physicalFootprint(of: pid), let owner = attribution.owner(of: pid) else { continue }
            footprints[owner, default: AppFootprint(pid: owner)].add(bytes)
        }
        return Array(footprints.values)
    }

    // MARK: - Attribution

    /// Decides which app a process belongs to: the app itself, the app macOS holds responsible for it,
    /// an app among its ancestors, or the app whose bundle contains its executable.
    private struct Attribution {
        private let ownerByAppPID: [pid_t: pid_t]
        private let ownerByResponsiblePID: [pid_t: pid_t]
        private let bundles: [(prefix: String, owner: pid_t)]

        init(apps: [AppIdentity]) {
            // Extensions and helper apps shipped inside another app's bundle belong to that app.
            let prefixes = apps.compactMap { app in app.bundlePath.map { (prefix: $0 + "/", pid: app.pid) } }
            let outerApps = apps.filter { app in
                guard let path = app.bundlePath else { return true }
                return !prefixes.contains { $0.pid != app.pid && path.hasPrefix($0.prefix) }
            }

            // Some helpers register as apps themselves (e.g. "Google Drive Web Content"). Apps that share
            // a responsible process collapse into one owner: that process if it is an app, otherwise the
            // member that is a real .app bundle.
            var ownerByAppPID: [pid_t: pid_t] = [:]
            var ownerByResponsiblePID: [pid_t: pid_t] = [:]
            let groups = Dictionary(grouping: outerApps) { MemorySampler.responsiblePID(of: $0.pid) ?? $0.pid }
            for (responsible, members) in groups {
                let owner = members.first { $0.pid == responsible }
                    ?? members.first { $0.bundlePath?.hasSuffix(".app") == true }
                    ?? members[0]
                ownerByResponsiblePID[responsible] = owner.pid
                for member in members { ownerByAppPID[member.pid] = owner.pid }
            }

            self.ownerByAppPID = ownerByAppPID
            self.ownerByResponsiblePID = ownerByResponsiblePID
            self.bundles = outerApps.compactMap { app in
                guard let path = app.bundlePath, let owner = ownerByAppPID[app.pid] else { return nil }
                return (prefix: path + "/", owner: owner)
            }
        }

        func owner(of pid: pid_t) -> pid_t? {
            if let owner = ownerByAppPID[pid] { return owner }
            if let responsible = MemorySampler.responsiblePID(of: pid),
               let owner = ownerByResponsiblePID[responsible] ?? ownerByAppPID[responsible] {
                return owner
            }

            var ancestor = pid
            for _ in 0..<16 {
                guard let parent = MemorySampler.parentPID(of: ancestor), parent > 1 else { break }
                if let owner = ownerByAppPID[parent] { return owner }
                ancestor = parent
            }

            guard let path = MemorySampler.executablePath(of: pid) else { return nil }
            return bundles.first { path.hasPrefix($0.prefix) }?.owner
        }
    }

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// The process macOS holds responsible for another, e.g. the app that launched an XPC service.
    /// The symbol is private to libsystem, so it is resolved at runtime and skipped if missing.
    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    fileprivate static func responsiblePID(of pid: pid_t) -> pid_t? {
        guard let responsibleFor = responsiblePIDFunction else { return nil }
        let responsible = responsibleFor(pid)
        return responsible > 0 ? responsible : nil
    }

    // MARK: - libproc

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private static func physicalFootprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    fileprivate static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbsi_ppid)
    }

    fileprivate static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    // MARK: - sysctl

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}

extension UInt64 {
    func subtractingClamped(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}
