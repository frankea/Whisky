//
//  BackendPickerView.swift
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

struct BackendPickerView: View {
    @Binding var selection: GraphicsBackend
    let resolvedBackend: GraphicsBackend

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                    BackendCard(
                        backend: backend,
                        isSelected: selection == backend,
                        resolvedBackend: backend == .recommended ? resolvedBackend : nil
                    ) {
                        selection = backend
                    }
                }
            }

            // Helper text below grid
            helperText

            // Inline compatibility warning
            if let warning = compatibilityWarning {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Helper Text

    @ViewBuilder
    private var helperText: some View {
        if selection == .recommended {
            Text("config.graphics.helperCurrently \(resolvedBackend.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("config.graphics.helperNextLaunch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Compatibility Warning

    private var compatibilityWarning: String? {
        switch selection {
        case .dxvk:
            if #unavailable(macOS 14.0) {
                return String(localized: "config.graphics.warning.dxvkMacOS")
            }
            return nil
        case .d3dMetal:
            if #unavailable(macOS 14.0) {
                return String(localized: "config.graphics.warning.d3dmetalMacOS")
            }
            return nil
        case .wined3d, .recommended:
            return nil
        }
    }
}

// MARK: - BackendCard

private struct BackendCard: View {
    let backend: GraphicsBackend
    let isSelected: Bool
    let resolvedBackend: GraphicsBackend?
    let action: () -> Void

    @State private var showRationale: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .white : .secondary)
                    Spacer()
                    if let tag = tagLabel {
                        Text(tag.text)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tag.color.opacity(isSelected ? 0.3 : 0.15), in: Capsule())
                            .foregroundStyle(isSelected ? .white : tag.color)
                    }
                    if backend == .recommended {
                        Button {
                            showRationale.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showRationale) {
                            Text(GraphicsBackendResolver.rationale())
                                .font(.caption)
                                .padding()
                                .frame(maxWidth: 240)
                        }
                    }
                }

                Text(backend.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(backend.summary)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)

                if backend == .recommended, isSelected, let resolved = resolvedBackend {
                    Text("config.graphics.currentlyUsing \(resolved.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Icon

    private var iconName: String {
        switch backend {
        case .recommended:
            "sparkles"
        case .d3dMetal:
            "display"
        case .dxvk:
            "arrow.triangle.2.circlepath"
        case .wined3d:
            "cup.and.saucer"
        }
    }

    // MARK: - Tag

    private var tagLabel: (text: String, color: Color)? {
        switch backend {
        case .recommended:
            nil
        case .d3dMetal:
            (String(localized: "config.graphics.tag.fast"), .green)
        case .dxvk:
            (String(localized: "config.graphics.tag.compatible"), .blue)
        case .wined3d:
            (String(localized: "config.graphics.tag.fallback"), .orange)
        }
    }
}
