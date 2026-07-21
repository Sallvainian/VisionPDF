import Foundation

/// Interprets OCRmyPDF's stderr stream.
///
/// When stderr is a pipe (not a TTY), OCRmyPDF suppresses its rich progress
/// bars and emits only milestone log lines. Those milestones are mapped to
/// coarse stages here. No percentages are invented — the UI shows an
/// indeterminate per-file bar plus these stage labels, and reserves determinate
/// progress for the queue level (files completed / total), which is real.
///
/// Stage patterns are matched against output observed from OCRmyPDF 17.8.1:
///   "Starting processing with 3 workers concurrently"
///   "Parsing 3 pages with HocrParser"
///   "Postprocessing..."
///   "Auto mode: produced PDF/A via Ghostscript"
///   "Image optimization ratio: 1.00 savings: 0.0%"
///   "Output file is a PDF/A-2b (auto mode achieved PDF/A)"
enum ProgressParser {
    enum Event: Equatable, Sendable {
        case stage(String)
        case pageCount(Int)
        /// A line that looks like a problem worth surfacing.
        case warning(String)
    }

    static func parse(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("Scanning contents") {
            return .stage("Scanning contents")
        }
        if trimmed.contains("Starting processing with") {
            return .stage("Recognizing text")
        }
        if let count = parsePageCount(from: trimmed) {
            return .pageCount(count)
        }
        if trimmed.hasPrefix("Postprocessing") {
            return .stage("Postprocessing")
        }
        if trimmed.contains("PDF/A via Ghostscript") || trimmed.contains("Convert to PDF/A") {
            return .stage("Converting to PDF/A")
        }
        if trimmed.hasPrefix("Image optimization") || trimmed.hasPrefix("Optimize ") {
            return .stage("Optimizing")
        }
        if trimmed.hasPrefix("Total file size ratio") || trimmed.hasPrefix("Output file is a") {
            return .stage("Finishing")
        }
        if trimmed.hasPrefix("WARNING") || trimmed.contains("page already has text") {
            return .warning(trimmed)
        }
        return nil
    }

    /// Matches "Parsing 3 pages with HocrParser".
    private static func parsePageCount(from line: String) -> Int? {
        guard line.hasPrefix("Parsing "), line.contains(" pages with") else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let count = Int(parts[1]) else { return nil }
        return count
    }
}

/// Translates OCRmyPDF exit codes into human-readable failure messages.
/// The table mirrors `ocrmypdf.exceptions.ExitCode` in OCRmyPDF 17.8.1.
enum OCRExitCode {
    static func explanation(for code: Int32) -> String {
        switch code {
        case 0: "Completed successfully."
        case 1: "Invalid arguments were passed to OCRmyPDF (bad_args)."
        case 2: "The input file is unreadable, corrupt, or not a supported PDF (input_file)."
        case 3: "A required helper program is missing — for example unpaper for “Clean pages”, or Ghostscript (missing_dependency)."
        case 4: "OCRmyPDF produced an invalid output PDF (invalid_output_pdf)."
        case 5: "A file could not be read or written — check permissions (file_access_error)."
        case 6: "The PDF already contains text on every page, so nothing was OCRed. Use “Skip pages with text” or “Redo existing OCR” (already_done_ocr)."
        case 7: "A helper program crashed while processing this file (child_process_error)."
        case 8: "The PDF is encrypted. Remove the password first (encrypted_pdf)."
        case 9: "Invalid OCRmyPDF configuration (invalid_config)."
        case 10: "The PDF/A conversion failed (pdfa_conversion_failed)."
        case 15: "OCRmyPDF reported an unexpected error (other_error)."
        case 130: "The run was interrupted (ctrl_c)."
        default: "OCRmyPDF exited with unrecognized code \(code)."
        }
    }

    /// Short label used in the queue row.
    static func shortLabel(for code: Int32) -> String {
        switch code {
        case 2: "Unsupported or corrupt PDF"
        case 3: "Missing helper program"
        case 5: "File permission error"
        case 6: "Already has text"
        case 8: "Encrypted PDF"
        default: "Failed (exit code \(code))"
        }
    }
}
