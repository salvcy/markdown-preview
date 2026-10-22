#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Called once per local image the document references, with its absolute path.
/// Return the `src` to use instead (e.g. "cid:img0"), or nil to leave it unchanged.
typedef NSString *_Nullable (^MDImageResolver)(NSString *path);

/// Converts Markdown bytes (UTF-8, UTF-16 with BOM, or legacy Latin-1) into a
/// complete, self-contained UTF-8 HTML document. Relative image paths resolve
/// against `baseDirectory`.
NSData *MDRenderHTMLDocument(NSData *markdown,
                             NSURL *_Nullable baseDirectory,
                             MDImageResolver _Nullable resolveImage);

NS_ASSUME_NONNULL_END
