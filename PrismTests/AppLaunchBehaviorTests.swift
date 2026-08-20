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
}
