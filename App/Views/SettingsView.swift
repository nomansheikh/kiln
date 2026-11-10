import AppKit
import KilnCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", subtitle: "Accounts, hardware and storage")
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    HuggingFaceCard()
                    HardwareCard()
                    StorageCard()
                    AboutCard()
                }
                .frame(maxWidth: 700)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Building blocks

/// A titled card: plain symbol, title and optional description, then rows.
private struct SettingsCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    var description: String?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                accessory
            }
            RowDivider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }
}

extension SettingsCard where Accessory == EmptyView {
    init(title: String, symbol: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, description: description, accessory: { EmptyView() }, content: content)
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// Title and description on the left, the control on the right.
private struct SettingsRow<Control: View>: View {
    let title: String
    let description: Text?
    let control: Control

    init(_ title: String, description: Text? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                if let description {
                    description
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
    }
}

extension SettingsRow where Control == Text {
    /// A read-only row showing a value.
    init(_ title: String, description: Text? = nil, value: String) {
        self.init(title, description: description) {
            Text(value).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Hugging Face

private struct HuggingFaceCard: View {
    @Environment(AppModel.self) private var model
    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var verifiedName: String?
    @State private var isVerifying = false

    var body: some View {
        SettingsCard(
            title: "Hugging Face",
            symbol: "key.fill",
            description: "Sign in to download gated models"
        ) {
            if model.hasToken {
                Pill(text: "Token saved", systemImage: "checkmark.circle.fill", tint: .green)
            } else {
                Pill(text: "No token", systemImage: "minus.circle")
            }
        } content: {
            SettingsRow(
                "Access token",
                description: Text("Optional. Only gated models, which ask you to accept terms first, need one. [Create a token](https://huggingface.co/settings/tokens)")
            ) {
                if model.hasToken {
                    savedControls
                } else {
                    entryControls
                }
            }

            if let verifiedName {
                Label("Signed in as \(verifiedName)", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RowDivider()
            Label("The token is stored in the macOS Keychain and sent only to huggingface.co.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedInput: String {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var entryControls: some View {
        HStack(spacing: 8) {
            SecureField("Access token", text: $tokenInput, prompt: Text(verbatim: "hf_..."))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: 210)
                .background(Theme.card, in: Capsule())
                .onSubmit(save)
            Button("Save", action: save)
                .buttonStyle(AccentButtonStyle())
                .disabled(trimmedInput.isEmpty)
        }
    }

    private var savedControls: some View {
        HStack(spacing: 8) {
            if isVerifying {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Verify", action: verify)
                .disabled(isVerifying)
            Button(role: .destructive, action: remove) {
                Text("Remove").foregroundStyle(.red)
            }
        }
        .buttonStyle(SoftButtonStyle())
    }

    private func save() {
        guard !trimmedInput.isEmpty else { return }
        do {
            try model.saveToken(trimmedInput)
            tokenInput = ""
            errorMessage = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    private func remove() {
        do {
            try model.removeToken()
            errorMessage = nil
            verifiedName = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    private func verify() {
        isVerifying = true
        Task {
            do {
                verifiedName = try await model.verifyToken()
                errorMessage = nil
            } catch {
                verifiedName = nil
                errorMessage = describe(error)
            }
            isVerifying = false
        }
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Hardware

private struct HardwareCard: View {
    @Environment(AppModel.self) private var model

    private var totalGB: Double { Double(model.memory.physicalMemoryGB) }

    private var usableGB: Double { Double(model.memory.usableBytes) / 1_073_741_824 }

    private var usableFraction: Double {
        guard totalGB > 0 else { return 0 }
        return min(max(usableGB / totalGB, 0), 1)
    }

    var body: some View {
        SettingsCard(title: "Hardware", symbol: "cpu", description: "What this Mac gives models to work with") {
            SettingsRow("Chip", value: chipName())
            RowDivider()
            memory
            RowDivider()
            SettingsRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .fontWeight(.medium)
                Spacer(minLength: 12)
                Text("\(usableGB.formatted(.number.precision(.fractionLength(1)))) GB of \(totalGB.formatted(.number.precision(.fractionLength(0)))) GB available to models")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(proxy.size.width * usableFraction, 8))
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Memory available to models")
            .accessibilityValue("\(Int(usableFraction * 100)) percent")

            Text("Kiln leaves room for macOS and your other apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private func chipName() -> String {
    var size = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
        return "Unknown"
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
        return "Unknown"
    }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

// MARK: - Storage

private struct StorageCard: View {
    @Environment(AppModel.self) private var model
    @State private var modelsSize: Int64?

    var body: some View {
        SettingsCard(title: "Storage", symbol: "internaldrive", description: "Where models and images live on disk") {
            FolderRow(title: "Models folder", folder: model.storage.root, badge: modelsSizeText)
            RowDivider()
            FolderRow(title: "Gallery folder", folder: model.gallery.directory, badge: galleryCountText)
            RowDivider()
            SettingsRow(
                "Loaded model",
                description: Text("Unloading frees the memory the model uses. It loads again the next time you generate.")
            ) {
                Button("Unload Model") { model.unloadModel() }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(model.phase.isBusy)
            }
        }
        // Re-measured whenever a model is installed or deleted.
        .task(id: model.installedIDs) {
            let root = model.storage.root
            modelsSize = await Task.detached(priority: .utility) { directorySize(of: root) }.value
        }
    }

    private var modelsSizeText: String {
        guard let modelsSize else { return "Calculating size…" }
        return "\(modelsSize.formatted(.byteCount(style: .file))) on disk"
    }

    private var galleryCountText: String {
        let count = model.galleryItems.count
        return count == 1 ? "1 image" : "\(count) images"
    }
}

/// A folder with its path, a size or count badge, and a reveal button.
private struct FolderRow: View {
    let title: String
    let folder: URL
    let badge: String

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .fontWeight(.medium)
                    Pill(text: badge)
                }
                Text(verbatim: folder.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(folder.path)
            }
            Spacer(minLength: 0)
            Button("Show in Finder") {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            .buttonStyle(SoftButtonStyle())
            .fixedSize()
        }
    }
}

/// Synchronous on purpose: directory enumerators cannot be iterated from async code.
private func directorySize(of directory: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else {
        return 0
    }
    var total: Int64 = 0
    for case let file as URL in enumerator {
        guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
        total += Int64(values.totalFileAllocatedSize ?? 0)
    }
    return total
}

// MARK: - About

private struct AboutCard: View {
    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Kiln"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development build"
    }

    var body: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            SettingsRow(appName, description: Text("Generates images on this Mac with models you download.")) {
                Pill(text: version)
            }
            RowDivider()
            SettingsRow(
                "Open source",
                description: Text("Kiln is open source under the MIT license and runs models with stable-diffusion.cpp.")
            ) {
                EmptyView()
            }
            RowDivider()
            SettingsRow(
                "Model licenses",
                description: Text("Each model's license is set by its authors. Check the model's page before using its images.")
            ) {
                EmptyView()
            }
        }
    }
}
