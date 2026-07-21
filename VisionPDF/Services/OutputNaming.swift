import Foundation

/// Computes output file locations and guards against overwrites.
enum OutputNaming {
    /// Builds the output URL for an input PDF: `Document.pdf` with suffix "OCR"
    /// becomes `Document OCR.pdf`, either beside the original or in the chosen
    /// folder. An empty suffix keeps the original name (which is then caught by
    /// `validate` when it would collide with the input).
    static func outputURL(
        for input: URL,
        mode: OutputMode,
        folder: URL?,
        suffix: String
    ) -> URL {
        let directory: URL
        switch mode {
        case .besideOriginal:
            directory = input.deletingLastPathComponent()
        case .selectedFolder:
            directory = folder ?? input.deletingLastPathComponent()
        }
        let base = input.deletingPathExtension().lastPathComponent
        let cleanSuffix = sanitizedSuffix(suffix)
        let name = cleanSuffix.isEmpty ? base : "\(base) \(cleanSuffix)"
        return directory
            .appendingPathComponent(name)
            .appendingPathExtension("pdf")
    }

    /// Strips path separators and other characters that are unsafe in a file
    /// name component.
    static func sanitizedSuffix(_ suffix: String) -> String {
        suffix
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves collisions within one batch: when two queued inputs map to the
    /// same output (for example `/a/Report.pdf` and `/b/Report.pdf` into one
    /// folder), later ones get ` 2`, ` 3`, … appended. `taken` holds the
    /// standardized paths already claimed by earlier queue items.
    static func uniquifiedURL(_ proposed: URL, taken: Set<String>) -> URL {
        let key = proposed.standardizedFileURL.path
        guard taken.contains(key) else { return proposed }
        let directory = proposed.deletingLastPathComponent()
        let base = proposed.deletingPathExtension().lastPathComponent
        for counter in 2...10_000 {
            let candidate = directory
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension("pdf")
            if !taken.contains(candidate.standardizedFileURL.path) {
                return candidate
            }
        }
        return proposed
    }

    enum ValidationError: LocalizedError, Equatable {
        case inputMissing(String)
        case outputFolderMissing(String)
        case outputFolderNotWritable(String)
        case outputSameAsInput(String)
        case outputExists(String)

        var errorDescription: String? {
            switch self {
            case .inputMissing(let path):
                "The input file no longer exists: \(path)"
            case .outputFolderMissing(let path):
                "The output folder does not exist: \(path)"
            case .outputFolderNotWritable(let path):
                "You don't have permission to write into: \(path)"
            case .outputSameAsInput(let path):
                "The output would overwrite the input file itself (\(path)). Choose a different folder or a non-empty suffix."
            case .outputExists(let path):
                "The output file already exists: \(path). Enable “Allow overwriting” to replace it."
            }
        }
    }

    /// Pre-flight checks for one input/output pair. `fileExists`,
    /// `directoryExists`, and `isWritableDirectory` are injectable for tests.
    static func validate(
        input: URL,
        output: URL,
        allowOverwrite: Bool,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        directoryExists: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        },
        isWritableDirectory: (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }
    ) throws(ValidationError) {
        let inputPath = input.standardizedFileURL.path
        let outputPath = output.standardizedFileURL.path
        let outputDir = output.deletingLastPathComponent().standardizedFileURL.path

        guard fileExists(inputPath) else {
            throw .inputMissing(inputPath)
        }
        guard directoryExists(outputDir) else {
            throw .outputFolderMissing(outputDir)
        }
        guard isWritableDirectory(outputDir) else {
            throw .outputFolderNotWritable(outputDir)
        }
        // Case-insensitive: the default APFS volume treats "Scan.PDF" and
        // "Scan.pdf" as the same file, and the output extension is always
        // lowercase — an exact-string compare would let OCRmyPDF overwrite
        // the original in place.
        guard inputPath.compare(outputPath, options: .caseInsensitive) != .orderedSame else {
            throw .outputSameAsInput(inputPath)
        }
        if !allowOverwrite, fileExists(outputPath) {
            throw .outputExists(outputPath)
        }
    }
}
