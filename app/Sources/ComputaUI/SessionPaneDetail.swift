import ComputaCore
import SwiftUI

/// One pane opened: what it is and where, its figures, the close button, and its processes.
struct PaneDetailView: View {
    let pane: RexPane
    let tab: RexTab
    let session: RexSession
    let metric: ProcessMetric
    let actions: SessionActions
    let requestClose: (PaneCloseRequest) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                PaneFacts(pane: pane, tab: tab, session: session)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pane.processes.count == 1 ? "1 Process" : "\(pane.processes.count) Processes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text.opacity(0.9))
                        .padding(.horizontal, 4)
                    ProcessTable(processes: pane.processes, metric: metric)
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PaneTile(kind: pane.kind, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pane.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if pane.isClaude { ClaudeTag() }
                }
                Text(kindText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dimText)
            }
            Spacer(minLength: 8)
            if actions.isAvailable {
                ClosePaneButton(titled: true, isBusy: actions.isBusy(pane)) {
                    requestClose(PaneCloseRequest(pane: pane, sessionID: session.id, sessionLabel: session.label))
                }
                .fixedSize()
            }
        }
        .padding(14)
        .sessionSurface()
    }

    private var kindText: String {
        switch pane.kind {
        case .claude: "Claude Code"
        case .shell: "Shell"
        case .program: "Program"
        case .unspecified: "Pane"
        }
    }
}

/// The pane's facts as label–value rows, like a Settings group.
struct PaneFacts: View {
    let pane: RexPane
    let tab: RexTab
    let session: RexSession

    var body: some View {
        let memory = pane.memory
        VStack(spacing: 0) {
            row("Folder", pane.workingDirectory.isEmpty ? "Unknown" : WorkingDirectory.abbreviatingHome(pane.workingDirectory))
                .help(pane.workingDirectory)
            Divider()
            row("Session", session.label.isEmpty ? "Session" : session.label)
            if session.tabs.count > 1 {
                Divider()
                row("Tab", tab.label.isEmpty ? "Tab" : tab.label)
            }
            Divider()
            row(SessionMemoryWords.label(memory), SessionFigures.memory(memory)).help(SessionMemoryWords.help)
            if !memory.isFootprintOnly {
                Divider()
                row("Footprint", Format.memory(memory.footprint)).help(SessionMemoryWords.help)
            }
            Divider()
            row("CPU", SessionFigures.cpu(pane.cpuPercent))
            Divider()
            row("Processes", processText)
        }
        .padding(.horizontal, 12)
        .sessionSurface(radius: SessionMetrics.groupRadius)
    }

    /// "4", or "4, 3 readable" when the daemon could not read them all.
    private var processText: String {
        let readable = pane.processes.count
        return readable < pane.processCount ? "\(pane.processCount), \(readable) readable" : "\(pane.processCount)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Theme.dimText)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// The pane's processes in columns: name and pid, Mem, Footprint, CPU.
struct ProcessTable: View {
    /// Already sorted.
    let processes: [ProcessEntry]
    let metric: ProcessMetric

    var body: some View {
        VStack(spacing: 0) {
            heading
            ForEach(processes) { process in
                Divider()
                row(process)
            }
            if processes.isEmpty {
                Divider()
                Text("The daemon could not read this pane's processes.")
                    .font(.callout)
                    .foregroundStyle(Theme.dimText)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 12)
        .sessionSurface(radius: SessionMetrics.groupRadius)
    }

    private var heading: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            headingColumn("Mem").help(SessionMemoryWords.help)
            headingColumn("Footprint").help(SessionMemoryWords.help)
            headingColumn("CPU")
        }
        .font(.caption)
        .foregroundStyle(Theme.dimText)
        .padding(.vertical, 6)
    }

    private func row(_ process: ProcessEntry) -> some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(process.name)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "\(process.pid)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.dimText)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(process.path.isEmpty ? process.name : process.path)
            column(residentText(process), bold: metric == .memory)
            column(Format.memory(process.memoryBytes), bold: false)
            column(SessionFigures.cpu(process.cpuPercent), bold: metric == .cpu)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 7)
    }

    private func headingColumn(_ text: String) -> some View {
        Text(text).frame(width: 66, alignment: .trailing)
    }

    /// An older daemon sends no resident size: a dash, never a wrong "0 B".
    private func residentText(_ process: ProcessEntry) -> String {
        process.residentBytes > 0 || process.memoryBytes == 0 ? Format.memory(process.residentBytes) : "—"
    }

    private func column(_ text: String, bold: Bool) -> some View {
        Text(text)
            .fontWeight(bold ? .medium : .regular)
            .foregroundStyle(bold ? Theme.text : Theme.text.opacity(0.7))
            .lineLimit(1)
            .frame(width: 66, alignment: .trailing)
    }
}
