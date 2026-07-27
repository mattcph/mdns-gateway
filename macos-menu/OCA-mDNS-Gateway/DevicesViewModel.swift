import Foundation

final class DevicesViewModel: ObservableObject {
    @Published private(set) var instances: [DeviceInstance] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published var selection = Set<DeviceInstance.ID>()

    private var refreshTask: Task<Void, Never>?
    private var autoRefreshEnabled = false

    var selectedInstance: DeviceInstance? {
        guard let id = selection.first else { return nil }
        return instances.first { $0.id == id }
    }

    var statusLine: String {
        if let errorMessage {
            return errorMessage
        }
        if isLoading && instances.isEmpty {
            return "Loading…"
        }
        let count = instances.count
        let devicesWord = count == 1 ? "device" : "devices"
        if let lastUpdated {
            let time = DateFormatter.localizedString(from: lastUpdated, dateStyle: .none, timeStyle: .medium)
            return "\(count) \(devicesWord) · Updated \(time)"
        }
        return "\(count) \(devicesWord)"
    }

    func appear() {
        autoRefreshEnabled = true
        Task { await refresh() }
        startAutoRefresh()
    }

    func disappear() {
        autoRefreshEnabled = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await GatewayAPIClient.fetchDevices()
            apply(result)
            errorMessage = nil
        } catch {
            if instances.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Refresh failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-fetches live data and writes pretty-printed `/v1/devices` JSON to `url`.
    @MainActor
    func export(to url: URL) async throws {
        let result = try await GatewayAPIClient.fetchDevices()
        apply(result)
        errorMessage = nil
        let pretty = try GatewayAPIClient.prettyPrintedDevicesJSON(from: result.rawData)
        try pretty.write(to: url, options: .atomic)
    }

    static func defaultExportFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "oca-devices-\(formatter.string(from: date)).json"
    }

    @MainActor
    private func apply(_ result: DevicesFetchResult) {
        instances = result.envelope.instances
        lastUpdated = Date()
        selection = selection.filter { id in instances.contains(where: { $0.id == id }) }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, self.autoRefreshEnabled, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }
}
