//
//  LaunchTimeBanner.swift
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

// MARK: - Banner Data

/// Data model for the launch-time fix notification banner.
///
/// Carries a summary of launcher-specific fixes that were applied, including the
/// launcher name, fix count, and deduplicated category list for display.
struct LaunchTimeBannerData: Equatable {
    /// The display name of the detected launcher.
    let launcherName: String
    /// Deduplicated categories of fixes applied (e.g. ["locale", "sandbox"]).
    let fixCategories: [String]
    /// Total number of individual environment variable fixes applied.
    let fixCount: Int

    /// Creates banner data from a ``LauncherType`` by querying its fix metadata.
    ///
    /// - Parameter launcher: The detected launcher type.
    /// - Returns: Banner data summarizing the launcher's fixes.
    static func from(launcher: LauncherType) -> LaunchTimeBannerData {
        let details = launcher.fixDetails()
        let categories = Array(Set(details.map(\.category.rawValue))).sorted()
        return LaunchTimeBannerData(
            launcherName: launcher.displayName,
            fixCategories: categories,
            fixCount: details.count
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the user taps "View Details" on the launch-time banner to
    /// navigate to the Launcher section in ConfigView.
    static let openLauncherConfig = Notification.Name(
        "com.isaacmarovitz.Whisky.openLauncherConfig"
    )
}

// MARK: - Banner View

/// A lightweight, non-blocking banner that notifies the user when launcher
/// compatibility fixes have been applied at launch time.
///
/// The banner slides in from the top with an orange tint, displays the launcher
/// name and a summary of applied fixes, then auto-dismisses after 5 seconds.
/// This is tier 1 of the three-tier launcher discovery model.
struct LaunchTimeBanner: View {
    let data: LaunchTimeBannerData
    var onViewDetails: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Launcher fixes applied: \(data.launcherName)")
                    .fontWeight(.medium)
                    .font(.callout)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("View Details") {
                onViewDetails?()
                NotificationCenter.default.post(name: .openLauncherConfig, object: nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "accessibility.toast.launcherFixes")
                + ": \(data.launcherName), \(data.fixCount) settings"
        )
    }

    private var subtitleText: String {
        let categories = data.fixCategories.joined(separator: ", ")
        return "\(data.fixCount) settings configured (\(categories))"
    }
}

// MARK: - Banner View Modifier

/// View modifier that overlays a ``LaunchTimeBanner`` at the top of the view.
///
/// The banner auto-dismisses after 5 seconds and can be tapped to dismiss early.
/// This follows the crash diagnosis banner pattern from Phase 5.
struct LaunchTimeBannerModifier: ViewModifier {
    @Binding var bannerData: LaunchTimeBannerData?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let data = bannerData {
                    LaunchTimeBanner(
                        data: data,
                        onViewDetails: {
                            dismissBanner()
                        },
                        onDismiss: {
                            dismissBanner()
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        dismissBanner()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: bannerData)
            .onChange(of: bannerData) { _, newValue in
                dismissTask?.cancel()
                if newValue != nil {
                    scheduleAutoDismiss()
                }
            }
    }

    private func scheduleAutoDismiss() {
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissBanner()
            }
        }
    }

    private func dismissBanner() {
        dismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) {
            bannerData = nil
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a launch-time fix banner overlay to the view.
    ///
    /// - Parameter bannerData: Binding to the banner data. Set to non-nil to show the banner.
    /// - Returns: A view with the launch-time banner overlay.
    func launchTimeBanner(_ bannerData: Binding<LaunchTimeBannerData?>) -> some View {
        modifier(LaunchTimeBannerModifier(bannerData: bannerData))
    }
}
