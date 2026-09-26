import PennantAPI
import PennantKit
import SwiftUI

/// An import under way, as the server reports it (`importProgress` on the status and the event stream): the table
/// being written and, when the served counts allow it, a determinate bar with the share done. Before the first
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
                    Text(verbatim: progress.table)
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
        .accessibilityIdentifier("import.progress")
    }
}
