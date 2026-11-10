import SwiftUI

/// Saves, verifies and removes the optional Hugging Face access token.
struct HuggingFaceCard: View {
    @Environment(AppModel.self) private var model
    @State private var tokenInput = ""
    @State private var errorMessage: String?
    @State private var verifiedName: String?
    @State private var isVerifying = false

    private var account: HubAccount { model.account }

    private var trimmedInput: String {
        tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SettingsCard(
            title: "Hugging Face",
            symbol: "key.fill",
            description: "Sign in to download gated models"
        ) {
            if account.hasToken {
                Pill(text: "Token saved", systemImage: "checkmark.circle.fill", tint: .green)
            } else {
                Pill(text: "No token", systemImage: "minus.circle")
            }
        } content: {
            SettingsRow(
                "Access token",
                description: Text("Optional. Only gated models, which ask you to accept terms first, need one. [Create a token](https://huggingface.co/settings/tokens)")
            ) {
                if account.hasToken {
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

            SettingsRowDivider()
            Label("The token is stored in the macOS Keychain and sent only to huggingface.co.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Controls

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

    // MARK: - Actions

    private func save() {
        guard !trimmedInput.isEmpty else { return }
        do {
            try account.save(trimmedInput)
            tokenInput = ""
            errorMessage = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    private func remove() {
        do {
            try account.remove()
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
                verifiedName = try await account.verify()
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
