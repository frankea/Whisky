//
//  GPTKImporter+InterposerPolicy.swift
//  WhiskyKit
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

import Foundation

/// Which payloads the runtime's interposers may go in front of, and when an
/// existing install is brought in line.
///
/// Neither interposer just forwards to Apple's DLL. The D3D12 one answers on
/// Apple's export ordinals and patches itself into the game's command lists,
/// the DXGI one rewrites the adapter's vtable. Both were written and measured
/// against the GPTK 4 betas (frankea/Whisky#163), and that does not carry over
/// to other payloads: with GPTK 3.0 the DXGI interposer's `VirtualProtect` on
/// the adapter vtable fails with error 87 and the driver version is never
/// answered, and Red Dead Redemption 2 crashes at startup with the D3D12 one in
/// the slot (frankea/Whisky#276).
extension GPTKImporter {
    /// The GPTK major version the interposers were validated against.
    static let interposerPayloadMajorVersion = 4

    /// Whether the interposers may go in front of a payload of `version`.
    ///
    /// Keyed on the major version Apple's `CFBundleShortVersionString` leads
    /// with ("3.0", "4.0b2"), so later 4.x betas and the release keep them while
    /// other lines go without until someone measures them there. A version that
    /// cannot be read fails closed.
    static func interposersSupport(payloadVersion version: String?) -> Bool {
        guard let version, let major = Int(version.prefix { $0.isASCII && $0.isNumber }) else {
            return false
        }
        return major == interposerPayloadMajorVersion
    }

    /// The version of the D3DMetal framework in `folder`'s runtime, whether it
    /// was deployed from the store or copied in by hand.
    static func deployedPayloadVersion(inLibraryFolder folder: URL) -> String? {
        frameworkVersion(
            inExternal: folder.appending(path: "Wine").appending(path: "lib").appending(path: "external")
        )
    }

    /// Whether the payload in `folder`'s runtime is the one `store` deployed.
    ///
    /// ``isDeployed(inLibraryFolder:)`` only looks for the files Apple's layout
    /// puts in the tree, so a payload someone copied in by hand passes it too.
    /// The forwarders no interposer takes over are only ever written by a
    /// deploy, so they tell the two apart.
    static func isStorePayloadDeployed(inLibraryFolder folder: URL, usingStore store: URL) -> Bool {
        guard storedRecord(inStore: store) != nil else {
            return false
        }
        let peDir = folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows")
        let storeLib = store.appending(path: "lib")
        let interposed = Set(interposers.map(\.slotName))
        return forwarderDLLNames.filter { !interposed.contains($0) }.allSatisfy { name in
            isGPTKForwarder(peDir.appending(path: name), matching: storeLib)
        }
    }

    // MARK: - Launch

    /// Brings the video processor in line with the payload already deployed,
    /// and seeds every bottle's placeholder when it is in.
    ///
    /// This is the path for installs that were already set up before the
    /// interposer existed: they have the payload deployed and never run a deploy
    /// again, so without this they would keep rendering video through the
    /// engine's broken fallback until they happened to reimport. Idempotent and
    /// cheap enough to run at launch.
    ///
    /// Because it runs on every launch, it only changes what the importer owns:
    ///
    /// - A payload that was not deployed from the store is left alone. Whoever
    ///   copied Apple's files in by hand also decides what sits in the slots.
    /// - A payload from outside the line the interposers were validated on has
    ///   them taken back out, since a deploy from before that check put them in.
    /// - The swap only goes over the store's own `d3d12.dll`, which is what
    ///   deploy leaves behind. A slot holding anything else was changed on
    ///   purpose.
    public static func ensureVideoProcessorInstalled(bottles: [URL]) {
        ensureVideoProcessorInstalled(
            bottles: bottles, inLibraryFolder: WhiskyWineInstaller.libraryFolder, usingStore: storeFolder
        )
    }

    /// Testable seam for ``ensureVideoProcessorInstalled(bottles:)``.
    static func ensureVideoProcessorInstalled(bottles: [URL], inLibraryFolder folder: URL, usingStore store: URL) {
        guard isDeployed(inLibraryFolder: folder),
              isStorePayloadDeployed(inLibraryFolder: folder, usingStore: store)
        else {
            return
        }

        let version = deployedPayloadVersion(inLibraryFolder: folder)
        guard interposersSupport(payloadVersion: version) else {
            if interposers.contains(where: { isInstalled($0, inLibraryFolder: folder) }) {
                let payload = version ?? "an unreadable version"
                logger.info("Taking the interposers back out of GPTK \(payload, privacy: .public)")
            }
            removeVideoProcessor(fromLibraryFolder: folder, usingStore: store)
            return
        }

        let slot = folder.appending(path: "Wine").appending(path: "lib").appending(path: "wine")
            .appending(path: "x86_64-windows").appending(path: videoProcessorInterposer.slotName)
        let slotIsDeploys = isVideoProcessorInstalled(inLibraryFolder: folder)
            || isGPTKForwarder(slot, matching: store.appending(path: "lib"))
        guard hasVideoProcessor(inLibraryFolder: folder), slotIsDeploys else {
            return
        }

        do {
            try installVideoProcessor(intoLibraryFolder: folder)
        } catch {
            logger.error("Installing the D3D12 video processor failed: \(error.localizedDescription)")
            return
        }
        for bottle in bottles {
            seedVideoDevicePlaceholder(inBottle: bottle, fromLibraryFolder: folder)
        }
    }
}
