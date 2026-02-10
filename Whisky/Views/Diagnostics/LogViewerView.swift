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

import SwiftUI
import WhiskyKit

/// Filter modes for the log viewer.
enum LogFilterMode: Equatable {
    /// Show the complete log.
    case all
    /// Show only lines that matched any diagnostic pattern.
    case tagged
    /// Show only lines matching crash/fatal or graphics categories.
    case crashRelated
    /// Show only lines matching a specific category.
    case category(CrashCategory)
}

/// Placeholder log viewer. Full NSTextView-backed implementation in Task 2.
struct LogViewerView: View {
    let logText: String
    let matches: [DiagnosisMatch]
    @Binding var filterMode: LogFilterMode
    @Binding var activeCategoryFilter: CrashCategory?
    @Binding var searchText: String

    var body: some View {
        Text("Log viewer placeholder")
    }
}
