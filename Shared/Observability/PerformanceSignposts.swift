import Foundation
import OSLog

/// Lightweight os_signpost instrumentation for release budgets (Track C2).
/// Emits only counts and durations — never post bodies, tokens, or attachments.
enum PerformanceSignposts {
    private static let signposter = OSSignposter(subsystem: "com.dailymind.bloomary.desktop", category: .pointsOfInterest)
    private static let logger = Logger(subsystem: "com.dailymind.bloomary.desktop", category: "Performance")
    private static var didReportAppLaunch = false

    /// Emitted once per process when the root view first appears.
    static func appLaunchComplete() {
        guard !didReportAppLaunch else { return }
        didReportAppLaunch = true
        signposter.emitEvent("AppLaunchComplete")
    }

    /// Draft cache load: signpost interval for duration, log line for the count.
    static func draftCacheLoad(_ body: () -> DraftSnapshot) -> DraftSnapshot {
        let state = signposter.beginInterval("DraftCacheLoad")
        let snapshot = body()
        signposter.endInterval("DraftCacheLoad", state)
        logger.debug("DraftCacheLoad drafts=\(snapshot.drafts.count, privacy: .public)")
        return snapshot
    }

    /// Synchronous interval measurement (e.g. local draft save).
    @discardableResult
    static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        let state = signposter.beginInterval(name)
        let result = body()
        signposter.endInterval(name, state)
        return result
    }

    /// Async interval measurement (e.g. publish attempt duration).
    static func beginAsyncInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func endAsyncInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
}
