import Foundation

/// Turns numbers into the short text the UI shows. Output does not depend on the locale.
public enum Format {
    /// A percentage rounded to the nearest whole percent and kept within 0...100. The rings,
    /// the menu bar label and the probe all use this, so they agree to the percent.
    public static func wholePercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value)).rounded(.toNearestOrAwayFromZero))
    }

    /// For example "42%".
    public static func percent(_ value: Double) -> String {
        "\(wholePercent(value))%"
    }

    /// A process's CPU share with one decimal, not capped at 100, because 100 is one core:
    /// "312.5%". Negative or invalid values show as zero.
    public static func cpuShare(_ value: Double) -> String {
        String(format: "%.1f%%", value.isFinite ? max(0, value) : 0)
    }

    /// Share of a ring to fill, 0...1, matching the whole percent shown beside it.
    public static func ringFraction(_ percentValue: Double) -> Double {
        Double(wholePercent(percentValue)) / 100
    }

    /// Memory sizes in binary units, as Activity Monitor shows them: "14.5 GB".
    public static func memory(_ bytes: UInt64) -> String {
        scaled(Double(bytes), base: 1024)
    }

    /// Storage sizes in decimal units, as Finder shows them: "494 GB".
    public static func storage(_ bytes: UInt64) -> String {
        scaled(Double(bytes), base: 1000)
    }

    /// Used and total memory sharing the total's unit: "21.0 / 36.0 GB", or with
    /// `separator: " of "` "21.0 of 36.0 GB".
    public static func memoryUsage(used: UInt64, total: UInt64, separator: String = " / ") -> String {
        usage(used: Double(used), total: Double(total), base: 1024, separator: separator)
    }

    /// Used and total storage sharing the total's unit: "811 / 995 GB".
    public static func storageUsage(used: UInt64, total: UInt64) -> String {
        usage(used: Double(used), total: Double(total), base: 1000)
    }

    /// Transfer rates in decimal units: "1.2 MB/s". Negative or invalid rates show as zero.
    public static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        return scaled(value, base: 1000) + "/s"
    }

    /// Time since `boot`: "3d 4h", "5h 12m" or "7m".
    public static func uptime(since boot: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(boot) / 60))
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    /// For example "82%, charging" or "100%, on power".
    public static func battery(_ battery: BatterySample) -> String {
        let charge = percent(battery.chargePercent)
        switch battery.state {
        case .charging: return "\(charge), charging"
        case .discharging: return "\(charge), on battery"
        case .full: return "\(charge), full"
        case .unknown: return battery.onACPower ? "\(charge), on power" : charge
        }
    }

    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    private static func usage(used: Double, total: Double, base: Double, separator: String = " / ") -> String {
        let (scaledTotal, unit) = unitFor(total, base: base)
        let divisor = pow(base, Double(unit))
        return "\(number(used / divisor, unit: unit))\(separator)\(number(scaledTotal, unit: unit)) \(units[unit])"
    }

    /// Below 100 one decimal is shown, from 100 none; bytes are always whole. A value that
    /// would print as 1000 or more moves up a unit.
    private static func scaled(_ value: Double, base: Double) -> String {
        let (amount, unit) = unitFor(value, base: base)
        return "\(number(amount, unit: unit)) \(units[unit])"
    }

    private static func unitFor(_ value: Double, base: Double) -> (amount: Double, unit: Int) {
        var amount = value
        var unit = 0
        while amount >= 999.5 && unit < units.count - 1 {
            amount /= base
            unit += 1
        }
        return (amount, unit)
    }

    private static func number(_ amount: Double, unit: Int) -> String {
        if unit == 0 || amount >= 99.95 { return "\(Int(amount.rounded()))" }
        return String(format: "%.1f", amount)
    }
}
