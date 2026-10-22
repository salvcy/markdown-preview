// Test harness: renders a Markdown file with the exact code the extension uses.
//   mdrender file.md            -> HTML on stdout (local images inlined as data: URIs)
//   mdrender file.md --bench N  -> average render time over N runs
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <time.h>
#import "MDRender.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: mdrender file.md [--bench N]\n");
            return 2;
        }
        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        NSData *markdown = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
        if (!markdown) {
            fprintf(stderr, "cannot read %s\n", argv[1]);
            return 1;
        }
        MDImageResolver resolver = ^NSString *(NSString *path) {
            fprintf(stderr, "image: %s\n", path.fileSystemRepresentation);
            NSData *data = [NSData dataWithContentsOfFile:path];
            UTType *type = [UTType typeWithFilenameExtension:path.pathExtension.lowercaseString];
            if (!data || !type.preferredMIMEType) return nil;
            return [NSString stringWithFormat:@"data:%@;base64,%@", type.preferredMIMEType,
                                              [data base64EncodedStringWithOptions:0]];
        };
        NSURL *base = url.URLByDeletingLastPathComponent;

        if (argc >= 4 && strcmp(argv[2], "--bench") == 0) {
            int runs = atoi(argv[3]);
            if (runs < 1) runs = 1;
            struct timespec t0, t1;
            clock_gettime(CLOCK_MONOTONIC, &t0);
            NSUInteger bytes = 0;
            for (int i = 0; i < runs; i++) {
                @autoreleasepool { bytes = MDRenderHTMLDocument(markdown, base, nil).length; }
            }
            clock_gettime(CLOCK_MONOTONIC, &t1);
            double ms = ((t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6) / runs;
            printf("%lu bytes in -> %lu bytes out, %.3f ms per render\n",
                   (unsigned long)markdown.length, (unsigned long)bytes, ms);
            return 0;
        }

        NSData *html = MDRenderHTMLDocument(markdown, base, resolver);
        fwrite(html.bytes, 1, html.length, stdout);
    }
    return 0;
}
