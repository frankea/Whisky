//
//  SessionResumeView.swift
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

/// Overlay shown when a paused session is found with Resume/Start over/Discard options.
///
/// Placeholder implementation. Full version in Task 3.
struct SessionResumeView: View {
    let session: TroubleshootingSession
    let stalenessChanges: [StalenessChange]
    var onResume: (TroubleshootingSession) -> Void
    var onStartOver: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        Text("Resume session?")
    }
}
