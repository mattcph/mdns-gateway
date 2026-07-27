import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DevicesView: View {
    @ObservedObject var viewModel: DevicesViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            detailPane
                .frame(minHeight: 120, idealHeight: 160, maxHeight: 220)
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear { viewModel.appear() }
        .onDisappear { viewModel.disappear() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(viewModel.statusLine)
                .font(.callout)
                .foregroundStyle(viewModel.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .lineLimit(2)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh") {
                Task { await viewModel.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("Export…") {
                exportDevices()
            }
            .disabled(viewModel.isLoading && viewModel.instances.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.instances.isEmpty {
            emptyState
        } else {
            Table(viewModel.instances, selection: $viewModel.selection) {
                TableColumn("Name") { (device: DeviceInstance) in
                    Text(device.name)
                }
                .width(min: 120, ideal: 180)
                TableColumn("Host") { (device: DeviceInstance) in
                    Text(device.host)
                }
                .width(min: 100, ideal: 140)
                TableColumn("Address(es)") { (device: DeviceInstance) in
                    Text(device.addressesDisplay)
                }
                .width(min: 100, ideal: 140)
                TableColumn("Port") { (device: DeviceInstance) in
                    Text("\(device.port)")
                }
                .width(min: 50, ideal: 60)
                TableColumn("Interface") { (device: DeviceInstance) in
                    Text(device.interface)
                }
                .width(min: 70, ideal: 90)
                TableColumn("Stale") { (device: DeviceInstance) in
                    Text(device.staleDisplay)
                }
                .width(min: 50, ideal: 60)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView("Loading devices…")
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("No OCA devices found on the network.")
                    .foregroundStyle(.secondary)
                Text("Devices appear when `_oca._tcp` services are announced via mDNS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let device = viewModel.selectedInstance {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("ID", device.id)
                    detailRow("Service", device.service)
                    detailRow("Domain", device.domain)
                    detailRow("State", device.state)
                    detailRow("TTL (s)", "\(device.ttlSeconds)")
                    detailRow("First seen", device.firstSeen)
                    detailRow("Last seen", device.lastSeen)
                    Text("TXT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if device.txt.isEmpty {
                        Text("(none)")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        ForEach(device.txtDisplayLines, id: \.key) { pair in
                            Text("\(pair.key) = \(pair.value)")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } else {
            Text(viewModel.instances.isEmpty ? "" : "Select a device to see TXT records and timestamps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func exportDevices() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = DevicesViewModel.defaultExportFileName()
        panel.title = "Export OCA Devices"
        panel.message = "Saves the same JSON as GET /v1/devices."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                try await viewModel.export(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
