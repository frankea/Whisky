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
/// against GPTK 4.0 beta 2 (frankea/Whisky#163), and that does not carry over
/// to other payloads: with GPTK 3.0 the DXGI interposer's `VirtualProtect` on
/// the adapter vtable fails with error 87 and the driver version is never
/// answered, and Red Dead Redemption 2 crashes at startup with the D3D12 one in
/// the slot (frankea/Whisky#276).
extension GPTKImporter {
    /// The D3DMetal builds the interposers were validated on, as Apple's
    /// `CFBundleShortVersionString` spells them.
    static let interposerPayloadVersions: Set<String> = ["4.0b2"]

    /// Whether the interposers may go in front of a payload of `version`.
    ///
    /// An exact list rather than a version range. Both interposers sit in slots
    /// every game on D3DMetal loads through, so a build they do not fit takes
    /// all of them down, while a build that goes without only loses the two
    /// fixes. A later build, 4.x included, gets them once someone has measured
    /// them there. A version that cannot be read fails closed.
    static func interposersSupport(payloadVersion version: String?) -> Bool {
        guard let version else {
            return false
        }
        return interposerPayloadVersions.contains(version)
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
    /// deploy, so they tell the two apart. A hand copy that is byte-identical
    /// to the store's counts as the store's, which is harmless: it is the same
    /// payload.
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

    /// Whether `folder`'s runtime holds a payload `store` did not deploy: one
    /// copied in by hand. Nothing the app runs on its own installs into it or
    /// deploys over it; importing a payload is what replaces it.
    static func holdsHandPlacedPayload(inLibraryFolder folder: URL, usingStore store: URL) -> Bool {
        isDeployed(inLibraryFolder: folder) && !isStorePayloadDeployed(inLibraryFolder: folder, usingStore: store)
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
    /// Because it runs on every launch, it only changes what the importer owns,
    /// plus what an earlier version of it did to trees it did not own:
    ///
    /// - A payload from outside the builds the interposers were validated on
    ///   has them taken back out, whoever set it up. Earlier versions put the
    ///   D3D12 one in at every launch over any payload holding Apple's files,
    ///   and deploys put both in over any payload.
    /// - Otherwise, a payload that was not deployed from the store is left
    ///   alone. Whoever copied Apple's files in by hand decides what sits in
    ///   the slots.
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
        guard isDeployed(inLibraryFolder: folder) else {
            return
        }
        let storeDeployed = isStorePayloadDeployed(inLibraryFolder: folder, usingStore: store)

        guard interposersSupport(payloadVersion: deployedPayloadVersion(inLibraryFolder: folder)) else {
            let storeLib = storeDeployed ? store.appending(path: "lib") : nil
            for interposer in interposers {
                takeBack(interposer, fromLibraryFolder: folder, storeLib: storeLib)
            }
            return
        }
        guard storeDeployed else {
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

    // MARK: - Taking an interposer back out

    /// Takes `interposer` back out of a payload it was not validated on and
    /// puts Apple's DLL back into the slot.
    ///
    /// Apple's DLL comes back from the renamed copy install left beside the
    /// slot, with its export name patched back. Install changed nothing else,
    /// so that is exactly the file it moved aside, and it needs no store: a
    /// payload copied in by hand has none. For a payload the store deployed,
    /// `storeLib` is the store's `lib`, whose copy comes first because it is
    /// what deploy put in the slot.
    ///
    /// A slot that went missing, which an interrupted restore could leave
    /// behind, is put back the same way. The renamed files only go once the
    /// slot holds Apple's DLL, restored or already there: a slot holding
    /// anything else may be forwarding to them.
    static func takeBack(_ interposer: GPTKInterposer, fromLibraryFolder folder: URL, storeLib: URL?) {
        let fileManager = FileManager.default
        let wineLib = folder.appending(path: "Wine").appending(path: "lib")
        let peDir = wineLib.appending(path: "wine").appending(path: "x86_64-windows")
        let slot = peDir.appending(path: interposer.slotName)
        let candidates = applesDLLCandidates(for: interposer, inPEDir: peDir, storeLib: storeLib)

        let shimInSlot = isInstalled(interposer, inLibraryFolder: folder)
        if shimInSlot || !fileManager.fileExists(atPath: slot.path(percentEncoded: false)) {
            let restoring = "Apple's \(interposer.slotName) for the \(interposer.label) interposer"
            guard let original = candidates.first else {
                if shimInSlot {
                    logger.error("No copy of \(restoring, privacy: .public) to put back")
                }
                return
            }
            do {
                try replaceSlot(slot, with: original)
            } catch {
                logger.error("Putting back \(restoring, privacy: .public) failed: \(error.localizedDescription)")
                return
            }
            logger.info("Put back \(restoring, privacy: .public)")
        } else {
            guard let current = try? Data(contentsOf: slot), candidates.contains(current) else {
                return
            }
        }

        try? fileManager.removeItem(at: peDir.appending(path: interposer.renamedName))
        try? fileManager.removeItem(
            at: wineLib.appending(path: "wine").appending(path: "x86_64-unix")
                .appending(path: interposer.renamedUnixName)
        )
    }

    /// The files that are Apple's DLL for `interposer`'s slot, most trusted
    /// first: the store's copy when there is a store to trust, then the renamed
    /// copy beside the slot with its export name patched back. The renamed copy
    /// only counts while it still carries the name install gave it.
    private static func applesDLLCandidates(
        for interposer: GPTKInterposer, inPEDir peDir: URL, storeLib: URL?
    ) -> [Data] {
        var candidates: [Data] = []
        if let storeLib {
            let pristine = storeLib.appending(path: "wine").appending(path: "x86_64-windows")
                .appending(path: interposer.slotName)
            if let data = try? Data(contentsOf: pristine) {
                candidates.append(data)
            }
        }
        if let renamed = try? Data(contentsOf: peDir.appending(path: interposer.renamedName)),
           let original = try? renamingExport(in: renamed, from: interposer.renamedName, to: interposer.slotName) {
            candidates.append(original)
        }
        return candidates
    }
}
