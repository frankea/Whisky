//
//  GameConfigurationView.swift
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

/// The primary entry point for browsing the game compatibility database.
///
/// Displays a searchable, filterable list of game configurations. Users can
/// search by title and aliases, filter by rating/store/backend, and navigate
/// to a detail view for each entry.
struct GameConfigurationView: View {
    @ObservedObject var bottle: Bottle
    @State private var entries: [GameDBEntry] = []
    @State private var searchText: String = ""
    @State private var selectedRating: CompatibilityRating?
    @State private var selectedStore: String?
    @State private var selectedBackend: String?

    // MARK: - Computed Properties

    private var filteredEntries: [GameDBEntry] {
        var result = entries

        // Apply search filter
        if !searchText.isEmpty {
            result = GameMatcher.searchEntries(searchText, in: result)
        }

        // Apply rating filter
        if let rating = selectedRating {
            result = result.filter { $0.rating == rating }
        }

        // Apply store filter
        if let store = selectedStore {
            result = result.filter { $0.store == store }
        }

        // Apply backend filter
        if let backend = selectedBackend {
            result = result.filter { entry in
                guard let variant = entry.defaultVariant,
                      let entryBackend = variant.settings.graphicsBackend
                else {
                    return false
                }
                return backendDisplayName(entryBackend) == backend
            }
        }

        return result
    }

    private var availableStores: [String] {
        Array(Set(entries.compactMap(\.store))).sorted()
    }

    private var availableBackends: [String] {
        let backends = entries.compactMap { entry -> String? in
            guard let variant = entry.defaultVariant,
                  let backend = variant.settings.graphicsBackend
            else {
                return nil
            }
            return backendDisplayName(backend)
        }
        return Array(Set(backends)).sorted()
    }

    // MARK: - Body

    var body: some View {
        List {
            if filteredEntries.isEmpty {
                emptyStateView
                    .accessibilityIdentifier("gamedb.emptyState")
            } else {
                ForEach(filteredEntries, id: \.id) { entry in
                    NavigationLink {
                        GameEntryDetailView(entry: entry, bottle: bottle)
                    } label: {
                        GameEntryRowView(entry: entry)
                    }
                    .accessibilityIdentifier("gamedb.row.\(entry.id)")
                }
            }
        }
        .accessibilityIdentifier("gamedb.list")
        .searchable(text: $searchText, prompt: "gamedb.search.prompt")
        .safeAreaInset(edge: .top) {
            filterBar
        }
        .navigationTitle("gamedb.title")
        .onAppear {
            entries = GameDBLoader.loadDefaults()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Rating filter
                Picker(selection: $selectedRating) {
                    Text("gamedb.filter.allRatings")
                        .tag(nil as CompatibilityRating?)
                    ForEach(CompatibilityRating.allCases, id: \.self) { rating in
                        Text(rating.displayName)
                            .tag(rating as CompatibilityRating?)
                    }
                } label: {
                    Text("gamedb.filter.rating")
                }
                .pickerStyle(.menu)

                // Store filter
                Picker(selection: $selectedStore) {
                    Text("gamedb.filter.allStores")
                        .tag(nil as String?)
                    ForEach(availableStores, id: \.self) { store in
                        Text(store.capitalized)
                            .tag(store as String?)
                    }
                } label: {
                    Text("gamedb.filter.store")
                }
                .pickerStyle(.menu)

                // Backend filter
                Picker(selection: $selectedBackend) {
                    Text("gamedb.filter.allBackends")
                        .tag(nil as String?)
                    ForEach(availableBackends, id: \.self) { backend in
                        Text(backend)
                            .tag(backend as String?)
                    }
                } label: {
                    Text("gamedb.filter.backend")
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label {
                if searchText.isEmpty {
                    Text("gamedb.empty.noData")
                } else {
                    Text("gamedb.empty.noResults \(searchText)")
                }
            } icon: {
                Image(systemName: "gamecontroller")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func backendDisplayName(_ backend: GraphicsBackend) -> String? {
        switch backend {
        case .d3dMetal: "D3DMetal"
        case .dxvk: "DXVK"
        case .wined3d: "WineD3D"
        case .recommended: nil
        }
    }
}
