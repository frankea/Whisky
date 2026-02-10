//
//  WhiskyApp.swift
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

import os.log
import Sparkle
import SwiftUI
import WhiskyKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.franke.Whisky", category: "WhiskyApp")

@main
struct WhiskyApp: App {
    @State var showSetup: Bool = false
    @State private var showDiagnosticsSheet: Bool = false
    @State private var crashDiagnosisBanner: CrashDiagnosisBannerState?
    @State private var audioDeviceToast: ToastData?
    @State private var audioMonitor = AudioDeviceMonitor()
    @State private var audioAlertTracker = AudioAlertTracker()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup)
                .frame(minWidth: ViewWidth.large, minHeight: 316)
                .environmentObject(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await WhiskyApp.deleteOldLogs()
                    }

                    startAudioDeviceListening()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .crashDiagnosisAvailable)
                ) { notification in
                    handleCrashDiagnosisNotification(notification)
                }
                .sheet(isPresented: $showDiagnosticsSheet) {
                    DiagnosticsPickerSheet()
                        .environmentObject(BottleVM.shared)
                }
                .overlay(alignment: .top) {
                    if let banner = crashDiagnosisBanner {
                        crashDiagnosisBannerView(banner)
                    }
                }
                .toast($audioDeviceToast)
        }
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            CommandGroup(after: .appInfo) {
                SparkleView(updater: updaterController.updater)
            }
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await WhiskyCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                // Task inherits main actor context from SwiftUI commands builder
                                Task {
                                    BottleVM.shared.bottlesList.paths.append(url)
                                    BottleVM.shared.loadBottles()
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    WhiskyApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    WhiskyApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    WhiskyApp.killBottles() // Better not make things more complicated for ourselves
                    WhiskyApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .help) {
                Button("help.github") {
                    if let url = URL(string: "https://github.com/frankea/Whisky") {
                        openURL(url)
                    }
                }
                Button("help.issues") {
                    if let url = URL(string: "https://github.com/frankea/Whisky/issues") {
                        openURL(url)
                    }
                }
                Divider()
                Button("Run Diagnostics\u{2026}") {
                    showDiagnosticsSheet = true
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])
            }
        }
        Settings {
            SettingsView()
        }
    }

    @MainActor
    static func killBottles() {
        for bottle in BottleVM.shared.bottles {
            // killBottle is fire-and-forget; errors are logged internally
            Wine.killBottle(bottle: bottle)
        }
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]
        )
        else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                logger.warning("Failed to delete log: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Crash Diagnosis Notification

    private func handleCrashDiagnosisNotification(_ notification: Notification) {
        guard let diagnosis = notification.userInfo?["diagnosis"] as? CrashDiagnosis,
              let programPath = notification.userInfo?["programPath"] as? String,
              let logFileURL = notification.userInfo?["logFileURL"] as? URL
        else { return }

        let programName = URL(fileURLWithPath: programPath).deletingPathExtension().lastPathComponent
        crashDiagnosisBanner = CrashDiagnosisBannerState(
            diagnosis: diagnosis,
            programName: programName,
            logFileURL: logFileURL
        )

        // Auto-dismiss after 8 seconds
        Task {
            try? await Task.sleep(for: .seconds(8))
            withAnimation {
                crashDiagnosisBanner = nil
            }
        }
    }

    private func crashDiagnosisBannerView(_ banner: CrashDiagnosisBannerState) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Crash detected \u{2014} \(banner.programName)")
                .fontWeight(.medium)
            Spacer()
            Button("View Diagnosis") {
                crashDiagnosisBanner = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                withAnimation {
                    crashDiagnosisBanner = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .shadow(radius: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Audio Device Alerts

    private func startAudioDeviceListening() {
        audioMonitor.startListening { event in
            Task { @MainActor in
                guard audioAlertTracker.shouldAlert(deviceName: event.deviceName) else { return }

                switch event.eventType {
                case .defaultOutputChanged, .disconnected:
                    let message = String(
                        localized: "audio.alert.disconnected"
                    ) + ": \(event.deviceName)"
                    audioDeviceToast = ToastData(message: message, style: .info)
                case .reconnected:
                    let message = String(
                        localized: "audio.alert.reconnected"
                    ) + ": \(event.deviceName)"
                    audioDeviceToast = ToastData(message: message, style: .success)
                case .sampleRateChanged:
                    // Check for low sample rate (HFP/Bluetooth issue)
                    if let device = audioMonitor.defaultOutputDevice(),
                       device.sampleRate < 22_050, device.sampleRate > 0
                    {
                        let message = String(localized: "audio.alert.lowSampleRate")
                            + ": \(event.deviceName)"
                        audioDeviceToast = ToastData(message: message, style: .info)
                    }
                }
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            logger.error("Failed to run getconf: \(error.localizedDescription)")
            return
        }
        getconf.waitUntilExit()

        let getconfOutput: Data
        do {
            getconfOutput = try pipe.fileHandleForReading.readToEnd() ?? Data()
        } catch {
            logger.error("Failed to read getconf output: \(error.localizedDescription)")
            return
        }

        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else {
            logger.error("Failed to decode getconf output as UTF-8")
            return
        }
        let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "d3dm").path
        do {
            try FileManager.default.removeItem(atPath: d3dmPath)
            logger.info("Successfully cleared shader caches")
        } catch {
            logger.warning("Failed to remove shader cache at \(d3dmPath): \(error.localizedDescription)")
        }
    }
}

// MARK: - Crash Diagnosis Banner State

struct CrashDiagnosisBannerState {
    let diagnosis: CrashDiagnosis
    let programName: String
    let logFileURL: URL
}

// MARK: - Audio Alert Rate Limiter

/// Tracks the last alert time per device name to rate-limit audio device alerts.
/// One alert per device per 3 minutes to avoid notification fatigue.
struct AudioAlertTracker {
    private var lastAlertTimes: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 180 // 3 minutes

    /// Returns true if an alert should be shown for this device.
    mutating func shouldAlert(deviceName: String) -> Bool {
        let now = Date()
        if let lastTime = lastAlertTimes[deviceName],
           now.timeIntervalSince(lastTime) < cooldownInterval
        {
            return false
        }
        lastAlertTimes[deviceName] = now
        return true
    }
}

// MARK: - Diagnostics Picker Sheet

/// Sheet that lets the user select a bottle and program, then opens DiagnosticsView.
struct DiagnosticsPickerSheet: View {
    @EnvironmentObject var bottleVM: BottleVM
    @Environment(\.dismiss) var dismiss

    @State private var selectedBottle: Bottle?
    @State private var selectedProgram: Program?
    @State private var isAnalyzing = false
    @State private var showDiagnosticsResult = false
    @State private var resultDiagnosis: CrashDiagnosis?
    @State private var resultLogText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run Diagnostics")
                .font(.headline)

            Picker("Bottle", selection: $selectedBottle) {
                Text("Select a bottle").tag(nil as Bottle?)
                ForEach(bottleVM.bottles) { bottle in
                    Text(bottle.settings.name).tag(bottle as Bottle?)
                }
            }

            if let bottle = selectedBottle {
                Picker("Program", selection: $selectedProgram) {
                    Text("Select a program").tag(nil as Program?)
                    ForEach(bottle.programs) { program in
                        Text(program.name).tag(program as Program?)
                    }
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Analyze") {
                    runAnalysis()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProgram == nil || isAnalyzing)

                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 400)
        .onChange(of: selectedBottle) { _, _ in
            selectedProgram = nil
        }
        .sheet(isPresented: $showDiagnosticsResult) {
            if let diagnosis = resultDiagnosis, let program = selectedProgram {
                DiagnosticsView(
                    diagnosis: diagnosis,
                    logText: resultLogText,
                    programName: program.name,
                    bottleName: selectedBottle?.settings.name ?? "",
                    timestamp: Date()
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
    }

    private func runAnalysis() {
        guard let program = selectedProgram,
              let logURL = program.settings.lastLogFileURL
        else { return }

        isAnalyzing = true
        Task {
            guard let diagnosis = await Wine.classifyLastRun(logFileURL: logURL, exitCode: 1) else {
                isAnalyzing = false
                return
            }
            resultDiagnosis = diagnosis
            resultLogText = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            isAnalyzing = false
            showDiagnosticsResult = true
        }
    }
}
