import SwiftUI
import UniformTypeIdentifiers

/// A minimal plain-text FileDocument. This is what makes the app a real
/// document-based SwiftUI app — DocumentGroup gives us native window tabs,
/// Save/Open, Versions, and restoration for free.
struct TextDocument: FileDocument {
    // Plain text + source code + markdown, so the app can open its own .swift
    // files and the .md skill doc as tabs.
    static var readableContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .sourceCode]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String = "# New Document\n\nStart typing…\n") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
