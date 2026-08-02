// The YouTube Data API returns titles HTML-escaped, so an apostrophe arrives as
// `&#39;` and an ampersand as `&amp;`. Left alone those leak straight into the
// UI and, worse, into the alias/search text used to match tracks.
export function decodeHtmlEntities(value: string): string {
  if (!value || !value.includes('&')) return value;
  return value
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    // Ampersand last, so "&amp;quot;" cannot be double-decoded into a quote.
    .replace(/&amp;/g, '&');
}
