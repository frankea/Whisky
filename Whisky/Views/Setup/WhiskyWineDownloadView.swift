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

struct WhiskyWineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var downloadError: String?
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
                    // Error state
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
                                downloadError = nil
                                fractionProgress = 0
                                completedBytes = 0
                                totalBytes = 0
                                downloadTask?.cancel()
                                observation?.invalidate()
                                observation = nil
                                downloadTask = nil
                                Task {
                                    await fetchVersionAndDownload()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            
                            Button("setup.quit") {
                                // Dismiss the setup entirely
                                showSetup = false
                            }
                            .buttonStyle(.bordered)
                            .keyboardShortcut(.cancelAction)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                } else {
                    // Download progress state
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
                
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                // First, fetch the version information
                await fetchVersionAndDownload()
            }
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
    
    func fetchVersionAndDownload() async {
        // Fetch version from GitHub Pages
        guard let versionURL = URL(string: DistributionConfig.versionPlistURL) else {
            downloadError = String(localized: "setup.whiskywine.error.invalidVersionURL")
            return
        }
        
        do {
            let (data, _) = try await URLSession(configuration: .ephemeral).data(from: versionURL)
            let decoder = PropertyListDecoder()
            let versionInfo = try decoder.decode(WhiskyWineVersion.self, from: data)
            
            // Construct download URL from version
            let versionString = "\(versionInfo.version.major).\(versionInfo.version.minor).\(versionInfo.version.patch)"
            let downloadURLString = DistributionConfig.librariesURL(version: versionString)
            
            guard let downloadURL = URL(string: downloadURLString) else {
                downloadError = String(localized: "setup.whiskywine.error.invalidDownloadURL")
                return
            }
            
            // Start download
            await MainActor.run {
                downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: downloadURL) { url, response, error in
                    Task { @MainActor in
                        if let error = error {
                            downloadError = error.localizedDescription
                            return
                        }
                        
                        // Validate HTTP response
                        if let httpResponse = response as? HTTPURLResponse {
                            guard (200...299).contains(httpResponse.statusCode) else {
                                let statusMessage: String
                                switch httpResponse.statusCode {
                                case 404:
                                    statusMessage = String(localized: "setup.whiskywine.error.fileNotFound")
                                case 403:
                                    statusMessage = String(localized: "setup.whiskywine.error.accessDenied")
                                case 429:
                                    statusMessage = String(localized: "setup.whiskywine.error.rateLimit")
                                case 500...599:
                                    statusMessage = String(localized: "setup.whiskywine.error.serverError")
                                default:
                                    statusMessage = String(format: String(localized: "setup.whiskywine.error.httpError"), httpResponse.statusCode)
                                }
                                downloadError = String(format: String(localized: "setup.whiskywine.error.downloadFailed"), statusMessage)
                                return
                            }
                        }
                        
                        if let url = url {
                            tarLocation = url
                            proceed()
                        } else {
                            downloadError = String(localized: "setup.whiskywine.error.noFileReceived")
                        }
                    }
                }
                
                observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
                    Task { @MainActor in
                        let currentTime = Date()
                        let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                        if completedBytes > 0 {
                            downloadSpeed = Double(completedBytes) / elapsedTime
                        }
                        totalBytes = task.countOfBytesExpectedToReceive
                        completedBytes = task.countOfBytesReceived
                        if totalBytes > 0 {
                            fractionProgress = Double(completedBytes) / Double(totalBytes)
                        }
                    }
                }
                
                startTime = Date()
                downloadTask?.resume()
            }
        } catch {
            await MainActor.run {
                downloadError = String(format: String(localized: "setup.whiskywine.error.fetchVersionFailed"), error.localizedDescription)
            }
        }
    }
}

