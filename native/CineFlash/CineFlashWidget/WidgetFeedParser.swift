import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct WidgetNewsItem: Identifiable {
    var id: String
    var title: String
    var source: String
}

/// Parser RSS/Atom con limiti applicati prima e durante la lettura.
final class WidgetFeedParser: NSObject, XMLParserDelegate {
    static let maxFeedBytes = 1_048_576
    private var items: [WidgetNewsItem] = []
    private let source: String
    private var depth = 0
    private var itemDepth: Int?
    private var fields: [String: String] = [:]
    private var field: String?
    private var text = ""
    private var href: String?
    private var itemCount = 0
    private var reachedLimit = false

    private init(source: String) { self.source = source }

    static func parse(_ data: Data, source: String) -> [WidgetNewsItem] {
        // Mantiene il formato UTF-8 già richiesto dal widget. Niente DTD/entities
        // personalizzate; NUL esclude UTF-16/32 prima del controllo del DOCTYPE.
        guard data.count <= maxFeedBytes,
              let xml = String(data: data, encoding: .utf8),
              !xml.utf8.contains(0), !xml.contains("<!DOCTYPE") else { return [] }
        let delegate = WidgetFeedParser(source: source)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        let success = parser.parse()
        let complete = success && parser.parserError == nil && delegate.depth == 0
        return complete || delegate.reachedLimit ? delegate.items : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        depth += 1
        guard depth <= 64 else { parser.abortParsing(); return }
        let name = elementName.lowercased()
        if itemDepth == nil, name == "item" || name == "entry" {
            itemDepth = depth
            fields = [:]
            href = nil
        } else if let itemDepth, depth == itemDepth + 1 {
            if name == "link", href == nil { href = attributeDict["href"] }
            if ["title", "link", "guid"].contains(name), fields[name] == nil {
                field = name
                text = ""
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text.append(string) }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if field != nil, let string = String(data: CDATABlock, encoding: .utf8) {
            text.append(string)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        defer { depth -= 1 }
        guard let itemDepth else { return }
        if depth == itemDepth + 1, let field {
            fields[field] = Self.cleanText(text)
            self.field = nil
            text = ""
        }
        if depth == itemDepth {
            if let title = fields["title"], !title.isEmpty {
                let link = [fields["link"], href, fields["guid"]]
                    .compactMap { $0 }.first { !$0.isEmpty } ?? title
                items.append(WidgetNewsItem(id: Self.hashId(link), title: title, source: source))
            }
            self.itemDepth = nil
            itemCount += 1
            if itemCount == 10 {
                reachedLimit = true
                parser.abortParsing()
            }
        }
    }

    /// Rimuove markup dei titoli CDATA con una sola scansione, senza regex.
    private static func cleanText(_ text: String) -> String {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        var result = ""
        var inTag = false
        for scalar in decoded.unicodeScalars {
            if scalar == "<" { inTag = true }
            else if scalar == ">", inTag { inTag = false }
            else if !inTag { result.unicodeScalars.append(scalar) }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hashId(_ s: String) -> String {
        var h: Int = 5381
        for ch in s.unicodeScalars { h = ((h << 5) &+ h &+ Int(ch.value)) & 0x7FFFFFFF }
        return String(h, radix: 36)
    }
}
