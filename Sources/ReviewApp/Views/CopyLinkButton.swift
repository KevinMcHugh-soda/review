import AppKit
import SwiftUI

/// A menu item that puts a web address on the pasteboard.
struct CopyLinkButton: View {
    let url: URL

    var body: some View {
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }
}
