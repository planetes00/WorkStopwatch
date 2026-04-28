import AppIntents
import Foundation

struct StartStopwatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Stopwatch"
    static var description = IntentDescription("Start the work stopwatch.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        StopwatchModel.shared.start()
        return .result()
    }
}

struct StopStopwatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Stopwatch"
    static var description = IntentDescription("Stop the work stopwatch.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> {
        let elapsed = StopwatchModel.shared.elapsed
        StopwatchModel.shared.stop()
        return .result(value: elapsed)
    }
}

struct ToggleStopwatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Stopwatch"
    static var description = IntentDescription("Start the stopwatch if stopped, stop it if running.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        StopwatchModel.shared.toggle()
        return .result(value: StopwatchModel.shared.isRunning)
    }
}

struct WorkStopwatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleStopwatchIntent(),
            phrases: ["Toggle \(.applicationName)", "Start or stop \(.applicationName)"],
            shortTitle: "Toggle",
            systemImageName: "stopwatch"
        )
        AppShortcut(
            intent: StartStopwatchIntent(),
            phrases: ["Start \(.applicationName)"],
            shortTitle: "Start",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopStopwatchIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
    }
}
