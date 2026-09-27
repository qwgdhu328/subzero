// Run with Node 24+: node --test tests/news.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fetchAllNews } from '../src/logic/news.ts';

const source = { key: 'test', name: 'Test', url: 'https://example.test/feed', enabled: true };

async function parse(t, xml) {
  t.mock.method(globalThis, 'fetch', async () => ({ ok: true, text: async () => xml }));
  return fetchAllNews([source]);
}

test('RSS preserves case-insensitive tags, attributes, CDATA, entities and first values', async (t) => {
  const { items, failed } = await parse(t, `<rss><channel><item>
    <TITLE lang="it"><![CDATA[ Cinema &amp; <b>film</b> ]]></TITLE><title>Ignored</title>
    <link>https://example.test/article?a=1&amp;b=2</link>
    <description><![CDATA[<p>Summary &#39;one&#39;</p>]]></description>
    <pubDate>2026-09-20T12:00:00Z</pubDate>
    <media:thumbnail url="https://example.test/image.jpg"/>
  </item></channel></rss>`);
  assert.deepEqual(failed, []);
  assert.equal(items.length, 1);
  assert.equal(items[0].title, 'Cinema & film');
  assert.equal(items[0].link, 'https://example.test/article?a=1&b=2');
  assert.equal(items[0].summary, "Summary 'one'");
  assert.equal(items[0].publishedAt, '2026-09-20T12:00:00.000Z');
  assert.equal(items[0].imageUrl, 'https://example.test/image.jpg');
});

test('Atom uses href, namespaced content and date fallbacks', async (t) => {
  const { items, failed } = await parse(t, `<feed><entry>
    <title>Atom</title><link href="https://example.test/atom"/>
    <content:encoded><![CDATA[<p>Content &amp; more</p>]]></content:encoded>
    <dc:date>2026-09-21T00:00:00Z</dc:date>
  </entry></feed>`);
  assert.deepEqual(failed, []);
  assert.equal(items.length, 1);
  assert.equal(items[0].link, 'https://example.test/atom');
  assert.equal(items[0].summary, 'Content & more');
  assert.equal(items[0].publishedAt, '2026-09-21T00:00:00.000Z');
});

test('missing tags and similarly prefixed tags do not become news items', async (t) => {
  const result = await parse(t, `<rss>
    <item><titleExtra>Wrong</titleExtra><link>https://example.test/one</link></item>
    <item><title>Unclosed<link>https://example.test/two</link></item>
    <item><title>Missing link</title></item>
  </rss>`);
  assert.deepEqual(result, { items: [], failed: ['Test'] });
});

for (const opening of ['<title>', '<title ', '<description>', '<content:encoded>']) {
  test(`many unmatched ${opening} openings finish within a bounded time`, () => {
    // A separate process enforces the deadline even if synchronous parsing stalls.
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
      import assert from 'node:assert/strict';
      import { fetchAllNews } from ${JSON.stringify(new URL('../src/logic/news.ts', import.meta.url).href)};
      const valid = '<item><title>Good</title><link>https://example.test/good</link></item>';
      const malformed = '<item>' + ${JSON.stringify(opening)}.repeat(100000) + '</item>';
      globalThis.fetch = async () => ({ ok: true, text: async () => '<rss>' + malformed + valid + '</rss>' });
      const result = await fetchAllNews([${JSON.stringify(source)}]);
      assert.deepEqual(result.failed, []);
      assert.equal(result.items.length, 1);
      assert.equal(result.items[0].title, 'Good');
    `], { encoding: 'utf8', timeout: 5000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
  });
}
