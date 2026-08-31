import XCTest
@testable import Prism

final class AppLaunchBehaviorTests: XCTestCase {
    func testUnitTestHostDoesNotBootstrapApplicationServices() {
        XCTAssertFalse(AppLaunchBehavior.shouldBootstrap(
            arguments: ["Prism"],
            environment: ["XCTestConfigurationFilePath": "/tmp/Prism.xctestconfiguration"]
        ))
    }

    func testUITestLaunchStillBootstrapsApplicationServices() {
        XCTAssertTrue(AppLaunchBehavior.shouldBootstrap(
            arguments: ["Prism", "--ui-testing"],
            environment: ["XCTestConfigurationFilePath": "/tmp/Prism.xctestconfiguration"]
        ))
    }

    func testNormalLaunchBootstrapsApplicationServices() {
        XCTAssertTrue(AppLaunchBehavior.shouldBootstrap(
            arguments: ["Prism"],
            environment: [:]
        ))
    }

    func testFirstNormalLaunchShowsDashboardOnlyOnce() {
        let suiteName = "com.mraz.prism.tests.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppLaunchBehavior.shouldShowDashboard(
            arguments: ["Prism"],
            defaults: defaults
        ))

        AppLaunchBehavior.markFirstLaunchCompleted(defaults: defaults)

        XCTAssertFalse(AppLaunchBehavior.shouldShowDashboard(
            arguments: ["Prism"],
            defaults: defaults
        ))
    }

    func testUITestAlwaysShowsDashboard() {
        let suiteName = "com.mraz.prism.tests.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppLaunchBehavior.markFirstLaunchCompleted(defaults: defaults)

        XCTAssertTrue(AppLaunchBehavior.shouldShowDashboard(
            arguments: ["Prism", "--ui-testing"],
            defaults: defaults
        ))
    }
}
