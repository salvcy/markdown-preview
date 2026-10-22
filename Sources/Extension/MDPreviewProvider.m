#import <QuickLookUI/QuickLookUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <sys/stat.h>
#import "MDRender.h"

// Caps so a huge or unusual document can't balloon memory use.
static const off_t kMaxImageBytes = 20 * 1024 * 1024;
static const off_t kMaxTotalImageBytes = 64 * 1024 * 1024;

@interface MDPreviewProvider : QLPreviewProvider <QLPreviewingController>
@end

@implementation MDPreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest *)request
                   completionHandler:(void (^)(QLPreviewReply *_Nullable, NSError *_Nullable))handler {
    NSURL *fileURL = request.fileURL;

    QLPreviewReply *reply = [[QLPreviewReply alloc]
        initWithDataOfContentType:UTTypeHTML
                      contentSize:CGSizeMake(900, 1000)
                dataCreationBlock:^NSData *_Nullable(QLPreviewReply *replyToUpdate, NSError **error) {
                    NSData *markdown = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:error];
                    if (!markdown) return nil;

                    // Local images are passed to Quick Look as attachments and referenced as cid:imgN.
                    NSMutableDictionary<NSString *, QLPreviewReplyAttachment *> *attachments = [NSMutableDictionary dictionary];
                    NSMutableDictionary<NSString *, NSString *> *sourceForPath = [NSMutableDictionary dictionary];
                    __block off_t totalBytes = 0;

                    MDImageResolver resolver = ^NSString *(NSString *path) {
                        NSString *known = sourceForPath[path];
                        if (known) return known;

                        UTType *type = [UTType typeWithFilenameExtension:path.pathExtension.lowercaseString];
                        if (!type || ![type conformsToType:UTTypeImage]) return nil;

                        struct stat st;
                        if (stat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return nil;
                        if (st.st_size > kMaxImageBytes || totalBytes + st.st_size > kMaxTotalImageBytes) return nil;

                        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
                        if (!data) return nil;
                        totalBytes += (off_t)data.length;

                        NSString *key = [NSString stringWithFormat:@"img%lu", (unsigned long)attachments.count];
                        attachments[key] = [[QLPreviewReplyAttachment alloc] initWithData:data contentType:type];
                        NSString *src = [@"cid:" stringByAppendingString:key];
                        sourceForPath[path] = src;
                        return src;
                    };

                    NSData *html = MDRenderHTMLDocument(markdown, fileURL.URLByDeletingLastPathComponent, resolver);
                    replyToUpdate.stringEncoding = NSUTF8StringEncoding;
                    if (attachments.count) replyToUpdate.attachments = attachments;
                    return html;
                }];

    handler(reply, nil);
}

@end
