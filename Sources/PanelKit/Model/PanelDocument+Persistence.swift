import Foundation
import CoreGraphics
import AppKit

// Reading and writing .panelgen files.

extension PanelDocument {

    // MARK Persistence

    package static let fileExtension = "panelgen"

    package func save(to url: URL) throws {
        // Stamp on write: a document loaded from a pre-versioning file decodes
        // as 0, and without this it would carry that 0 for the rest of its life.
        var out = self
        out.schemaVersion = Self.currentSchemaVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(out).write(to: url, options: [.atomic])
    }

    package static func load(from url: URL) throws -> PanelDocument {
        try JSONDecoder().decode(PanelDocument.self, from: Data(contentsOf: url))
    }
}
