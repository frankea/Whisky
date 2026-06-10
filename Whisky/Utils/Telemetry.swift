//
//  Telemetry.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import PostHog

/// Whisky's entire telemetry surface: five anonymous, opt-in-only events
/// covering the first-run funnel. SECURITY.md documents every event and
/// property — keep that list in sync with ``Event``.
///
/// Nothing is sent unless the user has explicitly opted in, and the SDK is
/// configured with every automatic capture feature disabled, so the events
/// declared here are the only data that can ever leave the app. `identify()`
/// is never called: events carry only a random anonymous ID.
enum Telemetry {
    /// Coarse failure classification. Never send raw error text — underlying
    /// messages contain file paths, which are personal data.
    enum InstallFailureReason: String {
        case tarballMissing = "tarball_missing"
        case extractFailed = "extract_failed"
        case verifyFailed = "verify_failed"
        case downloadFailed = "download_failed"
    }

    enum Event {
        case runtimeInstallStarted
        case runtimeInstallSucceeded
        case runtimeInstallFailed(reason: InstallFailureReason)
        case firstBottleCreated
        case firstProgramLaunched

        var name: String {
            switch self {
            case .runtimeInstallStarted: "runtime_install_started"
            case .runtimeInstallSucceeded: "runtime_install_succeeded"
            case .runtimeInstallFailed: "runtime_install_failed"
            case .firstBottleCreated: "first_bottle_created"
            case .firstProgramLaunched: "first_program_launched"
            }
        }

        var properties: [String: Any] {
            switch self {
            case let .runtimeInstallFailed(reason): ["reason": reason.rawValue]
            default: [:]
            }
        }

        /// "First ever" funnel steps are only reported once per install.
        var oncePerInstall: Bool {
            switch self {
            case .firstBottleCreated, .firstProgramLaunched: true
            default: false
            }
        }
    }

    enum ConsentState: String {
        case undecided
        case granted
        case denied
    }

    /// Shared with the `@AppStorage` bindings in WelcomeView and SettingsView.
    static let consentDefaultsKey = "telemetryConsent"

    static var consent: ConsentState {
        UserDefaults.standard.string(forKey: consentDefaultsKey)
            .flatMap(ConsentState.init(rawValue:)) ?? .undecided
    }

    /// The PostHog project token (public by design — it can only ingest
    /// events, not read them). An empty value disables telemetry entirely.
    private static var projectToken: String {
        Bundle.main.object(forInfoDictionaryKey: "PostHogProjectToken") as? String ?? ""
    }

    @MainActor private static var started = false

    /// Records the user's choice and starts or stops the SDK accordingly.
    /// Declining clears the queued events and the anonymous ID.
    @MainActor
    static func setConsent(granted: Bool) {
        let state: ConsentState = granted ? .granted : .denied
        UserDefaults.standard.set(state.rawValue, forKey: consentDefaultsKey)
        if granted {
            if started {
                PostHogSDK.shared.optIn()
            } else {
                start()
            }
        } else if started {
            PostHogSDK.shared.optOut()
            PostHogSDK.shared.reset()
        }
    }

    /// Call once at app launch; does nothing unless consent was granted.
    @MainActor
    static func startIfConsented() {
        if consent == .granted {
            start()
        }
    }

    @MainActor
    static func capture(_ event: Event) {
        guard consent == .granted else { return }
        start()
        guard started else { return }
        if event.oncePerInstall {
            let onceKey = "telemetryOnce_\(event.name)"
            guard !UserDefaults.standard.bool(forKey: onceKey) else { return }
            UserDefaults.standard.set(true, forKey: onceKey)
        }
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    /// Sets up the SDK with every automatic capture feature disabled: the
    /// explicit `capture(_:)` calls in this file are the only event source.
    @MainActor
    private static func start() {
        guard !started, !projectToken.isEmpty else { return }
        let config = PostHogConfig(projectToken: projectToken, host: "https://us.i.posthog.com")
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        // Surveys and session replay are unavailable on macOS; personProfiles
        // stays .identifiedOnly and identify() is never called, so all events
        // remain anonymous.
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.optIn()
        started = true
    }
}
