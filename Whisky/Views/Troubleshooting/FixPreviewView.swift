//
//  FixPreviewView.swift
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

/// Diff-style fix preview with Apply button and confirmation for high-impact changes.
///
/// Placeholder implementation. Full version in Task 2.
struct FixPreviewView: View {
    let node: FlowStepNode
    @ObservedObject var engine: TroubleshootingFlowEngine
    let bottle: Bottle
    let program: Program?

    var body: some View {
        Text("Fix: \(node.title ?? node.id)")
    }
}
