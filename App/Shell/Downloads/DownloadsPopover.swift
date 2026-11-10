import SwiftUI

/// The list of downloads with their progress, speed and time left.
struct DownloadsPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let library = model.library
        let downloads = library.downloadEntries

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Open Models") {
                    model.selection = .models
                    dismiss()
                }
                .buttonStyle(.link)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(downloads.enumerated()), id: \.element.recipe.id) { index, download in
                        if index > 0 {
                            Divider().padding(.horizontal, 16)
                        }
                        DownloadDetailRow(
                            name: download.recipe.name,
                            status: download.status,
                            speed: library.downloadSpeeds[download.recipe.id],
                            start: { library.download(download.recipe) },
                            pause: { library.pauseDownload(download.recipe) },
                            cancel: { library.cancelDownload(download.recipe) },
                            dismiss: { library.dismissDownload(download.recipe) },
                            use: {
                                model.use(download.recipe)
                                dismiss()
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 360)
    }
}
