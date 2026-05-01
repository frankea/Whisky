//
//  RunningProcessesView.swift
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

struct RunningProcessesView: View {
    @ObservedObject var bottle: Bottle
    @StateObject private var viewModel: ProcessesViewModel
    @State private var toast: ToastData?
    @State private var showStopConfirmation: Bool = false
    @State private var showForceStopConfirmation: Bool = false
    @State private var showingDetail: Bool = false

    init(bottle: Bottle) {
        self.bottle = bottle
        _viewModel = StateObject(wrappedValue: ProcessesViewModel(bottle: bottle))
    }

    var body: some View {
        ZStack {
            if viewModel.filteredProcesses.isEmpty, viewModel.shutdownState == .idle {
                emptyStateView
            } else {
                processTableView
            }
            if viewModel.shutdownState != .idle {
                shutdownOverlay
            }
        }
        .navigationTitle("tab.processes")
        .toolbar { processToolbar }
        .toast($toast)
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
        .confirmationDialog(
            String(localized: "process.confirm.stop.title"),
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            stopConfirmationButtons
        } message: {
            stopConfirmationMessage
        }
        .confirmationDialog(
            String(localized: "process.confirm.forceStop.title"),
            isPresented: $showForceStopConfirmation,
            titleVisibility: .visible
        ) {
            forceStopConfirmationButtons
        } message: {
            Text("process.confirm.forceStop.message")
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if viewModel.isPolling {
                ProgressView()
                    .controlSize(.small)
                Text("process.checking")
                    .foregroundStyle(.secondary)
            } else {
                Text("process.empty")
                    .foregroundStyle(.secondary)
                Button("process.action.refresh") {
                    Task { await viewModel.refreshProcessList() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shutdown Overlay

    private var shutdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                switch viewModel.shutdownState {
                case .stopping:
                    Text("process.stopping")
                case .forceKilling:
                    Text("process.forceStopping")
                case .idle:
                    EmptyView()
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Confirmation Dialogs

    @ViewBuilder
    private var stopConfirmationButtons: some View {
        Button(String(localized: "process.action.stopBottle"), role: .destructive) {
            Task {
                let count = await viewModel.stopBottle()
                withAnimation {
                    toast = ToastData(
                        message: String(localized: "process.toast.stopped \(count)"),
                        style: .success
                    )
                }
            }
        }
        Button("button.cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var stopConfirmationMessage: some View {
        let hasUntracked = viewModel.processes.contains { $0.source == .untracked }
        if hasUntracked {
            Text("process.confirm.stop.message")
                + Text("\n")
                + Text("process.confirm.stop.includesUntracked")
        } else {
            Text("process.confirm.stop.message")
        }
    }

    @ViewBuilder
    private var forceStopConfirmationButtons: some View {
        Button(String(localized: "process.action.forceStop"), role: .destructive) {
            Task {
                let count = await viewModel.forceStopBottle()
                withAnimation {
                    toast = ToastData(
                        message: String(localized: "process.toast.stopped \(count)"),
                        style: .success
                    )
                }
            }
        }
        Button("button.cancel", role: .cancel) {}
    }
}

// MARK: - Process Table & Detail

extension RunningProcessesView {
    var processTableView: some View {
        VStack(spacing: 0) {
            Table(viewModel.filteredProcesses, selection: $viewModel.selectedProcessID) {
                TableColumn(String(localized: "process.column.name")) { process in
                    Text(process.imageName)
                }
                .width(min: 120, ideal: 180)

                TableColumn(String(localized: "process.column.pid")) { process in
                    Text(String(process.winePID))
                        .monospacedDigit()
                }
                .width(min: 50, ideal: 60)

                TableColumn(String(localized: "process.column.memory")) { process in
                    Text(process.memoryUsage)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 80)

                TableColumn(String(localized: "process.column.started")) { process in
                    if let launchTime = process.launchTime {
                        Text(launchTime, style: .relative)
                    } else {
                        Text("process.column.started.unknown")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: 70, ideal: 90)

                TableColumn(String(localized: "process.column.kind")) { process in
                    Text(localizedKind(process.kind))
                }
                .width(min: 50, ideal: 60)

                TableColumn(String(localized: "process.column.source")) { process in
                    Text(localizedSource(process.source))
                        .foregroundStyle(process.source == .untracked ? .orange : .primary)
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: Int32.self) { selectedIDs in
                if let processID = selectedIDs.first,
                   let process = viewModel.filteredProcesses.first(where: { $0.id == processID }) {
                    processContextMenu(for: process)
                }
            } primaryAction: { _ in }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showingDetail,
               let selectedID = viewModel.selectedProcessID,
               let process = viewModel.filteredProcesses.first(where: { $0.id == selectedID }) {
                processDetailView(for: process)
            }
        }
    }

    @ViewBuilder
    func processContextMenu(for process: WineProcess) -> some View {
        Button {
            Task { await viewModel.quitProcess(process) }
        } label: {
            Label("process.action.quit", systemImage: "xmark.circle")
        }
        .disabled(viewModel.shutdownState != .idle)

        Button {
            Task { await viewModel.forceQuitProcess(process) }
        } label: {
            Label("process.action.forceQuit", systemImage: "xmark.circle.fill")
        }
        .disabled(viewModel.shutdownState != .idle)

        Divider()

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(process.winePID), forType: .string)
        } label: {
            Label("process.action.copyPID", systemImage: "doc.on.clipboard")
        }

        Button {
            withAnimation { showingDetail.toggle() }
        } label: {
            Label("process.action.showDetails", systemImage: "info.circle")
        }
    }

    func processDetailView(for process: WineProcess) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "process.column.name", value: process.imageName)
                    detailRow(label: "process.detail.winePID", value: String(process.winePID))
                    if let macosPID = process.macosPID {
                        detailRow(label: "process.detail.macosPID", value: String(macosPID))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "process.detail.source", value: localizedSource(process.source))
                    detailRow(label: "process.detail.kind", value: localizedKind(process.kind))
                    if let commandLine = process.commandLine {
                        detailRow(label: "process.column.name", value: commandLine)
                    }
                }
                Spacer()
            }
            if process.kind == .system || process.kind == .service {
                Label("process.detail.systemWarning", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    func detailRow(label: LocalizedStringResource, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Toolbar & Helpers

extension RunningProcessesView {
    @ToolbarContentBuilder
    var processToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Picker("process.filter.label", selection: $viewModel.filterMode) {
                Text("process.filter.apps").tag(ProcessesViewModel.FilterMode.appsOnly)
                Text("process.filter.all").tag(ProcessesViewModel.FilterMode.all)
            }
            .pickerStyle(.segmented)

            Button {
                Task { await viewModel.refreshProcessList() }
            } label: {
                Label("process.action.refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                showStopConfirmation = true
            } label: {
                Label("process.action.stopBottle", systemImage: "stop.circle")
            }
            .disabled(viewModel.shutdownState != .idle)
            .keyboardShortcut(.delete, modifiers: .command)

            Button {
                showForceStopConfirmation = true
            } label: {
                Label("process.action.forceStop", systemImage: "stop.circle.fill")
            }
            .disabled(viewModel.shutdownState != .idle)
        }
    }

    func localizedKind(_ kind: ProcessKind) -> String {
        switch kind {
        case .app: String(localized: "process.kind.app")
        case .service: String(localized: "process.kind.service")
        case .system: String(localized: "process.kind.system")
        }
    }

    func localizedSource(_ source: ProcessSource) -> String {
        switch source {
        case .whisky: String(localized: "process.source.whisky")
        case .untracked: String(localized: "process.source.untracked")
        }
    }
}
