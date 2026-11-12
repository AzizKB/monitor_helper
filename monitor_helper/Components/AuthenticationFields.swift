import SwiftUI

struct AuthenticationPasswordField: View {
    let title: String
    @Binding var text: String
    var isNewPassword = false
    var submitLabel: SubmitLabel = .go
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.medium)
            HStack(spacing: 0) {
                Group {
                    if isVisible { TextField(title, text: $text) }
                    else { SecureField(title, text: $text) }
                }
                .textContentType(isNewPassword ? .newPassword : .password)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused(focus).submitLabel(submitLabel).onSubmit(onSubmit)
                .padding(.leading, 12).accessibilityLabel(title)
                Button { isVisible.toggle(); focus.wrappedValue = true } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                .accessibilityLabel("\(isVisible ? "Hide" : "Show") \(title.lowercased())")
            }
            .frame(minHeight: 48)
            .background(AppTheme.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25)))
        }
        .privacySensitive()
        .onChange(of: scenePhase) { _, phase in if phase != .active { isVisible = false } }
        .onChange(of: isNewPassword) { isVisible = false }
    }
}

struct NewPasswordGuidance: View {
    let password: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("At least 12 characters", systemImage: password.count >= 12 ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(password.count >= 12 ? Color.green : Color.secondary)
            Label("Uppercase and lowercase letters", systemImage: AuthenticationInput.hasBothLetterCases(password) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(AuthenticationInput.hasBothLetterCases(password) ? Color.green : Color.secondary)
            Label("A number and a symbol (such as !)", systemImage: AuthenticationInput.hasNumberAndSymbol(password) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(AuthenticationInput.hasNumberAndSymbol(password) ? Color.green : Color.secondary)
            if password.utf8.count > AuthenticationInput.maximumPasswordBytes {
                Text("This password is too long. Use at most 72 bytes; some characters use more than one.").foregroundStyle(.red)
            } else if !password.isEmpty {
                Text(password.count >= 16 ? "Good length. Make sure this password is unique." : "A unique phrase of 16 or more characters is even better.").foregroundStyle(.secondary)
            }
            Text("Use a unique password or let your password manager create one. Spaces and passphrases are welcome.").foregroundStyle(.secondary)
        }
        .font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}

struct AuthenticationNotice: View {
    let message: String
    var isError = true
    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.subheadline).foregroundStyle(isError ? Color.red : Color.green)
            .fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}
