import Foundation
import KilnCore

extension DownloadStatus {
    /// Progress as a whole percentage, such as "25%", when the total size is known.
    var percentText: String? {
        fraction?.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "4.2 GB of 17 GB · 25% · filename", leaving out whatever is unknown.
    var transferCaption: String {
        var caption = receivedBytes.formatted(.byteCount(style: .file))
        if let totalBytes {
            caption += " of " + totalBytes.formatted(.byteCount(style: .file))
        }
        if let percentText {
            caption += " · " + percentText
        }
        if let file = currentFile?.split(separator: "/").last {
            caption += " · " + String(file)
        }
        return caption
    }
}
