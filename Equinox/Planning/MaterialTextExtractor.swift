import Foundation
import PDFKit

/// Extracts a trimmed text summary from an attached material so the
/// on-device planner can read the actual content (PDFs via PDFKit).
enum MaterialTextExtractor {
    static let maxCharacters = 4000

    static func summary(from url: URL) -> String? {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch url.pathExtension.lowercased() {
        case "pdf":
            return pdfText(url)
        case "txt", "md":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            return trim(text)
        default:
            return nil
        }
    }

    private static func pdfText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else {
            return nil
        }

        var text = ""
        // First pages carry the outline/syllabus signal; cap the work.
        let pageLimit = min(document.pageCount, 15)
        for index in 0..<pageLimit {
            guard let page = document.page(at: index), let content = page.string else {
                continue
            }
            text += content + "\n"
            if text.count > maxCharacters {
                break
            }
        }
        return text.isEmpty ? nil : trim(text)
    }

    private static func trim(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s{3,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(maxCharacters))
    }
}
