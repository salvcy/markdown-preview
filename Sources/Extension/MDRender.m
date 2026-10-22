#import "MDRender.h"

#include <string.h>
#include "cmark-gfm.h"
#include "cmark-gfm-extension_api.h"
#include "cmark-gfm-core-extensions.h"

#pragma mark - Page template

// GitHub-style stylesheet with automatic light/dark mode. No web fonts, no JS.
#define MD_CSS \
":root{color-scheme:light dark;--fg:#1f2328;--muted:#59636e;--bg:#fff;--line:#d1d9e0;--line-soft:#d1d9e0b3;" \
"--code:#818b981f;--pre:#f6f8fa;--link:#0969da;--mark:#fff8c5;" \
"--note:#0969da;--tip:#1a7f37;--important:#8250df;--warning:#9a6700;--caution:#d1242f}" \
"@media (prefers-color-scheme:dark){:root{--fg:#f0f6fc;--muted:#9198a1;--bg:#0d1117;--line:#3d444d;--line-soft:#3d444db3;" \
"--code:#656c7633;--pre:#151b23;--link:#4493f8;--mark:#bb800926;" \
"--note:#4493f8;--tip:#3fb950;--important:#ab7df8;--warning:#d29922;--caution:#f85149}}" \
"html{background:var(--bg)}" \
"body{margin:0;color:var(--fg);background:var(--bg);font:16px/1.5 -apple-system,BlinkMacSystemFont,'Helvetica Neue',Arial,sans-serif;overflow-wrap:break-word}" \
".markdown-body{max-width:980px;margin:0 auto;padding:32px 40px 48px}" \
".markdown-body>:first-child{margin-top:0}.markdown-body>:last-child{margin-bottom:0}" \
"a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}" \
"p,blockquote,ul,ol,dl,table,pre,details{margin:0 0 16px}" \
"h1,h2,h3,h4,h5,h6{margin:24px 0 16px;font-weight:600;line-height:1.25}" \
"h1{font-size:2em}h2{font-size:1.5em}h1,h2{padding-bottom:.3em;border-bottom:1px solid var(--line-soft)}" \
"h3{font-size:1.25em}h4{font-size:1em}h5{font-size:.875em}h6{font-size:.85em;color:var(--muted)}" \
"hr{height:.25em;margin:24px 0;padding:0;border:0;background:var(--line)}" \
"ul,ol{padding-left:2em}ol ol,ol ul,ul ol,ul ul{margin-bottom:0}li+li{margin-top:.25em}li>p{margin-top:16px}" \
"li:has(>input[type=checkbox]){list-style:none}li>input[type=checkbox]{margin:0 .2em .25em -1.4em;vertical-align:middle}" \
"dt{font-weight:600}dd{margin:0 0 16px;padding:0 16px}" \
"blockquote{padding:0 1em;color:var(--muted);border-left:.25em solid var(--line)}" \
"blockquote>:first-child{margin-top:0}blockquote>:last-child{margin-bottom:0}" \
"code,kbd,pre,samp,tt{font-family:ui-monospace,SFMono-Regular,'SF Mono',Menlo,monospace}" \
"code,tt{padding:.2em .4em;font-size:85%;white-space:break-spaces;background:var(--code);border-radius:6px}" \
"pre{padding:16px;overflow:auto;font-size:85%;line-height:1.45;background:var(--pre);border-radius:6px;word-wrap:normal}" \
"pre code,pre tt{padding:0;font-size:100%;white-space:pre;word-break:normal;background:transparent;border-radius:0}" \
"kbd{display:inline-block;padding:3px 5px;font-size:11px;line-height:10px;vertical-align:middle;background:var(--pre);" \
"border:1px solid var(--line);border-radius:6px;box-shadow:inset 0 -1px 0 var(--line)}" \
"table{display:block;width:max-content;max-width:100%;overflow:auto;border-spacing:0;border-collapse:collapse}" \
"th,td{padding:6px 13px;border:1px solid var(--line)}th{font-weight:600}tr:nth-child(2n){background:var(--pre)}" \
"img{max-width:100%;box-sizing:content-box}mark{color:inherit;background:var(--mark)}summary{cursor:pointer}" \
".footnotes{font-size:12px;color:var(--muted);border-top:1px solid var(--line);padding-top:8px}.footnotes ol{padding-left:16px}" \
".front-matter{color:var(--muted)}" \
".alert{padding:8px 16px;color:inherit;border-left:.25em solid var(--line)}.alert-title{font-weight:500;line-height:1}" \
".alert-note{border-left-color:var(--note)}.alert-note>.alert-title{color:var(--note)}" \
".alert-tip{border-left-color:var(--tip)}.alert-tip>.alert-title{color:var(--tip)}" \
".alert-important{border-left-color:var(--important)}.alert-important>.alert-title{color:var(--important)}" \
".alert-warning{border-left-color:var(--warning)}.alert-warning>.alert-title{color:var(--warning)}" \
".alert-caution{border-left-color:var(--caution)}.alert-caution>.alert-title{color:var(--caution)}"

// The CSP blocks scripts and every network request: only inline CSS and
// embedded (cid:/data:) images can load.
static const char kPageHead[] =
    "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">\n"
    "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src cid: data:\">\n"
    "<meta name=\"color-scheme\" content=\"light dark\">\n"
    "<style>" MD_CSS "</style>\n"
    "</head><body><article class=\"markdown-body\">\n";

static const char kPageTail[] = "</article></body></html>\n";

#pragma mark - Text decoding

static BOOL IsValidUTF8(const uint8_t *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        // Fast path: skip 8 ASCII bytes at a time.
        if (n - i >= 8) {
            uint64_t chunk;
            memcpy(&chunk, s + i, 8);
            if ((chunk & 0x8080808080808080ULL) == 0) { i += 8; continue; }
        }
        uint8_t c = s[i];
        if (c < 0x80) { i++; continue; }
        size_t len;
        uint8_t lo = 0x80, hi = 0xBF;  // allowed range of the 2nd byte (Unicode Table 3-7)
        if (c >= 0xC2 && c <= 0xDF) {
            len = 2;
        } else if (c >= 0xE0 && c <= 0xEF) {
            len = 3;
            if (c == 0xE0) lo = 0xA0;
            else if (c == 0xED) hi = 0x9F;
        } else if (c >= 0xF0 && c <= 0xF4) {
            len = 4;
            if (c == 0xF0) lo = 0x90;
            else if (c == 0xF4) hi = 0x8F;
        } else {
            return NO;
        }
        if (n - i < len || s[i + 1] < lo || s[i + 1] > hi) return NO;
        for (size_t k = 2; k < len; k++) {
            if ((s[i + k] & 0xC0) != 0x80) return NO;
        }
        i += len;
    }
    return YES;
}

/// Returns the input as UTF-8. Valid UTF-8 passes through without copying.
static NSData *UTF8Data(NSData *data) {
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    if (n == 0) return data;

    NSStringEncoding bomEncoding = 0;
    if (n >= 4 && ((b[0] == 0xFF && b[1] == 0xFE && b[2] == 0 && b[3] == 0) ||
                   (b[0] == 0 && b[1] == 0 && b[2] == 0xFE && b[3] == 0xFF))) {
        bomEncoding = NSUTF32StringEncoding;
    } else if (n >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
        bomEncoding = NSUTF16StringEncoding;
    } else if (IsValidUTF8(b, n)) {
        return data;
    }

    // Not UTF-8: decode the way text editors fall back (Windows Latin-1, then ISO Latin-1).
    const NSStringEncoding candidates[] = {bomEncoding, NSWindowsCP1252StringEncoding, NSISOLatin1StringEncoding};
    for (size_t i = 0; i < sizeof candidates / sizeof *candidates; i++) {
        if (candidates[i] == 0) continue;
        NSString *text = [[NSString alloc] initWithData:data encoding:candidates[i]];
        if (text) return [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    }
    return data;
}

#pragma mark - Front matter

typedef struct {
    size_t innerStart, innerEnd, end;
} MDFrontMatter;

static size_t LineEnd(const char *s, size_t n, size_t i) {
    const char *nl = memchr(s + i, '\n', n - i);
    return nl ? (size_t)(nl - s) : n;
}

/// True if line [a, b) is exactly `fence`, ignoring trailing spaces, tabs and CR.
static BOOL LineIsFence(const char *s, size_t a, size_t b, const char *fence) {
    while (b > a && (s[b - 1] == '\r' || s[b - 1] == ' ' || s[b - 1] == '\t')) b--;
    return b - a == 3 && memcmp(s + a, fence, 3) == 0;
}

/// Detects a leading YAML (--- ... ---) or TOML (+++ ... +++) front matter block.
/// Its first non-blank line must look like a key ("key: value" / "key = value"),
/// so a document that merely starts with a horizontal rule is left alone.
static BOOL FindFrontMatter(const char *s, size_t n, size_t start, MDFrontMatter *out) {
    if (start >= n) return NO;
    size_t e = LineEnd(s, n, start);
    const char *closeA, *closeB;
    char keyChar;
    if (LineIsFence(s, start, e, "---")) {
        closeA = "---"; closeB = "..."; keyChar = ':';
    } else if (LineIsFence(s, start, e, "+++")) {
        closeA = closeB = "+++"; keyChar = '=';
    } else {
        return NO;
    }

    BOOL sawFirstLine = NO;
    for (size_t a = e + 1; a < n;) {
        size_t b = LineEnd(s, n, a);
        if (LineIsFence(s, a, b, closeA) || LineIsFence(s, a, b, closeB)) {
            if (!sawFirstLine) return NO;
            out->innerStart = e + 1;
            out->innerEnd = a;
            out->end = b < n ? b + 1 : n;
            return YES;
        }
        if (!sawFirstLine) {
            size_t k = a;
            while (k < b && (s[k] == ' ' || s[k] == '\t' || s[k] == '\r')) k++;
            if (k < b) {
                if (!memchr(s + k, keyChar, b - k)) return NO;
                sawFirstLine = YES;
            }
        }
        a = b + 1;
    }
    return NO;
}

static void AppendEscapedHTML(NSMutableData *out, const char *s, size_t n) {
    size_t run = 0;
    for (size_t i = 0; i < n; i++) {
        const char *rep;
        switch (s[i]) {
            case '&': rep = "&amp;"; break;
            case '<': rep = "&lt;"; break;
            case '>': rep = "&gt;"; break;
            case '"': rep = "&quot;"; break;
            default: continue;
        }
        [out appendBytes:s + run length:i - run];
        [out appendBytes:rep length:strlen(rep)];
        run = i + 1;
    }
    [out appendBytes:s + run length:n - run];
}

#pragma mark - Markdown

static const int kCmarkOptions = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8;

/// GitHub Flavored Markdown -> HTML fragment. Caller frees with free().
static char *RenderMarkdown(const char *s, size_t n) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cmark_gfm_core_extensions_ensure_registered(); });

    cmark_parser *parser = cmark_parser_new(kCmarkOptions);
    if (!parser) return NULL;
    // tagfilter neutralises <script>, <style>, <iframe> etc. in raw HTML, like GitHub.
    static const char *const kExtensions[] = {"table", "strikethrough", "autolink", "tagfilter", "tasklist"};
    for (size_t i = 0; i < sizeof kExtensions / sizeof *kExtensions; i++) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension(kExtensions[i]);
        if (ext) cmark_parser_attach_syntax_extension(parser, ext);
    }
    cmark_parser_feed(parser, s, n);
    cmark_node *doc = cmark_parser_finish(parser);
    char *html = NULL;
    if (doc) {
        html = cmark_render_html(doc, kCmarkOptions, cmark_parser_get_syntax_extensions(parser));
        cmark_node_free(doc);
    }
    cmark_parser_free(parser);
    return html;
}

#pragma mark - GitHub alerts  (> [!NOTE] ...)

static NSString *ApplyAlerts(NSString *html) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
            regularExpressionWithPattern:@"<blockquote>\\n<p>\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\](?:<br />)?(\\n|</p>\\n)"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];
    });
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    if (matches.count == 0) return html;

    NSMutableString *out = [NSMutableString stringWithCapacity:html.length + matches.count * 64];
    NSUInteger last = 0;
    for (NSTextCheckingResult *m in matches) {
        [out appendString:[html substringWithRange:NSMakeRange(last, m.range.location - last)]];
        NSString *kind = [html substringWithRange:[m rangeAtIndex:1]].lowercaseString;
        BOOL textFollows = [html characterAtIndex:[m rangeAtIndex:2].location] == '\n';
        [out appendFormat:@"<blockquote class=\"alert alert-%@\">\n<p class=\"alert-title\">%@</p>\n%@",
                          kind, kind.capitalizedString, textFollows ? @"<p>" : @""];
        last = NSMaxRange(m.range);
    }
    [out appendString:[html substringFromIndex:last]];
    return out;
}

#pragma mark - Local images

static NSString *UnescapeHTML(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSUInteger n = s.length, i = 0;
    while (i < n) {
        NSRange amp = [s rangeOfString:@"&" options:NSLiteralSearch range:NSMakeRange(i, n - i)];
        if (amp.location == NSNotFound) break;
        [out appendString:[s substringWithRange:NSMakeRange(i, amp.location - i)]];
        i = amp.location;
        NSRange semi = [s rangeOfString:@";" options:NSLiteralSearch range:NSMakeRange(i, MIN(n - i, (NSUInteger)12))];
        NSString *rep = nil;
        if (semi.location != NSNotFound) {
            NSString *name = [s substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)];
            if ([name isEqualToString:@"amp"]) rep = @"&";
            else if ([name isEqualToString:@"lt"]) rep = @"<";
            else if ([name isEqualToString:@"gt"]) rep = @">";
            else if ([name isEqualToString:@"quot"]) rep = @"\"";
            else if ([name isEqualToString:@"apos"]) rep = @"'";
            else if (name.length > 1 && [name characterAtIndex:0] == '#') {
                BOOL hex = [name characterAtIndex:1] == 'x' || [name characterAtIndex:1] == 'X';
                NSString *digits = [name substringFromIndex:hex ? 2 : 1];
                const char *d = digits.UTF8String;
                char *end = NULL;
                unsigned long cp = (d && *d) ? strtoul(d, &end, hex ? 16 : 10) : 0;
                if (end && *end == '\0' && cp > 0 && cp <= 0x10FFFF && !(cp >= 0xD800 && cp <= 0xDFFF)) {
                    UTF32Char c = (UTF32Char)cp;
                    rep = [[NSString alloc] initWithBytes:&c length:4 encoding:NSUTF32LittleEndianStringEncoding];
                }
            }
        }
        if (rep) {
            [out appendString:rep];
            i = semi.location + 1;
        } else {
            [out appendString:@"&"];
            i++;
        }
    }
    if (i < n) [out appendString:[s substringFromIndex:i]];
    return out;
}

static BOOL HasURLScheme(NSString *s) {
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == ':') return i > 0;
        BOOL letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        BOOL other = (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
        if (!(letter || (i > 0 && other))) return NO;
    }
    return NO;
}

/// Maps an <img src> value to a replacement via the resolver, for local files only.
static NSString *ResolveImageSource(NSString *raw, NSURL *base, MDImageResolver resolve) {
    NSString *v = [UnescapeHTML(raw) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (v.length == 0 || [v hasPrefix:@"#"] || [v hasPrefix:@"//"]) return nil;

    NSString *path = nil;
    if (HasURLScheme(v)) {
        if (![v.lowercaseString hasPrefix:@"file:"]) return nil;  // remote, data:, cid: ... untouched
        path = [NSURL URLWithString:v].path;
    } else {
        NSRange cut = [v rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
        if (cut.location != NSNotFound) v = [v substringToIndex:cut.location];
        v = v.stringByRemovingPercentEncoding ?: v;
        if (v.length == 0) return nil;
        if ([v hasPrefix:@"/"]) path = v;
        else if (base.path) path = [base.path stringByAppendingPathComponent:v];
    }
    if (path.length == 0) return nil;
    return resolve(path.stringByStandardizingPath);
}

static NSString *EscapeAttribute(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
        stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

static NSString *RewriteImages(NSString *html, NSURL *base, MDImageResolver resolve) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression
            regularExpressionWithPattern:@"(<img\\b[^>]*?\\s)src\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
                                 options:NSRegularExpressionCaseInsensitive
                                   error:NULL];
    });
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    if (matches.count == 0) return html;

    NSMutableString *out = [NSMutableString stringWithCapacity:html.length];
    NSUInteger last = 0;
    for (NSTextCheckingResult *m in matches) {
        NSRange value = NSMakeRange(NSNotFound, 0);
        for (NSUInteger g = 2; g <= 4 && value.location == NSNotFound; g++) value = [m rangeAtIndex:g];
        if (value.location == NSNotFound) continue;
        NSString *src = ResolveImageSource([html substringWithRange:value], base, resolve);
        if (!src) continue;  // keep the original tag as-is
        [out appendString:[html substringWithRange:NSMakeRange(last, m.range.location - last)]];
        [out appendString:[html substringWithRange:[m rangeAtIndex:1]]];
        [out appendFormat:@"src=\"%@\"", EscapeAttribute(src)];
        last = NSMaxRange(m.range);
    }
    if (last == 0) return html;
    [out appendString:[html substringFromIndex:last]];
    return out;
}

#pragma mark - Public

NSData *MDRenderHTMLDocument(NSData *markdown, NSURL *baseDirectory, MDImageResolver resolveImage) {
    NSData *utf8 = UTF8Data(markdown);
    const char *s = utf8.length ? utf8.bytes : "";
    size_t n = utf8.length;
    size_t start = (n >= 3 && memcmp(s, "\xEF\xBB\xBF", 3) == 0) ? 3 : 0;  // UTF-8 BOM

    NSMutableData *out = [NSMutableData dataWithCapacity:sizeof kPageHead + n + n / 2 + sizeof kPageTail];
    [out appendBytes:kPageHead length:sizeof kPageHead - 1];

    MDFrontMatter fm;
    if (FindFrontMatter(s, n, start, &fm)) {
        static const char open[] = "<pre class=\"front-matter\"><code>";
        static const char close[] = "</code></pre>\n";
        [out appendBytes:open length:sizeof open - 1];
        AppendEscapedHTML(out, s + fm.innerStart, fm.innerEnd - fm.innerStart);
        [out appendBytes:close length:sizeof close - 1];
        start = fm.end;
    }

    char *body = RenderMarkdown(s + start, n - start);
    if (body) {
        size_t len = strlen(body);
        BOOL alerts = strstr(body, "<blockquote>\n<p>[!") != NULL;
        BOOL images = resolveImage != nil && strcasestr(body, "<img") != NULL;
        NSString *html = (alerts || images)
            ? [[NSString alloc] initWithBytes:body length:len encoding:NSUTF8StringEncoding]
            : nil;
        if (html) {
            if (alerts) html = ApplyAlerts(html);
            if (images) html = RewriteImages(html, baseDirectory, resolveImage);
            [out appendData:[html dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
        } else {
            [out appendBytes:body length:len];
        }
        cmark_get_default_mem_allocator()->free(body);
    }

    [out appendBytes:kPageTail length:sizeof kPageTail - 1];
    return out;
}
