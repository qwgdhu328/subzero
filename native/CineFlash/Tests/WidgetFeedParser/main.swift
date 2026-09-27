// Run from the repository root (macOS or Linux with Swift):
// swiftc native/CineFlash/CineFlashWidget/WidgetFeedParser.swift \
//   native/CineFlash/Tests/WidgetFeedParser/main.swift -o /tmp/widget-feed-tests
// /tmp/widget-feed-tests
import Foundation

func parse(_ xml: String) -> [WidgetNewsItem] {
    WidgetFeedParser.parse(Data(xml.utf8), source: "Test")
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let rss = """
<rss><channel><title>Channel title</title><item>
<title><![CDATA[ Cinema &amp; <b>film</b> ]]></title>
<link>https://example.test/news?a=1&amp;b=2</link>
</item><item><title>Second &#8217; title</title><guid>fallback</guid></item>
</channel></rss>
"""
let items = parse(rss)
expect(items.count == 2, "RSS item count")
expect(items[0].title == "Cinema & film", "CDATA, entities and title markup")
expect(items[1].title == "Second ’ title", "Numeric XML entities")
expect(items.allSatisfy { $0.source == "Test" }, "Source preserved")

let atom = """
<feed xmlns="http://www.w3.org/2005/Atom"><entry>
<title type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">Cinema &amp; <b>film</b></div></title>
<link href="https://example.test/news?a=1&amp;b=2"/>
</entry></feed>
"""
expect(parse(atom).first?.id == items[0].id, "RSS text link and Atom href produce the same stable ID")
expect(parse(atom).first?.title == "Cinema & film", "Atom nested title")
expect(parse("<rss><item><title>Second ’ title</title><link>fallback</link></item></rss>").first?.id == items[1].id,
       "GUID fallback matches link ID")
expect(parse("<rss><item><title>fallback</title></item></rss>").first?.id == items[1].id,
       "Title fallback matches link ID")
expect(parse("<rss><item><title> </title></item></rss>").isEmpty, "Empty titles skipped")

let item = "<item><title>Title</title><link>https://example.test/</link></item>"
expect(parse("<rss>" + String(repeating: item, count: 12) + "</rss>").count == 10, "Ten-item limit")
expect(parse("<rss>" + String(repeating: item, count: 10) + "<broken").count == 10,
       "Parser stops before malformed content after the tenth item")
expect(parse("<rss>" + String(repeating: "<item/>", count: 10) + item + "</rss>").isEmpty,
       "Limit counts items even when they have no title")
expect(parse("<rss>" + item + "<item>").isEmpty, "Malformed document rejected before limit")
expect(parse("<rss>" + String(repeating: "<item>", count: 100_000)).isEmpty,
       "Adversarial unmatched opening tags rejected")
expect(parse(String(repeating: "<x>", count: 65) + item + String(repeating: "</x>", count: 65)).isEmpty,
       "Excessive nesting rejected")
expect(parse("<rss><item><title><![CDATA[" + String(repeating: "<", count: 100_000) + "]]></title></item></rss>").isEmpty,
       "Adversarial title markup handled without regex")

let small = "<rss>" + item + "</rss>"
let atLimit = small + String(repeating: " ", count: WidgetFeedParser.maxFeedBytes - small.utf8.count)
expect(parse(atLimit).count == 1, "Exactly the byte limit is accepted")
expect(parse(atLimit + " ").isEmpty, "Oversized input rejected")
expect(WidgetFeedParser.parse(Data([0xff, 0xfe]), source: "Test").isEmpty, "Invalid UTF-8 rejected")
expect(WidgetFeedParser.parse(small.data(using: .utf16LittleEndian)!, source: "Test").isEmpty,
       "UTF-16 rejected before DTD check")
expect(parse("<!DOCTYPE rss [<!ENTITY a 'expansion'>]><rss><item><title>&a;</title></item></rss>").isEmpty,
       "Internal DTD/entity rejected")
expect(parse("<!DOCTYPE rss SYSTEM 'file:///etc/passwd'><rss>" + item + "</rss>").isEmpty,
       "External DTD rejected")
print("WidgetFeedParser regressions passed")
