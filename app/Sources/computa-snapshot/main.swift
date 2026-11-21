// Renders the app's views offscreen to PNG files in .build/snapshots, using SwiftUI's
// ImageRenderer at 2x. No window and no screen capture are involved.
//
// Usage: computa-snapshot [output directory]

import AppKit
import ComputaCore
import ComputaUI
import SwiftUI

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/snapshots",
    isDirectory: true
)

struct SnapshotError: Error, CustomStringConvertible {
    let description: String
}

/// Puts a view on a dark backdrop, like the desktop behind the real popover.
struct Backdrop<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .padding(20)
            .background(Color(white: 0.11))
    }
}

@MainActor
func render(_ view: some View, named name: String) throws {
    let renderer = ImageRenderer(content: Backdrop(content: view))
    renderer.scale = 2
    guard let image = renderer.cgImage else {
        throw SnapshotError(description: "ImageRenderer produced no image for \(name)")
    }
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw SnapshotError(description: "could not encode \(name) as PNG")
    }
    let file = outputDirectory.appendingPathComponent("\(name).png")
    try data.write(to: file)
    print("\(file.path) \(image.width)x\(image.height)")
}

@MainActor
func popover(
    _ state: ConnectionState, sample: SystemSample? = Fixtures.sample, host: HostInfo? = Fixtures.host,
    sleepOn: Bool = false, sleepError: String? = nil, claude: String? = nil
) -> PopoverView {
    PopoverView(
        content: PopoverContent(
            state: state, sample: sample, host: host, endpoint: .local,
            preventSleepOn: sleepOn, preventSleepError: sleepError, claudeSummary: claude
        ),
        actions: .none
    )
}

@MainActor
func renderAll() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let notRunning = DaemonProblem(
        kind: .unreachable, summary: "computad is not running at 127.0.0.1:7300.", detail: "unavailable"
    )
    let unsupported = DaemonProblem(
        kind: .unsupported, summary: "computad at 127.0.0.1:7300 does not offer this call yet. Update the daemon.",
        detail: "unimplemented"
    )
    try render(popover(.connected), named: "popover-connected-sleep-off")
    try render(popover(.connected, sleepOn: true), named: "popover-connected-sleep-on")
    try render(
        popover(.connected, claude: ClaudeUsage.popoverText(Fixtures.sessions)), named: "popover-claude-row"
    )
    try render(popover(.connected, sample: Fixtures.desktopUnderPressure), named: "popover-desktop-pressure")
    try render(popover(.connecting, sample: nil, host: nil), named: "popover-connecting")
    try render(popover(.daemonNotRunning(notRunning)), named: "popover-daemon-not-running")
    try render(popover(.daemonNotRunning(unsupported), sleepOn: true), named: "popover-daemon-unsupported-sleep-on")
    try render(
        popover(.connected, sleepError: "Could not keep this Mac awake: IOPMAssertionCreateWithName failed (0xe00002c2)"),
        named: "popover-sleep-error"
    )
    try renderExtras()
}

do {
    try MainActor.assumeIsolated { try renderAll() }
} catch {
    FileHandle.standardError.write(Data("computa-snapshot: \(error)\n".utf8))
    exit(1)
}
