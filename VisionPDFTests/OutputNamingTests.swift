import Foundation
import Testing
@testable import VisionPDF

@Suite("OutputNaming")
struct OutputNamingTests {
    // MARK: Suffix generation

    @Test("Default suffix: Document.pdf becomes Document OCR.pdf beside the original")
    func defaultSuffix() {
        let input = URL(fileURLWithPath: "/scans/Document.pdf")
        let output = OutputNaming.outputURL(for: input, mode: .besideOriginal, folder: nil, suffix: "OCR")
        #expect(output.path == "/scans/Document OCR.pdf")
    }

    @Test("Selected folder mode writes into the chosen folder")
    func selectedFolder() {
        let input = URL(fileURLWithPath: "/scans/Document.pdf")
        let folder = URL(fileURLWithPath: "/output", isDirectory: true)
        let output = OutputNaming.outputURL(for: input, mode: .selectedFolder, folder: folder, suffix: "OCR")
        #expect(output.path == "/output/Document OCR.pdf")
    }

    @Test("Selected folder mode without a folder falls back beside the original")
    func selectedFolderMissing() {
        let input = URL(fileURLWithPath: "/scans/Document.pdf")
        let output = OutputNaming.outputURL(for: input, mode: .selectedFolder, folder: nil, suffix: "OCR")
        #expect(output.path == "/scans/Document OCR.pdf")
    }

    @Test(
        "Names with spaces, parentheses, brackets, and apostrophes keep them",
        arguments: [
            ("/a/My Report (final).pdf", "/a/My Report (final) OCR.pdf"),
            ("/a/scan [v2].pdf", "/a/scan [v2] OCR.pdf"),
            ("/a/it's here.pdf", "/a/it's here OCR.pdf"),
            ("/a/Ünïcode – dash.pdf", "/a/Ünïcode – dash OCR.pdf"),
        ]
    )
    func specialCharacterNames(_ input: String, _ expected: String) {
        let output = OutputNaming.outputURL(
            for: URL(fileURLWithPath: input),
            mode: .besideOriginal,
            folder: nil,
            suffix: "OCR"
        )
        #expect(output.path == expected)
    }

    @Test("Empty suffix keeps the original name")
    func emptySuffix() {
        let input = URL(fileURLWithPath: "/scans/Document.pdf")
        let output = OutputNaming.outputURL(for: input, mode: .besideOriginal, folder: nil, suffix: "")
        #expect(output.path == "/scans/Document.pdf")
    }

    @Test("Suffix is sanitized: path separators are stripped")
    func suffixSanitized() {
        #expect(OutputNaming.sanitizedSuffix("O/C:R\\x") == "OCRx")
        #expect(OutputNaming.sanitizedSuffix("  OCR  ") == "OCR")
    }

    // MARK: Duplicate handling within a batch

    @Test("Two inputs mapping to one output get numbered")
    func uniquify() {
        let first = URL(fileURLWithPath: "/out/Report OCR.pdf")
        var taken = Set<String>()

        let a = OutputNaming.uniquifiedURL(first, taken: taken)
        #expect(a.path == "/out/Report OCR.pdf")
        taken.insert(a.standardizedFileURL.path)

        let b = OutputNaming.uniquifiedURL(first, taken: taken)
        #expect(b.path == "/out/Report OCR 2.pdf")
        taken.insert(b.standardizedFileURL.path)

        let c = OutputNaming.uniquifiedURL(first, taken: taken)
        #expect(c.path == "/out/Report OCR 3.pdf")
    }

    // MARK: Validation

    private let existingInput = "/in/present.pdf"

    private func validate(
        input: String = "/in/present.pdf",
        output: String = "/out/present OCR.pdf",
        allowOverwrite: Bool = false,
        existingFiles: Set<String> = ["/in/present.pdf"],
        directories: Set<String> = ["/in", "/out"],
        writableDirectories: Set<String> = ["/in", "/out"]
    ) throws(OutputNaming.ValidationError) {
        try OutputNaming.validate(
            input: URL(fileURLWithPath: input),
            output: URL(fileURLWithPath: output),
            allowOverwrite: allowOverwrite,
            fileExists: { existingFiles.contains($0) },
            directoryExists: { directories.contains($0) },
            isWritableDirectory: { writableDirectories.contains($0) }
        )
    }

    @Test("Valid input and output pass")
    func validPasses() throws {
        try validate()
    }

    @Test("Missing input file is rejected")
    func missingInput() {
        #expect(throws: OutputNaming.ValidationError.inputMissing("/in/gone.pdf")) {
            try self.validate(input: "/in/gone.pdf", existingFiles: [])
        }
    }

    @Test("Missing output folder is rejected")
    func missingOutputFolder() {
        #expect(throws: OutputNaming.ValidationError.outputFolderMissing("/nowhere")) {
            try self.validate(output: "/nowhere/x OCR.pdf")
        }
    }

    @Test("Non-writable output folder is rejected")
    func nonWritableFolder() {
        #expect(throws: OutputNaming.ValidationError.outputFolderNotWritable("/out")) {
            try self.validate(writableDirectories: ["/in"])
        }
    }

    @Test("Output identical to input is rejected")
    func outputEqualsInput() {
        #expect(throws: OutputNaming.ValidationError.outputSameAsInput("/in/present.pdf")) {
            try self.validate(output: "/in/present.pdf", directories: ["/in"], writableDirectories: ["/in"])
        }
    }

    @Test("Case-only difference counts as the same file (APFS default volumes)")
    func outputEqualsInputCaseInsensitive() {
        // "Scan.PDF" with an empty suffix maps to "Scan.pdf" — the same file
        // on a case-insensitive volume.
        #expect(throws: OutputNaming.ValidationError.outputSameAsInput("/in/Scan.PDF")) {
            try self.validate(
                input: "/in/Scan.PDF",
                output: "/in/Scan.pdf",
                existingFiles: ["/in/Scan.PDF"],
                directories: ["/in"],
                writableDirectories: ["/in"]
            )
        }
    }

    @Test("Existing output without overwrite permission is rejected")
    func existingOutputBlocked() {
        #expect(throws: OutputNaming.ValidationError.outputExists("/out/present OCR.pdf")) {
            try self.validate(existingFiles: ["/in/present.pdf", "/out/present OCR.pdf"])
        }
    }

    @Test("Existing output with overwrite enabled passes")
    func existingOutputAllowed() throws {
        try validate(
            allowOverwrite: true,
            existingFiles: ["/in/present.pdf", "/out/present OCR.pdf"]
        )
    }

    @Test("Real non-writable folder is caught end to end")
    func realNonWritableFolder() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("VisionPDFTests-\(UUID().uuidString)")
        let lockedDir = base.appendingPathComponent("locked")
        try fileManager.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        let input = base.appendingPathComponent("in.pdf")
        try Data("x".utf8).write(to: input)
        defer { try? fileManager.removeItem(at: base) }

        // Remove write permission.
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
        }

        #expect(throws: OutputNaming.ValidationError.self) {
            try OutputNaming.validate(
                input: input,
                output: lockedDir.appendingPathComponent("in OCR.pdf"),
                allowOverwrite: false
            )
        }
    }
}
