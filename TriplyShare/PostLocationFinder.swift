import Foundation
import LinkPresentation
import MapKit

/// Looks through a shared post for where it is: an address, or a "📍 Place" line in the caption.
enum PostLocationFinder {

    /// The post's text. Instagram usually shares only the link, so the caption comes from the
    /// link preview (the same title Messages shows for the link), plus any text that was shared with it.
    static func postText(url: URL?, sharedText: String) async -> String {
        var parts = [sharedText]
        if let url, let title = await previewTitle(for: url) { parts.append(title) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Bits of text that look like a location, best first (at most 3).
    static func candidates(in text: String) -> [String] {
        var found: [String] = []

        // 1. Lines marked with a pin, e.g. "📍 Ichiran Shibuya" or "📍: 1-22-7 Jinnan, Shibuya".
        for line in text.components(separatedBy: .newlines) {
            for marker in ["📍", "📌", "Location:", "Address:", "Add:"] {
                guard let range = line.range(of: marker, options: .caseInsensitive) else { continue }
                let rest = line[range.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :：-–@\t\"“”"))
                if rest.count >= 3 { found.append(String(rest.prefix(120))) }
                break
            }
        }

        // 2. Street addresses Apple's data detector recognises.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let r = Range(match.range, in: text) {
                    found.append(text[r].replacingOccurrences(of: "\n", with: ", "))
                }
            }
        }

        // 3. Phrases with street words or a postcode the detector misses
        //    (e.g. "at 21 Jalan Telawi 3, Bangsar, 59100 Kuala Lumpur").
        let streetWords = #"(?i)\b(jalan|jln|lorong|lebuh|persiaran|lebuhraya|street|st\.|road|rd\.?|avenue|ave|lane|soi|thanon|chome|dori|gil|ro)\b|丁目|\b\d{5}\b"#
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: "\n•|—–!?。"))
        for clause in clauses where clause.range(of: streetWords, options: .regularExpression) != nil {
            var piece = clause
            // "Cafe hopping at 21 Jalan…" → "21 Jalan…"
            if let at = piece.range(of: " at ", options: [.caseInsensitive, .backwards]) {
                piece = String(piece[at.upperBound...])
            }
            piece = piece.trimmingCharacters(in: CharacterSet(charactersIn: " :：-@\t\"“”.,"))
            if (6...120).contains(piece.count) { found.append(piece) }
        }

        // Keep the first of each, ignoring case and spacing.
        var seen = Set<String>()
        return found.filter { seen.insert($0.lowercased().filter { !$0.isWhitespace }).inserted }
            .prefix(3)
            .map { $0 }
    }

    /// Apple Maps places for the candidates (first match of each), near `region` when given.
    static func places(for candidates: [String], near region: MKCoordinateRegion?) async -> [MKMapItem] {
        var items: [MKMapItem] = []
        for text in candidates {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            if let region { request.region = region }
            if let item = try? await MKLocalSearch(request: request).start().mapItems.first,
               !items.contains(where: { $0.placemark.coordinate.latitude == item.placemark.coordinate.latitude
                                        && $0.placemark.coordinate.longitude == item.placemark.coordinate.longitude }) {
                items.append(item)
            }
        }
        return items
    }

    /// The link preview's title (for Instagram this usually holds the caption). Gives up after a few seconds.
    private static func previewTitle(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 6
        provider.shouldFetchSubresources = false
        return try? await provider.startFetchingMetadata(for: url).title
    }
}
