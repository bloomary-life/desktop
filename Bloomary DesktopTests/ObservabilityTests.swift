import Sentry
import Testing
@testable import Bloomary_Desktop

struct ObservabilityTests {
    // Verifies: MAC-001
    @Test
    func testRunsNeverStartCrashReporting() {
        #expect(CrashReporter.isRunningTests)
        #expect(!SentrySDK.isEnabled)
    }
}
