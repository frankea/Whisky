//
//  LogViewerView.swift
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

import AppKit
import SwiftUI
import WhiskyKit

/// Filter modes for the log viewer.
enum LogFilterMode: Equatable {
    case all
    case tagged
    case crashRelated
    case category(CrashCategory)
}

/// NSTextView-backed log viewer with inline tagging, gutter markers, and filtering.
struct LogViewerView: View {
    let logText: String
    let matches: [DiagnosisMatch]
    @Binding var filterMode: LogFilterMode
    @Binding var activeCategoryFilter: CrashCategory?
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            LogTextView(
                logText: logText,
                matches: matches,
                filterMode: filterMode,
                searchText: searchText
            )
        }
    }
}

// MARK: - Filter Bar

extension LogViewerView {
    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton(title: "Show all", mode: .all)
            filterButton(title: "Only tagged", mode: .tagged)
            filterButton(title: "Crash-related", mode: .crashRelated)
            Spacer()
            TextField("Search log\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }

    private func filterButton(title: String, mode: LogFilterMode) -> some View {
        Button {
            filterMode = mode
            if case .category = mode {} else {
                activeCategoryFilter = nil
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(filterMode == mode ? .semibold : .regular)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    filterMode == mode
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSViewRepresentable

/// NSTextView wrapper providing high-performance log rendering with line tagging.
struct LogTextView: NSViewRepresentable {
    let logText: String
    let matches: [DiagnosisMatch]
    let filterMode: LogFilterMode
    let searchText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 4)
        context.coordinator.textView = textView
        applyContent(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyContent(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: NSTextView?

        func scrollToLine(_ lineIndex: Int) {
            guard let textView, let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            var currentLine = 0
            var charIndex = 0
            while currentLine < lineIndex, charIndex < text.length {
                let range = text.lineRange(for: NSRange(location: charIndex, length: 0))
                charIndex = NSMaxRange(range)
                currentLine += 1
            }
            let targetRange = NSRange(location: charIndex, length: 0)
            textView.scrollRangeToVisible(targetRange)
        }
    }

    // MARK: - Content Application

    private func applyContent(to textView: NSTextView) {
        let allLines = logText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let matchedLineIndices = Set(matches.map(\.lineIndex))

        let filteredLines: [(index: Int, text: String)] = filterLines(
            allLines: allLines,
            matchedIndices: matchedLineIndices
        )

        let matchLookup = buildMatchLookup()
        let attributed = buildAttributedString(
            filteredLines: filteredLines,
            matchLookup: matchLookup
        )

        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.setAttributedString(attributed)
        storage.endEditing()
    }

    private func filterLines(
        allLines: [String],
        matchedIndices: Set<Int>
    ) -> [(index: Int, text: String)] {
        allLines.enumerated()
            .filter { passesFilter(lineIndex: $0.offset, lineText: $0.element, matchedIndices: matchedIndices) }
            .map { (index: $0.offset, text: $0.element) }
    }

    private func passesFilter(lineIndex: Int, lineText: String, matchedIndices: Set<Int>) -> Bool {
        // Search text filter
        if !searchText.isEmpty, !lineText.localizedCaseInsensitiveContains(searchText) {
            return false
        }

        switch filterMode {
        case .all:
            return true
        case .tagged:
            return matchedIndices.contains(lineIndex)
        case .crashRelated:
            return matches.contains { match in
                match.lineIndex == lineIndex &&
                    (match.pattern.category == .coreCrashFatal || match.pattern.category == .graphics)
            }
        case let .category(category):
            return matches.contains { $0.lineIndex == lineIndex && $0.pattern.category == category }
        }
    }
}

// MARK: - Match Lookup

extension LogTextView {
    private func buildMatchLookup() -> [Int: DiagnosisMatch] {
        var lookup: [Int: DiagnosisMatch] = [:]
        for match in matches {
            if let existing = lookup[match.lineIndex] {
                if match.pattern.severity > existing.pattern.severity {
                    lookup[match.lineIndex] = match
                }
            } else {
                lookup[match.lineIndex] = match
            }
        }
        return lookup
    }
}

// MARK: - Attributed String Builder

extension LogTextView {
    private func buildAttributedString(
        filteredLines: [(index: Int, text: String)],
        matchLookup: [Int: DiagnosisMatch]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let baseColor = NSColor.textColor
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = 1

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: baseParagraph
        ]

        for (idx, entry) in filteredLines.enumerated() {
            let lineNumber = String(format: "%5d ", entry.index + 1)
            var lineContent: String

            if let match = matchLookup[entry.index] {
                let marker = gutterMarker(for: match)
                lineContent = "\(lineNumber)\(marker) \(entry.text)"
            } else {
                lineContent = "\(lineNumber)  \(entry.text)"
            }

            if idx < filteredLines.count - 1 {
                lineContent += "\n"
            }

            let lineAttr = NSMutableAttributedString(string: lineContent, attributes: baseAttributes)

            // Apply background tint for tagged lines
            if let match = matchLookup[entry.index] {
                let bgColor = backgroundColor(for: match)
                let fullRange = NSRange(location: 0, length: lineAttr.length)
                lineAttr.addAttribute(.backgroundColor, value: bgColor, range: fullRange)

                // Color the gutter marker
                let markerColor = markerColor(for: match)
                let markerStart = lineNumber.count
                let markerLength = 1
                if markerStart + markerLength <= lineAttr.length {
                    let markerRange = NSRange(location: markerStart, length: markerLength)
                    lineAttr.addAttribute(.foregroundColor, value: markerColor, range: markerRange)
                }
            }

            result.append(lineAttr)
        }

        return result
    }

    private func gutterMarker(for match: DiagnosisMatch) -> String {
        switch match.pattern.category {
        case .coreCrashFatal:
            "\u{25CF}" // filled circle
        case .graphics:
            "\u{25CF}"
        case .dependenciesLoading:
            "\u{25CF}"
        case .prefixFilesystem:
            "\u{25CF}"
        case .networkingLaunchers:
            "\u{25CF}"
        case .antiCheatUnsupported:
            "\u{25CF}"
        case .otherUnknown:
            "\u{25CB}" // open circle
        }
    }

    private func backgroundColor(for match: DiagnosisMatch) -> NSColor {
        switch match.pattern.category {
        case .coreCrashFatal:
            NSColor.systemRed.withAlphaComponent(0.08)
        case .graphics:
            NSColor.systemOrange.withAlphaComponent(0.08)
        default:
            if match.pattern.severity >= .error {
                NSColor.systemRed.withAlphaComponent(0.06)
            } else if match.pattern.severity >= .warning {
                NSColor.systemYellow.withAlphaComponent(0.06)
            } else {
                NSColor.clear
            }
        }
    }

    private func markerColor(for match: DiagnosisMatch) -> NSColor {
        switch match.pattern.category {
        case .coreCrashFatal:
            .systemRed
        case .graphics:
            .systemOrange
        case .dependenciesLoading:
            .systemBlue
        case .prefixFilesystem:
            .systemPurple
        case .networkingLaunchers:
            .systemCyan
        case .antiCheatUnsupported:
            .systemGray
        case .otherUnknown:
            .secondaryLabelColor
        }
    }
}
