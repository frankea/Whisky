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
import os
import SemanticVersion
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WhiskyWineDownloadView")

private func formatHTTPError(statusCode: Int) -> String {
    let statusMessage = switch statusCode {
    case 404:
        String(localized: "setup.whiskywine.error.fileNotFound")
    case 403:
        String(localized: "setup.whiskywine.error.accessDenied")
    case 429:
        String(localized: "setup.whiskywine.error.rateLimit")
    case 500 ... 599:
        String(localized: "setup.whiskywine.error.serverError")
    default:
        String(
            format: String(localized: "setup.whiskywine.error.httpError"),
            statusCode
        )
    }
    return String(
        format: String(localized: "setup.whiskywine.error.downloadFailed"),
        statusMessage
    )
}

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var downloadError: String?
    @State private var currentDownloadTaskID: UUID?
    @Binding var tarLocation: URL
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    @Binding var diagnostics: WhiskyWineSetupDiagnostics

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

                if let error = downloadError {
                    errorView(error: error)
                } else {
                    progressView
                }

                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task { @MainActor in
                diagnostics.reset()
                diagnostics.record("Entered download stage")
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
                            ? Text(String(format: String(localized: "setup.whiskywine.eta"),
                                          formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                            : Text(String()))
                    Spacer()
                }
                .font(.subheadline)
                .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    private func retryDownload() {
        downloadError = nil
        fractionProgress = 0
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        startTime = nil
        downloadTask?.cancel()
        observation?.invalidate()
        observation = nil
        downloadTask = nil
        currentDownloadTaskID = nil
        diagnostics.resetDownloadState(reason: "Retry requested")
        Task {
            await fetchVersionAndDownload()
        }
    }

    private func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    private func formatRemainingTime(remainingBytes: Int64) -> String {
        // Avoid dividing by zero or non-positive speeds which lead to invalid estimates.
        guard downloadSpeed > 0 else {
            return ""
        }
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: remainingTimeInSeconds) ?? ""
    }

    private func proceed() {
        path.append(.whiskyWineInstall)
    }

    @MainActor
    private func fetchVersionAndDownload() async {
        guard let versionURL = URL(string: DistributionConfig.versionPlistURL) else {
            downloadError = String(localized: "setup.whiskywine.error.invalidVersionURL")
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
                downloadError = formatHTTPError(statusCode: httpResponse.statusCode)
                return
            }

            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

            let version = versionInfo.version
            let versionString = "\(version.major).\(version.minor).\(version.patch)"
            let downloadURLString = DistributionConfig.librariesURL(version: versionString)
            diagnostics.record("Resolved version \(versionString)")

            guard let downloadURL = URL(string: downloadURLString) else {
                downloadError = String(localized: "setup.whiskywine.error.invalidDownloadURL")
                return
            }

            diagnostics.downloadURL = downloadURL.absoluteString
            startDownload(from: downloadURL)
        } catch {
            let errorMessage = error.localizedDescription
            diagnostics.record("Version fetch failed: \(errorMessage)")
            downloadError = String(
                format: String(localized: "setup.whiskywine.error.fetchVersionFailed"),
                errorMessage
            )
        }
    }

    @MainActor
    private func startDownload(from url: URL) {
        let taskID = UUID()
        currentDownloadTaskID = taskID

        diagnostics.downloadStartedAt = Date()
        diagnostics.record("Starting download")
        downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: url) { fileURL, response, error in
            // URLSession deletes the temporary file immediately after completion handler returns.
            // We must move it to a safe location synchronously before the async Task executes.
            var permanentURL: URL?
            var moveError: Error?
            if let tempURL = fileURL {
                let destinationURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("tar.gz")
                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    permanentURL = destinationURL
                } catch {
                    // Log and capture move error to provide better error messaging
                    let errorDesc = error.localizedDescription
                    logger.error("Failed to move file: \(errorDesc)")
                    moveError = error
                    permanentURL = nil
                }
            }

            // Prioritize network error, then move error
            let effectiveError = error ?? moveError
            Task { @MainActor in
                handleDownloadCompletion(
                    taskID: taskID,
                    fileURL: permanentURL,
                    response: response,
                    error: effectiveError
                )
            }
        }

        observation = downloadTask?.observe(\.countOfBytesReceived) { [taskID] task, _ in
            Task { @MainActor in
                handleProgressUpdate(taskID: taskID, task: task)
            }
        }

        startTime = Date()
        downloadTask?.resume()
    }

    @MainActor
    private func handleDownloadCompletion(
        taskID: UUID,
        fileURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        guard currentDownloadTaskID == taskID else { return }

        if let error {
            // Don't show error when download was explicitly cancelled (e.g., during retry)
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            downloadError = String(
                format: String(localized: "setup.whiskywine.error.downloadFailed"),
                error.localizedDescription
            )
            diagnostics.downloadFinishedAt = Date()
            diagnostics.record("Download failed: \(error.localizedDescription)")
            return
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            diagnostics.downloadHTTPStatus = httpResponse.statusCode
            diagnostics.downloadFinishedAt = Date()
            diagnostics.record("Download HTTP \(httpResponse.statusCode)")
            downloadError = formatHTTPError(statusCode: httpResponse.statusCode)
            return
        }

        if let url = fileURL {
            tarLocation = url
            diagnostics.downloadFinishedAt = Date()
            diagnostics.record("Download completed: moved to temp")
            proceed()
        } else {
            diagnostics.downloadFinishedAt = Date()
            diagnostics.record("Download completed but no file URL received")
            downloadError = String(localized: "setup.whiskywine.error.noFileReceived")
        }
    }

    @MainActor
    private func handleProgressUpdate(taskID: UUID, task: URLSessionDownloadTask) {
        guard currentDownloadTaskID == taskID else { return }

        let currentTime = Date()
        let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
        let currentBytes = task.countOfBytesReceived
        if currentBytes > 0 {
            downloadSpeed = Double(currentBytes) / elapsedTime
        }
        totalBytes = task.countOfBytesExpectedToReceive
        completedBytes = currentBytes
        if totalBytes > 0 {
            fractionProgress = Double(completedBytes) / Double(totalBytes)
        }
        diagnostics.recordProgress(bytesReceived: completedBytes, bytesExpected: totalBytes)
    }
}
