import AppKit
import SwiftUI

/// Single binary, two personalities: run it with arguments and it behaves like a CLI, run it
/// with none (or from Finder) and it opens the app.
@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
            // Launch Services passes -psn_… when you double-click an app bundle.
            .filter { !$0.hasPrefix("-psn_") }

        if let first = args.first, first.hasPrefix("--") {
            exit(CLI.run(args))
        }

        FolderForgeApp.main()
    }
}
