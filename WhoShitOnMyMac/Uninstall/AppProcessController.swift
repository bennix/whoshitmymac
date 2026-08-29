import AppKit
import Foundation

enum AppQuitOutcome: Equatable, Sendable {
    case notRunning
    case terminated
    case forceTerminated
    case failed
}

enum AppProcessController {
    static func matches(
        bundleIdentifier: String,
        appURL: URL,
        candidateBundleIdentifier: String?,
        candidateBundleURL: URL?
    ) -> Bool {
        guard candidateBundleIdentifier == bundleIdentifier,
              let candidateBundleURL else { return false }
        return PathNormalizer.resolve(candidateBundleURL).path == PathNormalizer.resolve(appURL).path
    }

    static func isRunning(appURL: URL, bundleIdentifier: String) -> Bool {
        !matchingApplications(appURL: appURL, bundleIdentifier: bundleIdentifier).isEmpty
    }

    static func quit(
        appURL: URL,
        bundleIdentifier: String,
        gracefulTimeout: TimeInterval = 2,
        forceTimeout: TimeInterval = 3
    ) -> AppQuitOutcome {
        var applications = matchingApplications(appURL: appURL, bundleIdentifier: bundleIdentifier)
        guard !applications.isEmpty else { return .notRunning }

        for application in applications {
            _ = application.terminate()
        }
        if waitUntilTerminated(applications, timeout: gracefulTimeout) {
            return .terminated
        }

        applications = matchingApplications(appURL: appURL, bundleIdentifier: bundleIdentifier)
        for application in applications {
            _ = application.forceTerminate()
        }
        return waitUntilTerminated(applications, timeout: forceTimeout) ? .forceTerminated : .failed
    }

    private static func matchingApplications(appURL: URL, bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter {
            matches(
                bundleIdentifier: bundleIdentifier,
                appURL: appURL,
                candidateBundleIdentifier: $0.bundleIdentifier,
                candidateBundleURL: $0.bundleURL
            )
        }
    }

    private static func waitUntilTerminated(
        _ applications: [NSRunningApplication],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if applications.allSatisfy(\.isTerminated) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return applications.allSatisfy(\.isTerminated)
    }
}
