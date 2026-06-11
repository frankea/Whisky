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
import os.log
import PostHog
import WhiskyKit

private extension Logger {
    static let telemetry = Logger(
        subsystem: Bundle.whiskyBundleIdentifier,
        category: "Telemetry"
    )
}

/// Whisky's entire telemetry event surface: five anonymous, opt-in-only events
/// covering the first-run funnel. Every event Whisky can send, and all SDK
/// configuration, is declared in this file; the app only calls ``capture(_:)``
/// with these declared events. Keep the event list in sync with the README
/// table, SECURITY.md, and the `setup.telemetry.consent.help` string.
///
/// Nothing is sent unless the user has explicitly opted in. Every automatic
/// capture feature of the SDK is disabled, and `personProfiles` is `.never`, so
/// no person profile is ever created and `identify()` is never called — events
/// are anonymous. Note the SDK still attaches its standard context to each event
/// (app/macOS version, hardware model, locale, and more); SECURITY.md enumerates
/// the full list. PostHog's ingestion sees the connecting IP like any HTTPS
/// request; GeoIP enrichment is disabled via `$geoip_disable`. None of this is
/// tied to the user's identity.
enum Telemetry {
    /// Coarse failure classification. Never send raw error text — underlying
    /// messages contain file paths, which are personal data.
    enum InstallFailureReason: String {
        case tarballMissing = "tarball_missing"
        case extractFailed = "extract_failed"
        case verifyFailed = "verify_failed"
        case downloadFailed = "download_failed"
        /// Extraction reported success but the runtime is not actually usable
        /// afterwards (e.g. the `wine64` binary is missing).
        case runtimeIncomplete = "runtime_incomplete"
    }

    enum Event {
        case runtimeInstallStarted
        case runtimeInstallSucceeded
        case runtimeInstallFailed(reason: InstallFailureReason)
        case firstBottleCreated
        case firstProgramLaunchAttempted

        var name: String {
            switch self {
            case .runtimeInstallStarted: "runtime_install_started"
            case .runtimeInstallSucceeded: "runtime_install_succeeded"
            case .runtimeInstallFailed: "runtime_install_failed"
            case .firstBottleCreated: "first_bottle_created"
            // Captured when a launch is initiated, before its outcome is known —
            // the name says "attempted" so the data isn't read as success.
            case .firstProgramLaunchAttempted: "first_program_launch_attempted"
            }
        }

        /// Exhaustive (no `default:`) on purpose: a new event case must declare
        /// its properties and once-policy before this builds. The compiler can't
        /// enforce doc re-sync, so re-sync the README, SECURITY.md, and the
        /// `setup.telemetry.consent.help` string at the same time.
        var properties: [String: Any] {
            switch self {
            case let .runtimeInstallFailed(reason): ["reason": reason.rawValue]
            case .runtimeInstallStarted, .runtimeInstallSucceeded,
                 .firstBottleCreated, .firstProgramLaunchAttempted: [:]
            }
        }

        /// "First ever" funnel steps are only reported once per install.
        var oncePerInstall: Bool {
            switch self {
            case .firstBottleCreated, .firstProgramLaunchAttempted: true
            case .runtimeInstallStarted, .runtimeInstallSucceeded, .runtimeInstallFailed: false
            }
        }
    }

    enum ConsentState: String {
        case undecided
        case granted
        case denied
    }

    /// The UserDefaults key backing consent. Read it via `@AppStorage` if you
    /// like, but **never write it directly** — route writes through
    /// ``setConsent(granted:)`` so the SDK opt-in/opt-out state stays in sync.
    /// Note the SDK state is best-effort only (`reset()` clears the SDK's
    /// persisted opt-out flag); what actually enforces a denial is the
    /// app-level consent check in ``capture(_:)``, so that guard must stay.
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
    /// Declining stops all future capture and resets the anonymous ID; any
    /// events already queued at that moment may still be delivered (posthog-ios
    /// 3.59.x exposes no public queue-purge), but no new ones are captured.
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
    ///
    /// The SDK-behavior claims below (no public queue-purge, surveys/session
    /// replay being macOS-unavailable) were verified against posthog-ios 3.59.3;
    /// re-check them on a package bump.
    @MainActor
    private static func start() {
        guard !started else { return }
        guard !projectToken.isEmpty else {
            if consent == .granted {
                Logger.telemetry.warning("Telemetry consented but disabled: no PostHogProjectToken in Info.plist")
            }
            return
        }
        let host = "https://us.i.posthog.com"
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        #if DEBUG
        config.debug = true
        #endif
        // Explicit, not relying on SDK defaults: never build a person profile, so
        // events stay anonymous even though we never call identify(). (Surveys and
        // session replay are macOS-unavailable in posthog-ios 3.59.x and cannot be
        // enabled.)
        config.personProfiles = .never
        // Disable server-side GeoIP enrichment on every event.
        config.setBeforeSend { event in
            event.properties["$geoip_disable"] = true
            return event
        }
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.optIn()
        started = true
        // Success-path log so "telemetry is live" is observable, not just failure.
        // Only a short token prefix is logged, never the full token.
        Logger.telemetry.info(
            "Telemetry started (host \(host, privacy: .public), token \(projectToken.prefix(8), privacy: .public)…)"
        )
    }
}
