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
    @State private var storedRecord: GPTKStoreRecord?
    @State private var runtimeCapable = false
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
            Text(runtimeCapable ? "settings.gptk.capability.ok" : "settings.gptk.capability.blocked")
                .font(.caption)
                .foregroundStyle(.secondary)
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
    }

    private func refresh() {
        storedRecord = GPTKImporter.storedRecord()
        runtimeCapable = GPTKImporter.isRuntimeGPTKCapable()
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
        do {
            // Unconditional: isDeployed() reads files written late in deploy, so
            // a half-finished deploy looks undeployed while forwarders are
            // already swapped, and skipping cleanup would delete originals/ with
            // the store. The removal is idempotent per file.
            try GPTKImporter.removeDeployedPayload()
            try GPTKImporter.removeStore()
            storeFailure = nil
        } catch {
            importError = error.localizedDescription
        }
        refresh()
    }
}
