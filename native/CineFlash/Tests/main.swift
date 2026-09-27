// macOS: xcrun swiftc -target "$(uname -m)-apple-macosx12.0" -o /tmp/news-service-tests CineFlash/Models.swift CineFlash/NewsService.swift Tests/main.swift
// Then run /tmp/news-service-tests (from native/CineFlash).
import Foundation

let source = NewsSource(key: "test", name: "Test feed", url: "https://example.test/feed", enabled: true)
func parse(_ xml: String) -> [NewsItem] { NewsService.parseRss(xml, source: source) }
func rss(_ body: String) -> String { "<rss><channel>\(body)</channel></rss>" }
let item = "<item><title>Film &amp; cinema &#8217;</title><link>https://example.test/film?a=1&amp;b=2</link></item>"
let normal = parse(rss(item))
assert(normal.count == 1)
assert(normal[0].title == "Film & cinema ’")
assert(normal[0].link == "https://example.test/film?a=1&b=2")
assert(normal[0].id == NewsService.hashId(normal[0].link))
assert(normal[0].sourceKey == source.key && normal[0].source == source.name)

let rich = parse("""
<rss xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel><item><title><![CDATA[Un <b>film</b> &quot;nuovo&quot;]]></title>
<guid>https://example.test/guid</guid>
<content:encoded><![CDATA[<p>Cinema&nbsp;oggi &#x27;!</p><script>hidden</script>]]></content:encoded>
<dc:date>2026-09-27T12:00:00Z</dc:date>
<media:thumbnail url="https://example.test/poster?a=1&amp;b=2"/>
<enclosure url="https://example.test/other"/>
</item></channel></rss>
""")
assert(rich.count == 1)
assert(rich[0].title == "Un film \"nuovo\"")
assert(rich[0].summary == "Cinema oggi '!")
assert(rich[0].publishedAt == "2026-09-27T12:00:00Z")
assert(rich[0].imageUrl == "https://example.test/poster?a=1&b=2")

let atom = parse("""
<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom</title>
<link href="https://example.test/atom"/><summary>Short summary</summary>
<published>2026-09-27T10:00:00Z</published></entry></feed>
""")
assert(atom.count == 1 && atom[0].link == "https://example.test/atom")
assert(atom[0].summary == "Short summary")
assert(atom[0].publishedAt == "2026-09-27T10:00:00Z")
assert(parse(rss("<item><title>No link</title></item>" + item)).count == 1)
assert(parse(rss("<item><title>First</title><title>Second</title><link>x</link></item>"))[0].title == "First")
assert(parse(rss("<item><title>T</title><link>x</link><description>" + String(repeating: "a", count: 500) + "</description></item>"))[0].summary.count == 400)

// Each rejection must discard any preceding complete items too.
assert(parse(rss(item) + "<").isEmpty)
for opening in ["<item>", "<entry>", "<item "] {
    let start = Date()
    assert(parse(rss(String(repeating: opening, count: 50_000))).isEmpty)
    assert(Date().timeIntervalSince(start) < 5, "Unmatched openings took too long")
}
assert(parse(rss(String(repeating: "<x>", count: 65) + item + String(repeating: "</x>", count: 65))).isEmpty)
assert(parse(rss(String(repeating: item, count: 512))).count == 512)
assert(parse(rss(String(repeating: item, count: 513))).isEmpty)
let longTitle = "<item><title>" + String(repeating: "é", count: 8193) + "</title><link>x</link></item>"
assert(parse(rss(item + longTitle)).isEmpty)
let longAttribute = "<item><title>T</title><link href=\"" + String(repeating: "a", count: 16385) + "\"/></item>"
assert(parse(rss(item + longAttribute)).isEmpty)
let exactFeed = rss(item) + String(repeating: " ", count: NewsService.maxFeedBytes - rss(item).utf8.count)
assert(parse(exactFeed).count == 1)
assert(parse(exactFeed + " ").isEmpty)
assert(parse("<!DOCTYPE rss [<!ENTITY x 'expanded'>]>" + rss("<item><title>&x;</title><link>x</link></item>")).isEmpty)
assert(parse("<!DOCTYPE rss SYSTEM 'file:///etc/passwd'>" + rss(item)).isEmpty)
print("NewsService RSS/Atom and resource-limit regression checks passed")
