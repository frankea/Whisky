//
//  GPTKImporter+Authenticity.swift
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
import Security

/// An Apple-built code object in a payload's `external/` folder.
struct GPTKAppleCode: Sendable {
    /// Its name in `external/`.
    let name: String
    /// The identifier Apple signs it as.
    let identifier: String
}

/// The checks on the Mach-O half of a payload: the shared library and the
/// D3DMetal framework, which every process in a bottle loads once the payload
/// is deployed.
extension GPTKImporter {
    /// The payload's Apple-built code, in the order it is checked.
    ///
    /// Apple gives each a designated requirement of `identifier "<id>" and
    /// anchor apple`, with the same identifiers on GPTK 2.0 and 4.0b2. The
    /// unix bridge entries are symlinks to the shared library, so checking it
    /// covers them.
    static let appleSignedCode = [
        GPTKAppleCode(name: "libd3dshared.dylib", identifier: "com.apple.libd3dshared"),
        GPTKAppleCode(name: "D3DMetal.framework", identifier: "com.apple.D3DMetal")
    ]

    /// Whether the code object at `url` (a Mach-O file or a bundle) carries a
    /// valid Apple signature for `identifier`.
    ///
    /// The code must satisfy `identifier "<identifier>" and anchor apple`, the
    /// designated requirement Apple gives the payload's binaries: a signing
    /// chain that ends at Apple's root, for that identifier. Every
    /// architecture in a universal file must pass, not only the host's. In a
    /// bundle, every file the seal lists must be present and unchanged, and a
    /// file added inside the sealed version fails unless the seal's rules omit
    /// its name (`.DS_Store`, for one). A bundle's main executable and its
    /// `_CodeSignature` folder are read through a link without complaint, and
    /// what lies around the sealed version is not looked at;
    /// ``unsealedItem(inExternal:)`` covers both. A path that is not a code
    /// object fails.
    ///
    /// Strict validation is not requested, because it refuses a genuine
    /// framework when Finder has left a `.DS_Store` in its `_CodeSignature`
    /// folder. The rules it adds that bear on what the loader picks up are
    /// enforced by ``unsealedItem(inExternal:)`` instead, more tightly:
    /// Apple's layout around the sealed version, and only regular files and
    /// real folders inside it, which refuses the linked main executable this
    /// check follows. Among the rest is a check for bytes appended after the
    /// signed image, which the loader never maps.
    public static func isAppleSigned(_ url: URL, identifier: String) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return false }

        // Pinned to the identifier, not just the anchor, so no other
        // Apple-signed binary can fill the slot.
        var requirement: SecRequirement?
        let requirementText = "identifier \"\(identifier)\" and anchor apple"
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }

        // Every slice, not only the host's: the payload is x86_64 and runs
        // under Rosetta, so on Apple silicon the default check would only look
        // at a slice Wine never loads.
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures))
        let status = SecStaticCodeCheckValidity(staticCode, flags, requirement)
        if status != errSecSuccess {
            let name = url.lastPathComponent
            logger.info("Apple signature check failed for \(name, privacy: .public): \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    /// The first item under `external/` that Apple's signatures do not cover,
    /// as a payload-relative path, or `nil` when everything there is Apple's
    /// layout.
    ///
    /// The framework's signature seals `Versions/A` and nothing around it,
    /// and the signature check does not look around it either: a folder added
    /// beside `A` passes even `codesign --verify --strict --deep`. The loader
    /// does look there. D3DMetal's rpaths put `@loader_path/../Resources`
    /// ahead of `@loader_path/Resources`. Opened through the framework's
    /// top-level link, its loader path resolves to `Versions/A`, so a
    /// `Versions/Resources` folder wins over the sealed `Versions/A/Resources`;
    /// were the loader path the framework root, the first of those would be
    /// `external/Resources`. Everything around the sealed version therefore
    /// has to be exactly Apple's layout, and nothing inside it may lead
    /// elsewhere:
    ///
    /// - `external/` is a real folder holding the shared library as a regular
    ///   file and the framework as a real folder. A symlink in any of those
    ///   places would be copied as a link and leave the deployed tree
    ///   pointing outside it.
    /// - The framework root holds `Versions` and symlinks to their namesakes
    ///   in the current version (`D3DMetal` and `Resources`; GPTK 2.0 adds a
    ///   `Headers` link with nothing behind it). This is the rule codesign's
    ///   strict mode applies to a framework root.
    /// - `Versions` holds `A` and the `Current` link to it. Strict mode
    ///   accepts any number of version folders, which is how a
    ///   `Versions/Resources` folder gets past it.
    /// - `Versions/A` holds only regular files and real folders, all the way
    ///   down. The seal refuses a link in place of a sealed resource, but the
    ///   signature check follows a linked main executable. So does the
    ///   loader, which then resolves D3DMetal's `@loader_path` rpaths beside
    ///   wherever the link leads rather than in the payload. A linked
    ///   `_CodeSignature` gets past even strict mode.
    ///
    /// Finder's `.DS_Store` is allowed at each level: nothing loads it, and
    /// strict mode allows it in the framework root and in `Versions` too.
    static func unsealedItem(inExternal external: URL) -> String? {
        let framework = external.appending(path: "D3DMetal.framework")
        let versions = framework.appending(path: "Versions")
        let sealed = versions.appending(path: "A")
        let attributes = try? FileManager.default.attributesOfItem(atPath: external.path(percentEncoded: false))
        guard attributes?[.type] as? FileAttributeType == .typeDirectory else {
            return "external"
        }
        return firstUnexpectedItem(in: external, at: "external") { name, type, _ in
            switch name {
            case "libd3dshared.dylib": type == .typeRegular
            case "D3DMetal.framework": type == .typeDirectory
            default: false
            }
        } ?? firstUnexpectedItem(in: framework, at: "external/D3DMetal.framework") { name, type, link in
            if name == "Versions" {
                return type == .typeDirectory
            }
            return link == "Versions/Current/\(name)" || link == "Versions/A/\(name)"
        } ?? firstUnexpectedItem(in: versions, at: "external/D3DMetal.framework/Versions") { name, type, link in
            switch name {
            case "A": type == .typeDirectory
            case "Current": link == "A"
            default: false
            }
        } ?? firstLinkOrSpecialFile(under: sealed, at: "external/D3DMetal.framework/Versions/A")
    }

    /// The first item in `folder` or anywhere below it that is neither a
    /// regular file nor a real folder, such as a symlink, as `path/...`. A
    /// folder's entries are checked in name order before any folder among
    /// them is entered, and a folder that cannot be listed yields its path.
    private static func firstLinkOrSpecialFile(under folder: URL, at path: String) -> String? {
        var subfolders: [String] = []
        let item = firstUnexpectedItem(in: folder, at: path) { name, type, _ in
            if type == .typeDirectory {
                subfolders.append(name)
            }
            return type == .typeRegular || type == .typeDirectory
        }
        return item ?? subfolders.lazy.compactMap { name in
            firstLinkOrSpecialFile(under: folder.appending(path: name), at: "\(path)/\(name)")
        }.first
    }

    /// The first entry of `folder`, in name order, that `isExpected` refuses,
    /// as `path/name`. A folder that cannot be listed yields `path` itself,
    /// since what it holds is unknown.
    ///
    /// `isExpected` gets each entry's name, its type (a symlink reports as a
    /// symlink, not as what it points to) and, for a symlink, its destination.
    /// Finder's `.DS_Store` always passes.
    private static func firstUnexpectedItem(
        in folder: URL,
        at path: String,
        isExpected: (_ name: String, _ type: FileAttributeType?, _ link: String?) -> Bool
    ) -> String? {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
            return path
        }
        for name in names.sorted() {
            let item = folder.appending(path: name).path(percentEncoded: false)
            let type = (try? fileManager.attributesOfItem(atPath: item))?[.type] as? FileAttributeType
            if name == ".DS_Store", type == .typeRegular {
                continue
            }
            let link = type == .typeSymbolicLink ? try? fileManager.destinationOfSymbolicLink(atPath: item) : nil
            if !isExpected(name, type, link) {
                return "\(path)/\(name)"
            }
        }
        return nil
    }
}
