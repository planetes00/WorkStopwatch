import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Popover

struct StopwatchView: View {
    @EnvironmentObject var stopwatch: StopwatchModel

    var body: some View {
        VStack(spacing: 12) {
            Text(StopwatchModel.format(stopwatch.elapsed))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .padding(.top, 8)

            Text(stopwatch.phase.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(stopwatch.isRunning ? "Stop" : "Start") {
                    stopwatch.toggle()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.space, modifiers: [])

                Button("Reset") { stopwatch.reset() }
                    .disabled(stopwatch.isRunning)
            }

            Divider()

            GIFPreview(bookmark: stopwatch.currentBookmark)
                .frame(height: 180)
                .cornerRadius(8)
        }
        .padding(16)
        .frame(width: 360)
    }
}

// MARK: - Floating window

struct FloatingView: View {
    @EnvironmentObject var stopwatch: StopwatchModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(stopwatch.phase.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(StopwatchModel.format(stopwatch.elapsed))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
            }

            GIFPreview(bookmark: stopwatch.currentBookmark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(10)

            Button(stopwatch.isRunning ? "Stop" : "Start") {
                stopwatch.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(minWidth: 280, minHeight: 300)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var stopwatch: StopwatchModel
    @State private var showSaved: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Set images for each phase")
                        .font(.headline)
                    Spacer()
                    if showSaved {
                        Text("Saved ✓")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // Behavior toggle
                Toggle(isOn: $stopwatch.showFloatingWindowOnStart) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show floating character window when running")
                            .font(.subheadline)
                        Text("Turn off to keep only the menu bar timer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)

                BookmarkRow(
                    title: "1. Working",
                    subtitle: "While stopwatch is running",
                    bookmark: stopwatch.workingImage,
                    onSaved: flashSaved
                )
                BookmarkRow(
                    title: "2. Short break",
                    subtitle: "0–10 minutes after stop",
                    bookmark: stopwatch.breakImage,
                    onSaved: flashSaved
                )
                BookmarkRow(
                    title: "3. Phone call",
                    subtitle: "10–30 minutes after stop",
                    bookmark: stopwatch.phoneImage,
                    onSaved: flashSaved
                )
                BookmarkRow(
                    title: "4. Gone",
                    subtitle: "More than 30 minutes after stop",
                    bookmark: stopwatch.goneImage,
                    onSaved: flashSaved
                )
                BookmarkRow(
                    title: "5. Idle (optional)",
                    subtitle: "Initial state before any run. Falls back to Gone if empty.",
                    bookmark: stopwatch.idleImage,
                    onSaved: flashSaved
                )

                Text("Files are stored as security-scoped bookmarks; access persists across app restarts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func flashSaved() {
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { showSaved = false }
        }
    }
}

struct BookmarkRow: View {
    let title: String
    let subtitle: String
    @ObservedObject var bookmark: BookmarkedImage
    var onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)

            HStack {
                Text(pathLabel)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(bookmark.hasCustomFile ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)

                Button("Browse...") {
                    if let url = pickFile() {
                        bookmark.setURL(url)
                        onSaved()
                    }
                }
                if bookmark.hasCustomFile {
                    Button("Reset") {
                        bookmark.clear()
                        onSaved()
                    }
                }
            }

            if bookmark.hasAnyImage {
                GIFPreview(bookmark: bookmark)
                    .frame(height: 100)
                    .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }

    private var pathLabel: String {
        if bookmark.hasCustomFile { return bookmark.displayPath }
        if bookmark.defaultBundleName != nil { return "(default)" }
        return "(no file selected)"
    }

    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.gif, UTType.image]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - GIF rendering

/// NSImageView that ignores its image's intrinsic size, so SwiftUI's frame
/// (not the GIF's pixel dimensions) controls layout. Without this, large GIFs
/// blow out the window size.
final class ScalingImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct GIFPreview: NSViewRepresentable {
    @ObservedObject var bookmark: BookmarkedImage

    func makeNSView(context: Context) -> ScalingImageView {
        let v = ScalingImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        v.canDrawSubviewsIntoLayer = true
        v.wantsLayer = true
        // Make the view willing to shrink/grow within whatever frame SwiftUI gives it.
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateNSView(_ view: ScalingImageView, context: Context) {
        guard bookmark.hasAnyImage else {
            view.image = nil
            return
        }
        if let data = bookmark.readData(), let img = NSImage(data: data) {
            view.image = img
            view.animates = true
        } else {
            view.image = nil
            print("=== GIFPreview: failed to load for \(bookmark.key), path=\(bookmark.displayPath) ===")
        }
    }
}
