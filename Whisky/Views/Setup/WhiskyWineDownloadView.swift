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

import SwiftUI
import WhiskyKit
import SemanticVersion
import os

private let logger = Logger(subsystem: Bundle.whiskyBundleIdentifier, category: "WhiskyWineDownloadView")

private func formatHTTPError(statusCode: Int) -> String {
    let statusMessage: String
    switch statusCode {
    case 404:
        statusMessage = String(localized: "setup.whiskywine.error.fileNotFound")
    case 403:
        statusMessage = String(localized: "setup.whiskywine.error.accessDenied")
    case 429:
        statusMessage = String(localized: "setup.whiskywine.error.rateLimit")
    case 500...599:
        statusMessage = String(localized: "setup.whiskywine.error.serverError")
    default:
        statusMessage = String(
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
            Task {
                await fetchVersionAndDownload()
            }
        }
    }

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
                    Text(String(format: String(localized: "setup.whiskywine.progress"),
                                formatBytes(bytes: completedBytes),
                                formatBytes(bytes: totalBytes)))
                    + Text(String(" "))
                    + (shouldShowEstimate() ?
                       Text(String(format: String(localized: "setup.whiskywine.eta"),
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
        Task {
            await fetchVersionAndDownload()
        }
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    func proceed() {
        path.append(.whiskyWineInstall)
    }

    @MainActor
    func fetchVersionAndDownload() async {
        guard let versionURL = URL(string: DistributionConfig.versionPlistURL) else {
            downloadError = String(localized: "setup.whiskywine.error.invalidVersionURL")
            return
        }

        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(from: versionURL)

            // Check HTTP status code before attempting to decode
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                downloadError = formatHTTPError(statusCode: httpResponse.statusCode)
                return
            }

            let versionInfo = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)

            let version = versionInfo.version
            let versionString = "\(version.major).\(version.minor).\(version.patch)"
            let downloadURLString = DistributionConfig.librariesURL(version: versionString)

            guard let downloadURL = URL(string: downloadURLString) else {
                downloadError = String(localized: "setup.whiskywine.error.invalidDownloadURL")
                return
            }

            await startDownload(from: downloadURL)
        } catch {
            let errorMessage = error.localizedDescription
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

        if let error = error {
            // Don't show error when download was explicitly cancelled (e.g., during retry)
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            downloadError = String(
                format: String(localized: "setup.whiskywine.error.downloadFailed"),
                error.localizedDescription
            )
            return
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            downloadError = formatHTTPError(statusCode: httpResponse.statusCode)
            return
        }

        if let url = fileURL {
            tarLocation = url
            proceed()
        } else {
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
    }

    private func formatHTTPError(statusCode: Int) -> String {
        let statusMessage: String
        switch statusCode {
        case 404:
            statusMessage = String(localized: "setup.whiskywine.error.fileNotFound")
        case 403:
            statusMessage = String(localized: "setup.whiskywine.error.accessDenied")
        case 429:
            statusMessage = String(localized: "setup.whiskywine.error.rateLimit")
        case 500...599:
            statusMessage = String(localized: "setup.whiskywine.error.serverError")
        default:
            statusMessage = String(
                format: String(localized: "setup.whiskywine.error.httpError"),
                statusCode
            )
        }
        return String(
            format: String(localized: "setup.whiskywine.error.downloadFailed"),
            statusMessage
        )
    }
}
