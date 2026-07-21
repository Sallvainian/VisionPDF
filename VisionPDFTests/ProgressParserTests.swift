import Foundation
import Testing
@testable import VisionPDF

@Suite("ProgressParser")
struct ProgressParserTests {
    // Lines below are verbatim from OCRmyPDF 17.8.1 runs with piped stderr.

    @Test("Observed stage lines map to stages")
    func stages() {
        #expect(
            ProgressParser.parse(line: "Starting processing with 3 workers concurrently")
                == .stage("Recognizing text")
        )
        #expect(ProgressParser.parse(line: "Postprocessing...") == .stage("Postprocessing"))
        #expect(
            ProgressParser.parse(line: "Auto mode: produced PDF/A via Ghostscript")
                == .stage("Converting to PDF/A")
        )
        #expect(
            ProgressParser.parse(line: "Image optimization ratio: 1.00 savings: 0.0%")
                == .stage("Optimizing")
        )
        #expect(
            ProgressParser.parse(line: "Total file size ratio: 0.92 savings: -9.0%")
                == .stage("Finishing")
        )
        #expect(
            ProgressParser.parse(line: "Output file is a PDF/A-2b (auto mode achieved PDF/A)")
                == .stage("Finishing")
        )
    }

    @Test("Page count is read from the HocrParser line")
    func pageCount() {
        #expect(
            ProgressParser.parse(line: "Parsing 3 pages with HocrParser") == .pageCount(3)
        )
        #expect(
            ProgressParser.parse(line: "Parsing 128 pages with HocrParser") == .pageCount(128)
        )
    }

    @Test("Unremarkable lines produce no event")
    func noise() {
        #expect(ProgressParser.parse(line: "") == nil)
        #expect(ProgressParser.parse(line: "pikepdf mmap enabled") == nil)
        #expect(ProgressParser.parse(line: "   1 convert done") == nil)
    }

    @Test("Prior-text warnings are surfaced")
    func warnings() {
        #expect(
            ProgressParser.parse(line: "    1 page already has text! - aborting")
                == .warning("1 page already has text! - aborting")
        )
    }

    @Test("Exit codes map to the OCRmyPDF 17.8.1 ExitCode table")
    func exitCodes() {
        #expect(OCRExitCode.explanation(for: 0).contains("success"))
        #expect(OCRExitCode.explanation(for: 2).contains("input"))
        #expect(OCRExitCode.explanation(for: 3).contains("helper"))
        #expect(OCRExitCode.explanation(for: 6).contains("already contains text"))
        #expect(OCRExitCode.explanation(for: 8).contains("encrypted"))
        #expect(OCRExitCode.explanation(for: 130).contains("interrupted"))
        #expect(OCRExitCode.explanation(for: 99).contains("99"))
    }
}
