//
//  SettingItemView.swift
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

enum LoadingState: Equatable {
    case loading
    case modifying
    case success
    case failed
}

struct SettingItemView<Content: View>: View {
    let title: String.LocalizationValue
    /// Optional one-line explanation shown beneath the title, so users can make
    /// an informed choice without external docs.
    var description: String.LocalizationValue?
    let loadingState: LoadingState
    var onRetry: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @Namespace private var viewId
    @Namespace private var progressViewId

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: title))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let description {
                    Text(String(localized: description))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                switch loadingState {
                case .loading, .modifying:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .matchedGeometryEffect(id: progressViewId, in: viewId)
                case .success:
                    content()
                        .labelsHidden()
                        .disabled(loadingState != .success)
                case .failed:
                    HStack(spacing: 4) {
                        Text("config.notAvailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let onRetry {
                            Button(action: onRetry) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("config.retry")
                        }
                    }
                }
            }.animation(.default, value: loadingState)
        }
    }
}
