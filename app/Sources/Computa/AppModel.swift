import AppKit
import ComputaCore
import ComputaUI
import Observation
import os

/// Everything the app's scenes share: the daemon connection, Prevent Sleep and the settings.
@MainActor
@Observable
final class AppModel {
    let store: MonitorStore
    let sleep: SleepPreventionModel
    @ObservationIgnored private let settings = DaemonAddressSetting(defaults: .standard)
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "app")

    init() {
        store = MonitorStore(endpoint: settings.endpoint)
        sleep = SleepPreventionModel(preventer: IOKitSleepPreventer())
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
        logger.info("starting; daemon at \(self.store.endpoint, privacy: .public)")
        store.start()
    }

    var popoverContent: PopoverContent {
        PopoverContent(
            state: store.state, sample: store.sample, host: store.host, endpoint: store.endpoint,
            preventSleepOn: sleep.isOn, preventSleepError: sleep.lastError
        )
    }

    /// Checks, stores and applies a new daemon address.
    func saveAddress(_ text: String) throws(DaemonEndpointError) -> DaemonEndpoint {
        let endpoint = try settings.save(text)
        store.setEndpoint(endpoint)
        return endpoint
    }

    private func applicationWillTerminate() {
        logger.info("quitting; releasing prevent-sleep if held")
        sleep.set(on: false)
        store.stop()
    }
}
