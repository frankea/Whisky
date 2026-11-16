//
//  SetupView.swift
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

enum SetupStage {
    case rosetta
    case whiskyWineDownload
    case whiskyWineInstall
}

struct SetupView: View {
    @State private var path: [SetupStage] = []
    @State var tarLocation: URL = .init(fileURLWithPath: "")
    @State private var whiskyWineDiagnostics = WhiskyWineSetupDiagnostics()
    @Binding var showSetup: Bool
    var firstTime: Bool = true
    /// Set when the user accepted a runtime update. The installed runtime stays
    /// in place until the new one has been extracted, so setup has to go to the
    /// download stage even though a runtime is already installed. A binding,
    /// since the user can accept the update after setup has opened.
    @Binding var updatingRuntime: Bool

    var body: some View {
        VStack {
            NavigationStack(path: $path) {
                WelcomeView(path: $path, showSetup: $showSetup, firstTime: firstTime, updatingRuntime: updatingRuntime)
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: SetupStage.self) { stage in
                        switch stage {
                        case .rosetta:
                            RosettaView(path: $path, showSetup: $showSetup, updatingRuntime: $updatingRuntime)
                        case .whiskyWineDownload:
                            WhiskyWineDownloadView(
                                tarLocation: $tarLocation,
                                path: $path,
                                showSetup: $showSetup,
                                diagnostics: $whiskyWineDiagnostics
                            )
                        case .whiskyWineInstall:
                            WhiskyWineInstallView(
                                tarLocation: $tarLocation,
                                path: $path,
                                showSetup: $showSetup,
                                diagnostics: $whiskyWineDiagnostics
                            )
                        }
                    }
            }
        }
        .padding()
        .interactiveDismissDisabled()
        .onAppear {
            // An accepted runtime update goes to the download stage ahead of the
            // consent check. The installed runtime stays in place until the new
            // one is extracted, so the welcome screen would see it as installed
            // and offer only Done; with consent still undecided (the default)
            // that left most users unable to update. A missing Rosetta still
            // goes through the welcome screen to the Rosetta step, which then
            // continues to the download because an update is pending.
            if updatingRuntime {
                if Rosetta2.isRosettaInstalled {
                    path = [.whiskyWineDownload]
                }
                return
            }
            // Skip the welcome screen and go straight to the download stage only
            // once telemetry consent is already decided. WelcomeView is the sole
            // screen carrying the consent toggle, so on a genuine first run (consent
            // still undecided) we must show it even when the runtime is missing —
            // otherwise the opt-in would be unreachable. The only call site
            // (ContentView) always passes `firstTime: false`, so the consent check,
            // not `firstTime`, is what keeps the welcome screen reachable. A missing
            // Rosetta also keeps it, since the welcome screen routes to the Rosetta
            // step first and the download stage would skip it.
            if !firstTime, Telemetry.consent != .undecided, Rosetta2.isRosettaInstalled,
               !WhiskyWineInstaller.isWhiskyWineInstalled() {
                path = [.whiskyWineDownload]
            }
        }
    }
}
