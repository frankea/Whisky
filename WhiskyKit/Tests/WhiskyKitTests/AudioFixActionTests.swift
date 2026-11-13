//
//  AudioFixActionTests.swift
//  WhiskyKitTests
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

@testable import WhiskyKit
import XCTest

final class AudioFixActionTests: XCTestCase {
    // MARK: - Findings

    func testFindingsWithAFixMapToIt() {
        let expected: [String: AudioFixAction] = [
            "audio-disabled": .enableAudioDriver,
            "low-buffer-size": .useDefaultLatency,
            "tone-not-audible": .restoreAudio,
            "wine-audio-test-error": .restoreAudio,
            "no-default-device": .openSoundSettings,
            "no-output-channels": .openSoundSettings
        ]
        for (findingId, action) in expected {
            XCTAssertEqual(AudioFixAction(findingId: findingId), action, findingId)
        }
    }

    func testAdviceOnlyFindingsHaveNoFix() {
        // Whisky can't swap the user's headphones or the device's sample rate,
        // so these findings show their advice without a Fix button.
        XCTAssertNil(AudioFixAction(findingId: "bluetooth-device"))
        XCTAssertNil(AudioFixAction(findingId: "low-sample-rate"))
        XCTAssertNil(AudioFixAction(findingId: "not-a-finding"))
    }

    // MARK: - Wizard Steps

    func testEveryWizardStepMapsToAFix() {
        let expected: [String: AudioFixAction] = [
            "check-audio-driver": .enableAudioDriver,
            "set-coreaudio-driver": .useCoreAudioDriver,
            "set-stable-latency": .useStableLatency,
            "check-dsound": .useDefaultLatency,
            "reset-audio-state": .resetAudioState,
            "check-system-settings": .openSoundSettings
        ]
        for (stepId, action) in expected {
            XCTAssertEqual(AudioFixAction(troubleshootingActionId: stepId), action, stepId)
        }
        XCTAssertNil(AudioFixAction(troubleshootingActionId: "not-a-step"))
    }

    @MainActor
    func testEveryOfferedWizardStepMapsToAFix() {
        // Each symptom's fix ladder must resolve to a real fix, or the wizard's
        // Apply Fix button would only record the attempt.
        for symptom in AudioSymptom.allCases {
            let engine = AudioTroubleshootingEngine(probes: [])
            engine.selectedSymptom = symptom
            var offered: [String] = []
            // Walks the ladder: each applied step is skipped next time, and the
            // engine escalates once the ladder or the attempt limit runs out.
            engine.offerNextFix()
            while case let .offeringFix(_, actionId) = engine.wizardState {
                offered.append(actionId)
                engine.applyFix(actionId: actionId)
                engine.offerNextFix()
            }
            XCTAssertFalse(offered.isEmpty, "\(symptom)")
            for actionId in offered {
                XCTAssertNotNil(AudioFixAction(troubleshootingActionId: actionId), "\(symptom): \(actionId)")
            }
        }
    }

    // MARK: - Properties

    func testOnlyResetsClosePrograms() {
        let closing = AudioFixAction.allCases.filter(\.closesRunningPrograms)
        XCTAssertEqual(Set(closing), [.resetAudioState, .restoreAudio])
    }

    func testOnlyOpenSoundSettingsLeavesTheBottleAlone() {
        let external = AudioFixAction.allCases.filter { !$0.changesBottle }
        XCTAssertEqual(external, [.openSoundSettings])
        XCTAssertEqual(AudioFixAction.soundSettingsURL?.scheme, "x-apple.systempreferences")
    }

    // MARK: - Settings Changes

    func testEnableAudioDriverTurnsADisabledDriverBackOn() {
        var settings = BottleSettings()
        settings.audioDriver = .disabled
        AudioFixAction.enableAudioDriver.updateSettings(&settings)
        XCTAssertEqual(settings.audioDriver, .auto)
    }

    func testEnableAudioDriverKeepsAnEnabledDriver() {
        var settings = BottleSettings()
        settings.audioDriver = .coreaudio
        AudioFixAction.enableAudioDriver.updateSettings(&settings)
        XCTAssertEqual(settings.audioDriver, .coreaudio)
    }

    func testRestoreAudioTurnsADisabledDriverBackOn() {
        var settings = BottleSettings()
        settings.audioDriver = .disabled
        AudioFixAction.restoreAudio.updateSettings(&settings)
        XCTAssertEqual(settings.audioDriver, .auto)
    }

    func testUseCoreAudioDriverSetsCoreAudio() {
        var settings = BottleSettings()
        AudioFixAction.useCoreAudioDriver.updateSettings(&settings)
        XCTAssertEqual(settings.audioDriver, .coreaudio)
    }

    func testLatencyFixesSetTheirPresets() {
        var settings = BottleSettings()
        settings.audioLatencyPreset = .lowLatency
        AudioFixAction.useDefaultLatency.updateSettings(&settings)
        XCTAssertEqual(settings.audioLatencyPreset, .defaultPreset)

        AudioFixAction.useStableLatency.updateSettings(&settings)
        XCTAssertEqual(settings.audioLatencyPreset, .stable)
    }

    func testResetAndSoundSettingsLeaveSettingsUnchanged() {
        var settings = BottleSettings()
        settings.audioDriver = .disabled
        settings.audioLatencyPreset = .lowLatency
        for action in [AudioFixAction.resetAudioState, .openSoundSettings] {
            var copy = settings
            action.updateSettings(&copy)
            XCTAssertEqual(copy.audioDriver, .disabled, "\(action)")
            XCTAssertEqual(copy.audioLatencyPreset, .lowLatency, "\(action)")
        }
    }
}
