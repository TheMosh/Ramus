import Foundation

/// Formats byte counts the way Activity Monitor does: binary units, labelled GB and MB.
enum MemoryFormat {
    private static let bytesPerGB = 1_073_741_824.0
    private static let bytesPerMB = 1_048_576.0

    static func gigabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / bytesPerGB
    }

    /// "12.4 GB" or "512 MB", with a fixed number of decimals so live values don't jitter.
    static func string(_ bytes: UInt64) -> String {
        let gigabytes = gigabytes(bytes)
        if gigabytes >= 1 {
            return "\(gigabytes.formatted(.number.precision(.fractionLength(1)))) GB"
        }
        return "\((Double(bytes) / bytesPerMB).formatted(.number.precision(.fractionLength(0)))) MB"
    }

    /// Installed capacity, e.g. "32 GB".
    static func capacity(_ bytes: UInt64) -> String {
        "\(gigabytes(bytes).formatted(.number.precision(.fractionLength(0...1)))) GB"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
