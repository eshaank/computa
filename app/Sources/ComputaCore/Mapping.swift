import Foundation

// Maps the generated gRPC messages to the public domain models. The generated types stay
// `package`, so nothing outside this package depends on them.

extension Date {
    init(unixMilliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(unixMilliseconds) / 1000)
    }
}

extension HostInfo {
    package init(_ message: Computa_V1_Host) {
        self.init(
            hostname: message.hostname,
            model: message.model,
            chip: message.chip,
            osVersion: message.osVersion,
            daemonVersion: message.daemonVersion,
            memoryTotalBytes: message.memoryTotalBytes,
            coreGroups: message.coreGroups.map {
                CoreGroup(kind: CoreKind($0.kind), name: $0.name, coreCount: Int($0.coreCount))
            },
            bootTime: Date(unixMilliseconds: message.bootUnixMs),
            sampleIntervalMilliseconds: message.sampleIntervalMs,
            historyCapacity: message.historyCapacity
        )
    }
}

extension CoreKind {
    package init(_ kind: Computa_V1_CoreKind) {
        switch kind {
        case .performance: self = .performance
        case .efficiency: self = .efficiency
        case .unspecified, .UNRECOGNIZED: self = .unspecified
        }
    }
}

extension SystemSample {
    package init(_ message: Computa_V1_SystemSample) {
        time = Date(unixMilliseconds: message.unixMs)
        cpu = CpuSample(message.cpu)
        memory = MemorySample(message.memory)
        volumes = message.volumes.map(VolumeSample.init)
        diskReadBytesPerSecond = message.diskActivity.readBytesPerSec
        diskWriteBytesPerSecond = message.diskActivity.writeBytesPerSec
        network = NetworkSample(message.network)
        battery = message.hasBattery ? BatterySample(message.battery) : nil
    }
}

extension CpuSample {
    package init(_ message: Computa_V1_Cpu) {
        usagePercent = message.usagePercent
        userPercent = message.userPercent
        systemPercent = message.systemPercent
        cores = message.cores.map {
            CoreSample(index: Int($0.index), kind: CoreKind($0.kind), usagePercent: $0.usagePercent)
        }
        loadAverages = [message.loadAverage1M, message.loadAverage5M, message.loadAverage15M]
    }
}

extension MemoryPressure {
    package init(_ pressure: Computa_V1_MemoryPressure) {
        switch pressure {
        case .normal: self = .normal
        case .warning: self = .warning
        case .critical: self = .critical
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension MemorySample {
    package init(_ message: Computa_V1_Memory) {
        totalBytes = message.totalBytes
        usedBytes = message.usedBytes
        appBytes = message.appBytes
        wiredBytes = message.wiredBytes
        compressedBytes = message.compressedBytes
        cachedBytes = message.cachedBytes
        freeBytes = message.freeBytes
        swapUsedBytes = message.swapUsedBytes
        swapTotalBytes = message.swapTotalBytes
        pressure = MemoryPressure(message.pressure)
    }
}

extension VolumeSample {
    package init(_ message: Computa_V1_Volume) {
        name = message.name
        mountPoint = message.mountPoint
        totalBytes = message.totalBytes
        usedBytes = message.usedBytes
        availableBytes = message.availableBytes
    }
}

extension NetworkSample {
    package init(_ message: Computa_V1_Network) {
        receiveBytesPerSecond = message.rxBytesPerSec
        sendBytesPerSecond = message.txBytesPerSec
        interfaces = message.interfaces.map {
            NetworkInterfaceSample(
                name: $0.name,
                addresses: $0.addresses,
                receiveBytesPerSecond: $0.rxBytesPerSec,
                sendBytesPerSecond: $0.txBytesPerSec,
                receivedBytesTotal: $0.rxBytesTotal,
                sentBytesTotal: $0.txBytesTotal
            )
        }
    }
}

extension BatteryState {
    package init(_ state: Computa_V1_BatteryState) {
        switch state {
        case .charging: self = .charging
        case .discharging: self = .discharging
        case .full: self = .full
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension BatterySample {
    package init(_ message: Computa_V1_Battery) {
        chargePercent = message.chargePercent
        state = BatteryState(message.state)
        onACPower = message.onAcPower
        minutesRemaining = message.hasMinutesRemaining ? Int(message.minutesRemaining) : nil
    }
}

extension HistorySeries {
    package init(_ message: Computa_V1_History) {
        stepMilliseconds = message.stepMs
        points = message.points.map {
            HistoryPoint(
                time: Date(unixMilliseconds: $0.unixMs),
                cpuUsagePercent: $0.cpuUsagePercent,
                cpuUserPercent: $0.cpuUserPercent,
                cpuSystemPercent: $0.cpuSystemPercent,
                memoryUsedBytes: $0.memoryUsedBytes,
                memoryAppBytes: $0.memoryAppBytes,
                memoryWiredBytes: $0.memoryWiredBytes,
                memoryCompressedBytes: $0.memoryCompressedBytes,
                swapUsedBytes: $0.swapUsedBytes,
                networkReceiveBytesPerSecond: $0.netRxBytesPerSec,
                networkSendBytesPerSecond: $0.netTxBytesPerSec,
                diskReadBytesPerSecond: $0.diskReadBytesPerSec,
                diskWriteBytesPerSecond: $0.diskWriteBytesPerSec
            )
        }
    }
}
