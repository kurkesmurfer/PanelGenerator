import Foundation
import CoreGraphics
import AppKit

// MARK: - Tolerant decoding
//
// Swift's synthesised Codable does NOT fall back to a property's default value
// when a key is missing — it throws .keyNotFound. So every field added to a
// model after documents have been saved makes those documents unopenable
// (`segments` and `layout` did exactly that to every panel saved before the
// button-group commit). Decoding through `decodeOr` keeps old files readable.
//
// These inits live in extensions on purpose: declaring an init inside a struct
// body suppresses its memberwise initialiser, which the rest of the code uses.
//
// When adding a stored property to any of these types, add a matching line to
// its init(from:) below — encoding is still synthesised and will write the new
// key, so a field decoded nowhere would silently reset on every round-trip.

extension KeyedDecodingContainer {
    /// Missing key → `fallback`. A key that is present but malformed still
    /// throws: that is a corrupt file, not an old one, and should be reported.
    package func decodeOr<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

// Each init below starts from the type's own defaults and then overlays what
// the file actually contains. The fallback is therefore the declared default
// itself — it cannot drift out of sync with the property declaration.
