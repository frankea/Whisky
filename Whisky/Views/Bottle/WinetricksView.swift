//
//  WinetricksView.swift
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

struct WinetricksView: View {
    var bottle: Bottle
    @State private var winetricks: [WinetricksCategory]?
    @State private var selectedTrick: UUID?
    @State private var installedVerbs: Set<String> = []
    @State private var isLoadingInstalledVerbs = true
    @State private var verbFilter: VerbFilter = .all
    @Environment(\.dismiss) var dismiss

    private enum VerbFilter: String, CaseIterable {
        case all
        case installed
    }

    var body: some View {
        VStack {
            VStack {
                Text("winetricks.title")
                    .font(.title)
            }
            .padding(.bottom)

            if let winetricks {
                filterPicker
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                TabView {
                    ForEach(winetricks, id: \.category) { category in
                        verbTable(for: category)
                            .tabItem {
                                let key = "winetricks.category.\(category.category.rawValue)"
                                Text(NSLocalizedString(key, comment: ""))
                            }
                    }
                }
                .overlay {
                    if verbFilter == .installed, isLoadingInstalledVerbs {
                        VStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("winetricks.loading.installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("create.cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("button.run") {
                            guard let selectedTrick else {
                                return
                            }

                            let trick = winetricks.flatMap(\.verbs)
                                .first(where: { $0.id == selectedTrick })
                            if let trickName = trick?.name {
                                Task.detached {
                                    await Winetricks.runCommand(
                                        command: trickName,
                                        bottle: bottle
                                    )
                                }
                            }
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                Spacer()
            }
        }
        .padding()
        .onAppear {
            Task.detached {
                let tricks = await Winetricks.parseVerbs()

                await MainActor.run {
                    winetricks = tricks
                }
            }

            Task.detached {
                let result = await Winetricks.loadInstalledVerbs(for: bottle)
                await MainActor.run {
                    installedVerbs = result.verbs
                    isLoadingInstalledVerbs = false
                }

                // If loaded from cache, do a background refresh
                if result.fromCache {
                    if let fresh = await Winetricks.listInstalledVerbs(for: bottle) {
                        await MainActor.run {
                            installedVerbs = fresh
                        }
                        let bottleURL = await MainActor.run { bottle.url }
                        var cache = WinetricksVerbCache(
                            installedVerbs: fresh,
                            lastChecked: Date()
                        )
                        let logInfo = WinetricksVerbCache.winetricksLogInfo(for: bottleURL)
                        cache.logFileSize = logInfo.size
                        cache.logFileModDate = logInfo.modDate
                        try? WinetricksVerbCache.save(cache, to: bottleURL)
                    }
                }
            }
        }
        .frame(minWidth: ViewWidth.large, minHeight: 400)
    }

    // MARK: - Subviews

    private var filterPicker: some View {
        Picker("winetricks.filter", selection: $verbFilter) {
            Text("winetricks.filter.all")
                .tag(VerbFilter.all)
            if installedVerbs.isEmpty {
                Text("winetricks.filter.installed")
                    .tag(VerbFilter.installed)
            } else {
                Text("winetricks.filter.installedCount \(installedVerbs.count)")
                    .tag(VerbFilter.installed)
            }
        }
        .pickerStyle(.segmented)
    }

    private func filteredVerbs(for category: WinetricksCategory) -> [WinetricksVerb] {
        switch verbFilter {
        case .all:
            category.verbs
        case .installed:
            category.verbs.filter { installedVerbs.contains($0.name) }
        }
    }

    private func verbTable(for category: WinetricksCategory) -> some View {
        let verbs = filteredVerbs(for: category)
        return Table(verbs, selection: $selectedTrick) {
            TableColumn("winetricks.table.installed") { verb in
                if installedVerbs.contains(verb.name) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .width(30)
            TableColumn("winetricks.table.name", value: \.name)
            TableColumn("winetricks.table.description", value: \.description)
        }
    }
}
