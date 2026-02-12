//
//  StepCardView.swift
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

/// Renders a single flow step node as a card with evidence and confidence display.
///
/// Placeholder implementation. Full version in Task 2.
struct StepCardView: View {
    let node: FlowStepNode
    let checkResult: CheckResult?
    let isRunning: Bool

    var body: some View {
        Text("Step: \(node.title ?? node.id)")
    }
}
