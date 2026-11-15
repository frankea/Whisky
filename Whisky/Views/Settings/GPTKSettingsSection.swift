//
//  GPTKSettingsSection.swift
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

import SwiftUI
import UniformTypeIdentifiers
import WhiskyKit

/// Settings for Apple's Game Porting Toolkit payload: import from the
/// user-supplied disk image, show what is stored, and deploy it only when the
/// installed engine build can actually execute it.
struct GPTKSettingsSection: View {
    @Environment(\.openURL) private var openURL
    @State private var storedRecord: GPTKStoreRecord?
    @State private var runtimeCapable = false
    @State private var readiness: D3DMetalReadiness = .available
    /// Set after an import the installed engine can't run, which otherwise
    /// looks like it finished the job (#358).
    @State private var showEngineNeeded = false
    @State private var importing = false
    @State private var showImporter = false
    @State private var importError: String?
    /// Why the stored payload failed the checks it was given before its first
    /// deploy, which keeps it out of the runtime until it is imported again.
    @State private var storeFailure: String?

    var body: some View {
        Section {
            if let storedRecord {
                LabeledContent("settings.gptk.version", value: storedRecord.gptkVersion)
                if let storeFailure {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("settings.gptk.unverified", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(storeFailure)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("settings.gptk.status.none")
                    .foregroundStyle(.secondary)
            }

            if readiness.needsCapableEngine {
                engineNeededNote
            }

            HStack {
                Button("settings.gptk.import") {
                    showImporter = true
                }
                .disabled(importing)

                if importing {
                    ProgressView()
                        .controlSize(.small)
                }

                if storedRecord != nil {
                    Button("settings.gptk.remove", role: .destructive) {
                        removePayload()
                    }
                    .disabled(importing)
                }
            }
        } header: {
            Text("settings.gptk")
        } footer: {
            // An engine that can't run D3DMetal is explained in the section
            // itself, with where to get one.
            if runtimeCapable {
                Text("settings.gptk.capability.ok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Checked whether or not the engine can run the payload, so a store
            // that fails is reported before anything would deploy it.
            storeFailure = await Task.detached(priority: .utility) {
                let verdict = GPTKImporter.verifyStoredPayload()
                GPTKImporter.deployStoredPayloadIfCapable()
                guard case let .failed(reason) = verdict else { return nil }
                return reason
            }.value
            refresh()
            BottleVM.shared.migrateLauncherBackends()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.diskImage, .folder]
        ) { result in
            guard case let .success(url) = result else { return }
            importPayload(from: url)
        }
        .alert(
            "settings.gptk.import.failed",
            isPresented: .init(
                get: { importError != nil },
                set: { isPresented in
                    if !isPresented {
                        importError = nil
                    }
                }
            )
        ) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("settings.gptk.imported.engineNeeded.title", isPresented: $showEngineNeeded) {
            if let url = D3DMetalReadiness.engineReleasesURL {
                Button("gptk.engineReleases") {
                    openURL(url)
                }
            }
            Button("button.ok", role: .cancel) {}
        } message: {
            Text("settings.gptk.imported.engineNeeded.message")
        }
    }

    /// Says the engine, not the payload, is what D3DMetal is waiting on, and
    /// links to the GPTK-capable engine builds. A stored payload that failed
    /// its checks never deploys, so it gets the wording about a payload
    /// imported again rather than the promise that this one will deploy.
    private var engineNeededNote: some View {
        let message: LocalizedStringKey = readiness == .engineNotCapable && storeFailure == nil
            ? "settings.gptk.engine.needed"
            : "settings.gptk.engine.alsoNeeded"
        return VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "info.circle")
                .font(.callout)
            if let url = D3DMetalReadiness.engineReleasesURL {
                Link("gptk.engineReleases", destination: url)
                    .font(.callout)
            }
        }
    }

    private func refresh() {
        storedRecord = GPTKImporter.storedRecord()
        runtimeCapable = GPTKImporter.isRuntimeGPTKCapable()
        readiness = D3DMetalReadiness.current()
    }

    private func importPayload(from url: URL) {
        importing = true
        Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var mounts: [URL] = []
            do {
                let resolved = try GPTKDiskImage.resolvePayload(at: url)
                mounts = resolved.mounts
                let payload = try GPTKImporter.validatePayload(at: resolved.libRoot)
                try GPTKImporter.importPayload(payload)
                // Deployment into the Wine tree is gated: on an engine build
                // without GPTK exception-unwind support the payload would
                // crash every process that touches it.
                if GPTKImporter.isRuntimeGPTKCapable() {
                    try GPTKImporter.deployStoredPayload()
                }
                for mount in mounts.reversed() {
                    GPTKDiskImage.detach(mount)
                }
                await MainActor.run {
                    importing = false
                    storeFailure = nil
                    refresh()
                    showEngineNeeded = readiness.needsCapableEngine
                    // D3DMetal may be installed now: bottles Steam's profile
                    // had to switch to DXVK can go back to Recommended.
                    BottleVM.shared.migrateLauncherBackends()
                }
            } catch {
                for mount in mounts.reversed() {
                    GPTKDiskImage.detach(mount)
                }
                await MainActor.run {
                    importing = false
                    importError = error.localizedDescription
                    refresh()
                }
            }
        }
    }

    private func removePayload() {
        // Off the main thread: removal waits for any deploy the launch-time
        // update is running, and that can take a few seconds.
        Task.detached(priority: .userInitiated) {
            let failure: String?
            do {
                // Unconditional: isDeployed() reads files written late in deploy, so
                // a half-finished deploy looks undeployed while forwarders are
                // already swapped, and skipping cleanup would delete originals/ with
                // the store. The removal is idempotent per file.
                try GPTKImporter.removeDeployedPayload()
                try GPTKImporter.removeStore()
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                if let failure {
                    importError = failure
                } else {
                    storeFailure = nil
                }
                refresh()
            }
        }
    }
}
