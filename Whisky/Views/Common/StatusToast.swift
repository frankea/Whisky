//
//  StatusToast.swift
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

/// Style variants for status toast notifications
enum ToastStyle: Equatable {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success: .green
        case .error: .red
        case .info: .blue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .success: "Success"
        case .error: "Error"
        case .info: "Information"
        }
    }
}

/// A toast notification that appears at the bottom of the view
struct StatusToast: View {
    let message: String
    let style: ToastStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style.iconName)
                .foregroundStyle(style.iconColor)
            Text(message)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.accessibilityLabel): \(message)")
        .accessibilityHint("Tap to dismiss")
    }
}

/// View modifier to display toast notifications
struct ToastModifier: ViewModifier {
    @Binding var toast: ToastData?
    let autoDismissDelay: TimeInterval
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    StatusToast(message: toast.message, style: toast.style)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            scheduleDismissIfNeeded(for: toast)
                        }
                        .onChange(of: toast) { _, newToast in
                            scheduleDismissIfNeeded(for: newToast)
                        }
                        .onTapGesture {
                            dismissTask?.cancel()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.toast = nil
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: toast)
    }

    private func scheduleDismissIfNeeded(for toast: ToastData) {
        dismissTask?.cancel()
        guard toast.autoDismiss else { return }

        let currentMessage = toast.message
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(autoDismissDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.toast?.message == currentMessage {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.toast = nil
                    }
                }
            }
        }
    }
}

/// Data model for toast notifications
struct ToastData: Equatable {
    let message: String
    let style: ToastStyle
    var autoDismiss: Bool = true
}

extension View {
    /// Adds a toast notification overlay to the view
    /// - Parameters:
    ///   - toast: Binding to the toast data. Set to non-nil to show toast.
    ///   - autoDismissDelay: Time in seconds before auto-dismissing (default 3s)
    func toast(_ toast: Binding<ToastData?>, autoDismissDelay: TimeInterval = 3.0) -> some View {
        modifier(ToastModifier(toast: toast, autoDismissDelay: autoDismissDelay))
    }
}

#Preview("Success Toast") {
    VStack {
        Text("Content")
    }
    .frame(width: 400, height: 300)
    .overlay(alignment: .bottom) {
        StatusToast(message: "Launched: notepad.exe", style: .success)
            .padding(.bottom, 80)
    }
}

#Preview("Error Toast") {
    VStack {
        Text("Content")
    }
    .frame(width: 400, height: 300)
    .overlay(alignment: .bottom) {
        StatusToast(message: "Launch failed: File not found", style: .error)
            .padding(.bottom, 80)
    }
}
