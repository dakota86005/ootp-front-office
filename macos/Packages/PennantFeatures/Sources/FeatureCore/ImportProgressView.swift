import PennantAPI
import PennantKit
import SwiftUI

/// An import under way, as the server reports it (`importProgress` on the status and the event stream): when the
/// served counts allow it, a determinate bar with the share done, and the table being written in the help tag. Before the first
/// progress arrives it is an indeterminate bar. The phase code is not put into words here (the server will serve
/// them).
public struct ImportProgressView: View {
    let progress: Components.Schemas.ImportProgress?

    public init(progress: Components.Schemas.ImportProgress?) {
        self.progress = progress
    }

    public var body: some View {
        Group {
            if let progress, progress.files > 0 {
                ProgressView(value: Double(min(progress.fileIndex, progress.files)), total: Double(progress.files)) {
                    Text("Importing…")
                } currentValueLabel: {
                    if let share = ServedFormat.share(progress.fileIndex, of: progress.files) {
                        Text(verbatim: share).monospacedDigit()
                    }
                }
            } else {
                ProgressView {
                    Text("Importing…")
                }
            }
        }
        // The table being written is OOTP's file name, not words for the GM: it is in the help tag until the server
        // serves a name for it (N4)
        .help(detail: progress?.table)
        .accessibilityIdentifier("import.progress")
    }
}
