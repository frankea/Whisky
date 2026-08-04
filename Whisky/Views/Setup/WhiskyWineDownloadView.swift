//
//  WhiskyWineDownloadView.swift
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

import AppKit
import SemanticVersion
import SwiftUI
import WhiskyKit

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    // Internal so the formatting helpers in WhiskyWineDownloadFormatting.swift can read it.
    @State var downloadSpeed: Double = 0
    @State private var downloadTask: Task<Void, Never>?
    @State private var startTime: Date?
    /// Bytes already on disk when this UI session's download began (non-zero
    /// when resuming a partial), so speed and ETA only count fresh bytes.
    @State private var sessionBaselineBytes: Int64?
    /// The current failure, if any. Carries the user-facing message and the
    /// telemetry reason together so the two can never drift apart.
    /// Internal so the failure helper in WhiskyWineDownloadFormatting.swift can set it.
    @State var downloadFailure: DownloadFailure?
    /// Expected SHA-256 of the runtime archive, from the version plist. `nil`
    /// when no hash is advertised, in which case verification is skipped.
    @State private var expectedSHA256: String?
    /// Guards the once-per-setup-attempt `runtime_install_started` capture against
    /// repeated `onAppear` calls from NavigationStack (mirrors the install view).
    @State private var hasStartedDownload: Bool = false
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @Binding var diagnostics: WhiskyWineSetupDiagnostics

    /// Stable on-disk home for the runtime archive. Living in Caches rather
    /// than the ephemeral temp directory means a partially downloaded archive
    /// survives an app relaunch, and the next attempt resumes it instead of
    /// starting the full download over.
    static let archiveDestination: URL = .cachesDirectory
        .appending(path: Bundle.whiskyBundleIdentifier)
        .appending(path: "RuntimeDownload")
        .appending(path: "Libraries.tar.gz")

    /// Downloader that resumes interrupted transfers and retries transient
    /// failures with backoff. The session survives transient connectivity loss
    /// (Wi-Fi/Ethernet switches, VPN reconnects) and applies bounded
    /// request/resource timeouts so a stalled download surfaces an error
    /// instead of hanging forever.
    private static let downloader: ResumableDownloader = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        return ResumableDownloader(sessionConfiguration: config)
    }()

    var body: some View {
        VStack {
            VStack {
                Text("setup.whiskywine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.whiskywine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()

                if let failure = downloadFailure {
                    errorView(error: failure.message)
                } else {
                    progressView
                }

                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            // Guard against multiple onAppear calls from NavigationStack so the
            // once-per-setup-attempt runtime_install_started capture holds.
            guard !hasStartedDownload else { return }
            hasStartedDownload = true
            Task {
                diagnostics.reset()
                diagnostics.record("Entered download stage")
                diagnostics.record("Telemetry consent: \(Telemetry.consent.rawValue)")
                Telemetry.capture(.runtimeInstallStarted)
                await fetchVersionAndDownload()
            }
        }
    }
}

extension WhiskyWineDownloadView {
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .resizable()
                .foregroundStyle(.red)
                .frame(width: 80, height: 80)
                .padding(.bottom, 8)
            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button("setup.whiskywine.copyDiagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        diagnostics.reportString(stage: "download", error: error),
                        forType: .string
                    )
                }
                .buttonStyle(.bordered)

                Button("open.logs") {
                    WhiskyApp.openLogsFolder()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Button("setup.retry") {
                    retryDownload()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("setup.quit") {
                    showSetup = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var progressView: some View {
        VStack {
            ProgressView(value: fractionProgress, total: 1)
            HStack {
                HStack {
                    Text(String(
                        format: String(localized: "setup.whiskywine.progress"),
                        formatBytes(bytes: completedBytes),
                        formatBytes(bytes: totalBytes)
                    ))
                        + Text(String(" "))
                        + (shouldShowEstimate()
                            ? Text(String(
                                format: String(localized: "setup.whiskywine.eta"),
                                formatRemainingTime(
                                    remainingBytes: totalBytes - completedBytes
                                )
                            ))
                            : Text(String()))
                    Spacer()
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    /// Resets the UI and starts over. Partial download data stays on disk, so
    /// the new attempt resumes from wherever the failed one stopped.
    private func retryDownload() {
        downloadFailure = nil
        fractionProgress = 0
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        startTime = nil
        sessionBaselineBytes = nil
        downloadTask?.cancel()
        downloadTask = nil
        diagnostics.resetDownloadState(reason: "Retry requested")
        Task {
            await fetchVersionAndDownload()
        }
    }

    private func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    private func proceed() {
        path.append(.whiskyWineInstall)
    }

    @MainActor
    private func fetchVersionAndDownload() async {
        guard let versionURL = URL(string: DistributionConfig.versionPlistURL) else {
            setDownloadFailure(String(localized: "setup.whiskywine.error.invalidVersionURL"))
            return
        }

        diagnostics.versionPlistURL = versionURL.absoluteString
        diagnostics.record("Fetching version plist")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: versionURL)

            // Check HTTP status code before attempting to decode
            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode) {
                diagnostics.versionHTTPStatus = httpResponse.statusCode
                diagnostics.record("Version plist HTTP \(httpResponse.statusCode)")
                setDownloadFailure(formatHTTPError(statusCode: httpResponse.statusCode))
                return
            }

            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
            expectedSHA256 = versionInfo.sha256

            let version = versionInfo.version
            let versionString = "\(version.major).\(version.minor).\(version.patch)"
            let downloadURLString = DistributionConfig.librariesURL(version: versionString)
            diagnostics.record("Resolved version \(versionString)")

            guard let downloadURL = URL(string: downloadURLString) else {
                setDownloadFailure(String(localized: "setup.whiskywine.error.invalidDownloadURL"))
                return
            }

            diagnostics.downloadURL = downloadURL.absoluteString
            if await reuseExistingArchiveIfValid() {
                return
            }
            startDownload(from: downloadURL)
        } catch {
            let errorMessage = error.localizedDescription
            diagnostics.record("Version fetch failed: \(errorMessage)")
            setDownloadFailure(String(
                format: String(localized: "setup.whiskywine.error.fetchVersionFailed"),
                errorMessage
            ))
        }
    }

    /// A finished archive can be left behind when the app quits between the
    /// download and install stages. If it matches the advertised hash, skip
    /// straight to install; if not, discard it so the download starts clean.
    /// - Returns: `true` when the setup flow already moved on to install.
    @MainActor
    private func reuseExistingArchiveIfValid() async -> Bool {
        let destination = Self.archiveDestination
        guard let expected = expectedSHA256,
              FileManager.default.fileExists(atPath: destination.path(percentEncoded: false))
        else { return false }
        diagnostics.record("Found previously downloaded archive; verifying")
        let result = await Task.detached {
            WhiskyWineInstaller.integrityResult(forFileAt: destination, expectedSHA256: expected)
        }.value
        guard result == .match else {
            diagnostics.record("Previous archive failed verification; discarding")
            ResumableDownloader.discardArtifacts(at: destination)
            return false
        }
        diagnostics.record("Previous archive verified; skipping download")
        tarLocation = destination
        proceed()
        return true
    }

    @MainActor
    private func startDownload(from url: URL) {
        diagnostics.downloadStartedAt = Date()
        diagnostics.record("Starting download")
        startTime = Date()
        sessionBaselineBytes = nil
        let destination = Self.archiveDestination
        downloadTask = Task { @MainActor in
            do {
                try await Self.downloader.download(
                    from: url,
                    to: destination,
                    onEvent: { message in
                        Task { @MainActor in diagnostics.record(message) }
                    },
                    progress: { progress in
                        Task { @MainActor in handleProgressUpdate(progress) }
                    }
                )
                diagnostics.downloadFinishedAt = Date()
                diagnostics.record("Download completed")
                await verifyThenProceed(fileURL: destination)
            } catch is CancellationError {
                // Cancelled by retry or quit; partial data stays for resume.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Same as above, surfaced through URLSession.
            } catch {
                handleDownloadError(error)
            }
        }
    }

    @MainActor
    private func handleDownloadError(_ error: Error) {
        diagnostics.downloadFinishedAt = Date()
        if case let ResumableDownloadError.httpStatus(statusCode) = error {
            diagnostics.downloadHTTPStatus = statusCode
            diagnostics.record("Download HTTP \(statusCode)")
            setDownloadFailure(formatHTTPError(statusCode: statusCode))
            return
        }
        diagnostics.record("Download failed: \(error.localizedDescription)")
        setDownloadFailure(String(
            format: String(localized: "setup.whiskywine.error.downloadFailed"),
            error.localizedDescription
        ))
    }

    /// Verifies the downloaded archive against the advertised SHA-256, then
    /// continues to the install stage. Fails closed on a mismatch (deletes the
    /// archive, surfaces an error) rather than installing unverified bytes. When
    /// no hash is advertised, verification is skipped so older runtime metadata
    /// still installs.
    @MainActor
    private func verifyThenProceed(fileURL: URL) async {
        if let expected = expectedSHA256 {
            diagnostics.record("Verifying runtime archive (SHA-256)")
            // Hashed off the main actor — the archive is hundreds of megabytes.
            let result = await Task.detached {
                WhiskyWineInstaller.integrityResult(forFileAt: fileURL, expectedSHA256: expected)
            }.value
            let failure: String? = switch result {
            case .match: nil
            case let .mismatch(actual): "expected \(expected), got \(actual)"
            case .unreadable: "expected \(expected), archive unreadable"
            }
            if let failure {
                diagnostics.record("Integrity check FAILED — \(failure)")
                // Discard the archive plus any resume artifacts so the next
                // attempt restarts from a clean slate, never from bad bytes.
                ResumableDownloader.discardArtifacts(at: fileURL)
                setDownloadFailure(
                    String(
                        localized: "setup.whiskywine.error.checksumMismatch",
                        defaultValue: """
                        The downloaded Wine runtime failed its integrity check and was not installed. \
                        This usually means the download was corrupted. Please try again.
                        """
                    ),
                    reason: .verifyFailed
                )
                return
            }
            diagnostics.record("Integrity check passed")
        }

        tarLocation = fileURL
        proceed()
    }

    @MainActor
    private func handleProgressUpdate(_ progress: ResumableDownloadProgress) {
        if sessionBaselineBytes == nil {
            // First report of this session. When resuming, it already includes
            // the carried-over prefix; baseline it so speed and ETA reflect
            // only bytes actually transferred now.
            sessionBaselineBytes = progress.bytesOnDisk
            startTime = Date()
        }
        completedBytes = progress.bytesOnDisk
        totalBytes = progress.expectedBytes ?? 0
        let currentTime = Date()
        let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
        let sessionBytes = completedBytes - (sessionBaselineBytes ?? 0)
        if sessionBytes > 0, elapsedTime > 0 {
            downloadSpeed = Double(sessionBytes) / elapsedTime
        }
        if totalBytes > 0 {
            fractionProgress = Double(completedBytes) / Double(totalBytes)
        }
        diagnostics.recordProgress(bytesReceived: completedBytes, bytesExpected: totalBytes)
    }
}
