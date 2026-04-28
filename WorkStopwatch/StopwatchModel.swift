import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let stopwatchStateChanged = Notification.Name("stopwatchStateChanged")
    static let imagePathsChanged = Notification.Name("imagePathsChanged")
}

enum WorkPhase: String, CaseIterable {
    case working
    case shortBreak
    case phoneCall
    case gone
    case idle

    var label: String {
        switch self {
        case .working: return "Working"
        case .shortBreak: return "Short break"
        case .phoneCall: return "Phone call"
        case .gone: return "Gone"
        case .idle: return "Idle"
        }
    }
}

/// Holds a security-scoped bookmark for one phase image and provides
/// safe read access. Used so the sandbox grants persistent file access.
/// If no bookmark is set, falls back to a GIF bundled with the app.
final class BookmarkedImage: ObservableObject {
    let key: String
    let defaultBundleName: String?  // e.g. "working" -> looks up working.gif in bundle
    @Published private(set) var displayPath: String = ""

    private var bookmarkData: Data?

    init(key: String, defaultBundleName: String? = nil) {
        self.key = key
        self.defaultBundleName = defaultBundleName
        self.bookmarkData = UserDefaults.standard.data(forKey: "\(key).bookmark")
        self.displayPath = UserDefaults.standard.string(forKey: "\(key).path") ?? ""
    }

    /// True iff the user has chosen a custom file (vs. using the bundled default).
    var hasCustomFile: Bool { bookmarkData != nil && !displayPath.isEmpty }

    /// Path string to show in UI. Returns "(default)" placeholder if using bundle.
    var uiDisplayPath: String {
        if hasCustomFile { return displayPath }
        if defaultBundleName != nil { return "(using default image)" }
        return ""
    }

    /// Set from a freshly chosen URL (e.g. from NSOpenPanel).
    func setURL(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.bookmarkData = data
            self.displayPath = url.path
            UserDefaults.standard.set(data, forKey: "\(key).bookmark")
            UserDefaults.standard.set(url.path, forKey: "\(key).path")
            NotificationCenter.default.post(name: .imagePathsChanged, object: nil)
        } catch {
            print("=== Failed to create bookmark for \(url.path): \(error) ===")
        }
    }

    /// Clear the user's custom selection. Falls back to bundled default if available.
    func clear() {
        bookmarkData = nil
        displayPath = ""
        UserDefaults.standard.removeObject(forKey: "\(key).bookmark")
        UserDefaults.standard.removeObject(forKey: "\(key).path")
        NotificationCenter.default.post(name: .imagePathsChanged, object: nil)
    }

    /// Resolve bookmark to URL. Returns nil if no bookmark or resolution fails.
    /// Caller must call `stopAccessingSecurityScopedResource()` when done.
    func resolveURL() -> (url: URL, didStartAccessing: Bool)? {
        guard let data = bookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                if let fresh = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    self.bookmarkData = fresh
                    UserDefaults.standard.set(fresh, forKey: "\(key).bookmark")
                }
            }
            let started = url.startAccessingSecurityScopedResource()
            return (url, started)
        } catch {
            print("=== Failed to resolve bookmark for \(key): \(error) ===")
            return nil
        }
    }

    /// Read raw image data. Tries user's bookmarked file first, falls back to bundled default.
    func readData() -> Data? {
        // 1. Try user's custom file via security-scoped bookmark.
        if let resolved = resolveURL() {
            defer {
                if resolved.didStartAccessing {
                    resolved.url.stopAccessingSecurityScopedResource()
                }
            }
            if let data = try? Data(contentsOf: resolved.url) {
                return data
            }
        }
        // 2. Fall back to bundled default image.
        if let name = defaultBundleName,
           let url = Bundle.main.url(forResource: name, withExtension: "gif"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return nil
    }

    /// True if either a user file OR a bundled default is available for display.
    var hasAnyImage: Bool {
        if hasCustomFile { return true }
        if let name = defaultBundleName,
           Bundle.main.url(forResource: name, withExtension: "gif") != nil {
            return true
        }
        return false
    }
}

final class StopwatchModel: ObservableObject {
    static let shared = StopwatchModel()

    static let shortBreakLimit: TimeInterval = 10 * 60
    static let phoneCallLimit: TimeInterval  = 30 * 60

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var phase: WorkPhase = .idle

    // User preference: show the floating character window when running.
    // Default: true (existing behavior).
    @Published var showFloatingWindowOnStart: Bool {
        didSet {
            UserDefaults.standard.set(showFloatingWindowOnStart, forKey: "showFloatingWindow")
        }
    }

    // Bookmarked images for each phase, with bundled defaults.
    let workingImage  = BookmarkedImage(key: "img.working", defaultBundleName: "working")
    let breakImage    = BookmarkedImage(key: "img.break",   defaultBundleName: "shortbreak")
    let phoneImage    = BookmarkedImage(key: "img.phone",   defaultBundleName: "phonecall")
    let goneImage     = BookmarkedImage(key: "img.gone",    defaultBundleName: "gone")
    let idleImage     = BookmarkedImage(key: "img.idle",    defaultBundleName: "idle")

    private var startDate: Date?
    private var stopDate: Date?
    private var ticker: Timer?
    private var pathChangeObserver: NSObjectProtocol?

    private init() {
        // Default to true on first launch.
        if UserDefaults.standard.object(forKey: "showFloatingWindow") == nil {
            UserDefaults.standard.set(true, forKey: "showFloatingWindow")
        }
        self.showFloatingWindowOnStart = UserDefaults.standard.bool(forKey: "showFloatingWindow")

        startTicker()
        // Re-broadcast image changes so views observing the model refresh.
        pathChangeObserver = NotificationCenter.default.addObserver(
            forName: .imagePathsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Controls

    func start() {
        guard !isRunning else { return }
        startDate = Date()
        stopDate = nil
        elapsed = 0
        isRunning = true
        recomputePhase()
        NotificationCenter.default.post(name: .stopwatchStateChanged, object: nil)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopDate = Date()
        recomputePhase()
        NotificationCenter.default.post(name: .stopwatchStateChanged, object: nil)
    }

    func toggle() { isRunning ? stop() : start() }

    func reset() {
        isRunning = false
        elapsed = 0
        startDate = nil
        stopDate = nil
        phase = .idle
        NotificationCenter.default.post(name: .stopwatchStateChanged, object: nil)
    }

    // MARK: - Ticker / phase

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isRunning, let s = self.startDate {
                self.elapsed = Date().timeIntervalSince(s)
            }
            self.recomputePhase()
        }
    }

    private func recomputePhase() {
        let new: WorkPhase
        if isRunning {
            new = .working
        } else if let stop = stopDate {
            let since = Date().timeIntervalSince(stop)
            if since < Self.shortBreakLimit { new = .shortBreak }
            else if since < Self.phoneCallLimit { new = .phoneCall }
            else { new = .gone }
        } else {
            new = .idle
        }
        if new != phase {
            phase = new
            NotificationCenter.default.post(name: .stopwatchStateChanged, object: nil)
        }
    }

    // MARK: - Image lookup

    func bookmark(for phase: WorkPhase) -> BookmarkedImage {
        switch phase {
        case .working:    return workingImage
        case .shortBreak: return breakImage
        case .phoneCall:  return phoneImage
        case .gone:       return goneImage
        case .idle:
            // Idle has no bundled default by design; fall back to gone if user
            // hasn't picked an idle image.
            return idleImage.hasAnyImage ? idleImage : goneImage
        }
    }

    var currentBookmark: BookmarkedImage { bookmark(for: phase) }

    // MARK: - Format

    static func format(_ t: TimeInterval) -> String {
        let total = max(0, Int(t))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
