// swiftlint:disable file_length
//
//  DependencyInstallSheet.swift
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
import WhiskyKit

/// Guided dependency install sheet with 5 stages: Info, Preflight, Plan, Running, Verify.
///
/// Walks the user through what will be installed, checks prefix health,
/// shows the verb list, streams live log output during installation, and
/// re-verifies the dependency status after completion. Installation never
/// happens silently -- the user must explicitly click Install.
struct DependencyInstallSheet: View {
    let definition: DependencyDefinition
    @ObservedObject var bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var stage: InstallStage = .info
    @State private var logLines: [String] = []
    @State private var isInstalling: Bool = false
    @State private var installResult: InstallResult?
    @State private var showLog: Bool = false
    @State private var preflightResult: PreflightResult?
    @State private var verifyStatus: DependencyInstallStatus?

    var body: some View {
        VStack(spacing: 0) {
            stageContent
            Divider()
            bottomBar
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Install Stage

extension DependencyInstallSheet {
    enum InstallStage {
        case info
        case preflight
        case running
        case verify
    }

    enum InstallResult {
        case success
        case failure(exitCode: Int32)
        case error(String)
    }

    struct PreflightResult {
        let prefixValid: Bool
        let prefixMessage: String
    }
}

// MARK: - Stage Router

extension DependencyInstallSheet {
    @ViewBuilder
    private var stageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch stage {
                case .info:
                    infoStage
                case .preflight:
                    preflightStage
                case .running:
                    runningStage
                case .verify:
                    verifyStage
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Info Stage

extension DependencyInstallSheet {
    @ViewBuilder
    private var infoStage: some View {
        Label("What you\u{2019}re installing", systemImage: "info.circle.fill")
            .font(.title2)
            .fontWeight(.semibold)

        Text(definition.displayName)
            .font(.title3)

        Text(definition.description)
            .foregroundStyle(.secondary)

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "This will install: \(definition.winetricksVerbs.joined(separator: ", "))",
                    systemImage: "shippingbox"
                )
                .font(.callout)

                Label(
                    "Estimated time: \(definition.estimatedInstallMinutes) minutes",
                    systemImage: "clock"
                )
                .font(.callout)
            }
            .padding(4)
        }

        GroupBox {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Installed components cannot be automatically removed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }
}

// MARK: - Preflight Stage

extension DependencyInstallSheet {
    @ViewBuilder
    private var preflightStage: some View {
        Label("Preflight Checks", systemImage: "checklist")
            .font(.title2)
            .fontWeight(.semibold)

        if let result = preflightResult {
            preflightResultView(result)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking prefix health\u{2026}")
                    .foregroundStyle(.secondary)
            }
        }

        verbPlanSection
    }

    @ViewBuilder
    private func preflightResultView(_ result: PreflightResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.prefixValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.prefixValid ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Prefix Health")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(result.prefixMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !result.prefixValid {
            GroupBox {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Prefix validation failed. Installation may not succeed. You can proceed anyway.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private var verbPlanSection: some View {
        GroupBox("Verbs to install") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(definition.winetricksVerbs, id: \.self) { verb in
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(verb)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Running Stage

extension DependencyInstallSheet {
    @ViewBuilder
    private var runningStage: some View {
        Label("Installing\u{2026}", systemImage: "arrow.down.circle")
            .font(.title2)
            .fontWeight(.semibold)

        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Running winetricks for \(definition.displayName)")
                .foregroundStyle(.secondary)
        }

        DisclosureGroup(isExpanded: $showLog) {
            logView
        } label: {
            Text("Installation Log (\(logLines.count) lines)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 200)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: logLines.count) {
                if let last = logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Verify Stage

extension DependencyInstallSheet {
    @ViewBuilder
    private var verifyStage: some View {
        Label("Verification", systemImage: "checkmark.seal")
            .font(.title2)
            .fontWeight(.semibold)

        if let result = installResult {
            installResultView(result)
        }

        if let status = verifyStatus {
            verifyStatusView(status)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Re-checking dependency status\u{2026}")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func installResultView(_ result: InstallResult) -> some View {
        switch result {
        case .success:
            Label("Installation completed successfully", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failure(exitCode):
            Label(
                "Installation exited with code \(exitCode)",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        case let .error(message):
            Label("Installation failed: \(message)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func verifyStatusView(_ status: DependencyInstallStatus) -> some View {
        GroupBox {
            HStack(spacing: 8) {
                switch status {
                case .installed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All components verified as installed")
                case .partiallyInstalled:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Some components may not have installed correctly")
                case .notInstalled:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Installation may have failed -- components not detected")
                case .unknown:
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.gray)
                    Text("Could not verify installation status")
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Bottom Bar

extension DependencyInstallSheet {
    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if stage != .verify {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Spacer()

            switch stage {
            case .info:
                Button("Continue") {
                    stage = .preflight
                    runPreflightChecks()
                }
                .keyboardShortcut(.defaultAction)
            case .preflight:
                Button("Install") {
                    startInstallation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preflightResult == nil)
            case .running:
                EmptyView()
            case .verify:
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

// MARK: - Actions

extension DependencyInstallSheet {
    private func runPreflightChecks() {
        Task {
            let result = await MainActor.run {
                WinePrefixValidation.validatePrefix(for: bottle)
            }
            let preflight = PreflightResult(
                prefixValid: result.isValid,
                prefixMessage: result.isValid
                    ? "Prefix is healthy and ready for installation"
                    : result.diagnostics?.events.last ?? "Prefix validation failed"
            )
            await MainActor.run {
                preflightResult = preflight
            }
        }
    }

    private func startInstallation() {
        stage = .running
        isInstalling = true
        logLines = []

        Task {
            let verbStream = Winetricks.installVerbs(definition.winetricksVerbs, for: bottle)
            var lastExitCode: Int32 = 0
            var hadError = false

            for await (verb, progress) in verbStream {
                await MainActor.run {
                    switch progress {
                    case .preparing:
                        logLines.append("[\(verb)] Preparing\u{2026}")
                    case let .output(line):
                        logLines.append("[\(verb)] \(line)")
                    case let .completed(exitCode):
                        logLines.append("[\(verb)] Completed (exit code: \(exitCode))")
                        lastExitCode = exitCode
                    case let .failed(message):
                        logLines.append("[\(verb)] FAILED: \(message)")
                        hadError = true
                    }
                }
            }

            let result: InstallResult
            if hadError {
                result = .error("One or more verbs failed")
            } else if lastExitCode == 0 {
                result = .success
            } else {
                result = .failure(exitCode: lastExitCode)
            }

            await MainActor.run {
                installResult = result
                isInstalling = false
                stage = .verify
            }

            await runVerification()
            await saveInstallAttempt(result)
        }
    }

    private func runVerification() async {
        let statuses = await DependencyManager.checkDependencies(
            for: bottle,
            definitions: [definition]
        )
        await MainActor.run {
            verifyStatus = statuses.first?.status ?? .unknown
        }
    }

    private func saveInstallAttempt(_ result: InstallResult) async {
        let bottleURL = await MainActor.run { bottle.url }
        var history = BottleDependencyHistory.load(from: bottleURL) ?? BottleDependencyHistory()

        let success: Bool
        let exitCode: Int32?
        switch result {
        case .success:
            success = true
            exitCode = 0
        case let .failure(code):
            success = false
            exitCode = code
        case .error:
            success = false
            exitCode = nil
        }

        let attempt = DependencyInstallAttempt(
            definitionId: definition.id,
            verbsAttempted: definition.winetricksVerbs,
            timestamp: Date(),
            success: success,
            exitCode: exitCode
        )
        history.append(attempt)
        try? history.save(to: bottleURL)
    }
}

// swiftlint:enable file_length
