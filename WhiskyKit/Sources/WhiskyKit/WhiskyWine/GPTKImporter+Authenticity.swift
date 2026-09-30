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

/// The signature check on the Mach-O half of a payload: the shared library
/// and the D3DMetal framework, which every process in a bottle loads once
/// the payload is deployed.
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
    /// valid signature that chains to Apple's root certificate.
    ///
    /// This is `codesign --verify -R="anchor apple"`: the static code must be
    /// well-formed, every sealed resource must match, and the signing chain
    /// must end at Apple. Anything unsigned, ad-hoc signed, or signed by a
    /// third party fails, as does a path that is not a code object at all.
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
}
