// Container app for the Quick Look extension. It never runs in the background:
// opening it just shows a short note and quits.
#import <Cocoa/Cocoa.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        if (@available(macOS 14.0, *)) {
            [NSApp activate];
        } else {
            [NSApp activateIgnoringOtherApps:YES];
        }

        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Markdown Preview is installed";
        alert.informativeText =
            @"Select a .md file in Finder and press Space.\n\n"
            @"Nothing runs in the background. The preview extension starts only while a preview is open.\n\n"
            @"If previews don't appear, check that Markdown Preview is on in System Settings → General → "
            @"Login Items & Extensions → Quick Look.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
    return 0;
}
