import SwiftUI

private enum AuthMode: String, Identifiable {
    case register, reset
    var id: String { rawValue }
    var title: String { self == .register ? "创建账号" : "找回密码" }
}

struct RegistrationView: View {
    @Environment(AccountSession.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var passwordVisible = false
    @State private var sheet: AuthMode?
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case email, password }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    hero(compact: geometry.size.height < 760)
                    loginCard
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background { background }
        .preferredColorScheme(.light)
        .sheet(item: $sheet) { mode in
            AuthFormSheet(mode: mode, initialEmail: email) { restoredEmail in
                email = restoredEmail
                password = ""
                successMessage = "密码已重置，请使用新密码登录。"
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }

    private var background: some View {
        BrandTheme.rice
            .overlay { Image("LoginLandscape").resizable().scaledToFill() }
            .overlay {
                LinearGradient(
                    colors: [BrandTheme.pineDeep.opacity(0.68), BrandTheme.pineDeep.opacity(0.12), .black.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .ignoresSafeArea()
    }

    private func hero(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 15) {
            HStack(spacing: 11) {
                Image("BrandMark")
                    .resizable().scaledToFit().padding(6)
                    .frame(width: 45, height: 45)
                    .background(BrandTheme.rice.opacity(0.94), in: RoundedRectangle(cornerRadius: 13))
                Text("知行")
                    .font(.custom("NotoSerifSC-Bold", size: 28, relativeTo: .title))
            }
            if focusedField == nil {
                Text("知一方风土\n行万里山河")
                    .font(.custom("NotoSerifSC-Medium", size: compact ? 35 : 43, relativeTo: .largeTitle))
                    .lineSpacing(3).multilineTextAlignment(.center)
                Text("一张有故事的中国地图")
                    .font(.custom("NotoSerifSC-Medium", size: 15, relativeTo: .subheadline))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("欢迎回来")
                    .font(.custom("NotoSerifSC-Bold", size: 23, relativeTo: .title2))
                Text("使用邮箱和密码登录知行。")
                    .font(.subheadline).foregroundStyle(BrandTheme.ink.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 0) {
                Text("登录")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 37)
                    .background(BrandTheme.pine, in: RoundedRectangle(cornerRadius: 9))
                Button("注册") { present(.register) }
                    .frame(maxWidth: .infinity, minHeight: 37)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BrandTheme.pine)
            .buttonStyle(.plain)
            .padding(4)
            .background(BrandTheme.pine.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            AuthInputRow(icon: "envelope", title: "邮箱地址") {
                TextField("name@example.com", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            AuthInputRow(icon: "lock", title: "密码") {
                Group {
                    if passwordVisible { TextField("密码", text: $password) }
                    else { SecureField("密码", text: $password) }
                }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSignIn { Task { await signIn() } } }
                PasswordVisibilityButton(visible: $passwordVisible)
            }
            AuthAction(title: "登录知行", busy: isSigningIn, enabled: canSignIn) {
                Task { await signIn() }
            }
            Button("忘记密码？") { present(.reset) }
                .font(.subheadline.weight(.medium)).foregroundStyle(BrandTheme.pine)
                .frame(maxWidth: .infinity)
            AuthMessages(error: errorMessage, success: successMessage)
        }
        .foregroundStyle(BrandTheme.ink)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.78), lineWidth: 1) }
        .shadow(color: BrandTheme.pineDeep.opacity(0.24), radius: 30, y: 16)
    }

    private var canSignIn: Bool { validEmail(email) && !password.isEmpty && !isSigningIn }

    private func present(_ mode: AuthMode) {
        focusedField = nil
        errorMessage = nil
        successMessage = nil
        sheet = mode
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do { try await session.signIn(email: normalizedEmail(email), password: password) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AuthFormSheet: View {
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let mode: AuthMode
    let onPasswordReset: (String) -> Void
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var passwordVisible = false
    @State private var confirmationVisible = false
    @State private var sending = false
    @State private var submitting = false
    @State private var resendAfter = Date.distantPast
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var focusedField: Field?
    private enum Field { case email, code, password, confirmation }

    init(mode: AuthMode, initialEmail: String, onPasswordReset: @escaping (String) -> Void) {
        self.mode = mode
        self.onPasswordReset = onPasswordReset
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode.title)
                    .font(.custom("NotoSerifSC-Bold", size: 26, relativeTo: .title2))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(BrandTheme.pine.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(mode == .register ? "验证邮箱，设置密码，开启知行之旅。" : "通过注册邮箱验证码，设置新的登录密码。")
                        .font(.subheadline).foregroundStyle(BrandTheme.ink.opacity(0.62))
                    AuthInputRow(icon: "envelope", title: "邮箱地址") {
                        TextField("name@example.com", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next).onSubmit { focusedField = .code }
                    }
                    AuthInputRow(icon: "number", title: "邮箱验证码") {
                        TextField("6 位数字", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .code)
                            .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(resendAfter.timeIntervalSince(context.date).rounded(.up)))
                            Button { Task { await sendCode() } } label: {
                                if sending { ProgressView().controlSize(.small) }
                                else { Text(seconds > 0 ? "\(seconds) 秒后重发" : "获取验证码").font(.caption.weight(.semibold)) }
                            }
                            .disabled(sending || submitting || seconds > 0 || !validEmail(email))
                        }
                    }
                    AuthInputRow(icon: "lock", title: mode == .register ? "设置密码" : "新密码") {
                        Group {
                            if passwordVisible { TextField("至少 8 位", text: $password) }
                            else { SecureField("至少 8 位", text: $password) }
                        }
                            .textContentType(.newPassword).focused($focusedField, equals: .password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(mode == .register ? .next : .done)
                            .onSubmit { if mode == .register { focusedField = .confirmation } }
                        PasswordVisibilityButton(visible: $passwordVisible)
                    }
                    if mode == .register {
                        AuthInputRow(icon: "lock.fill", title: "确认密码") {
                            Group {
                                if confirmationVisible { TextField("再次输入密码", text: $confirmation) }
                                else { SecureField("再次输入密码", text: $confirmation) }
                            }
                                .textContentType(.newPassword).focused($focusedField, equals: .confirmation)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit { if canSubmit { Task { await submit() } } }
                            PasswordVisibilityButton(visible: $confirmationVisible)
                        }
                    }
                    AuthMessages(error: errorMessage, success: successMessage)
                    AuthAction(title: mode == .register ? "注册并进入知行" : "重置密码", busy: submitting, enabled: canSubmit) {
                        Task { await submit() }
                    }
                    Text(mode == .register ? "验证码 10 分钟内有效，请勿向他人透露。" : "如果邮箱已注册，验证码会发送到该邮箱。")
                        .font(.caption).foregroundStyle(BrandTheme.ink.opacity(0.58))
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 460).frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(BrandTheme.ink).tint(BrandTheme.pine)
        .background(BrandTheme.rice.ignoresSafeArea())
        .interactiveDismissDisabled(submitting || sending)
        .disabled(submitting)
    }

    private var canSubmit: Bool {
        validEmail(email) && code.count == 6 && password.count >= 8 && password.count <= 128
            && (mode == .reset || password == confirmation) && !submitting && !sending
    }

    private func sendCode() async {
        sending = true
        let address = normalizedEmail(email)
        errorMessage = nil
        successMessage = nil
        defer { sending = false }
        do {
            if mode == .reset { try await session.sendPasswordResetCode(email: address) }
            else { try await session.sendRegistrationCode(email: address) }
            resendAfter = .now.addingTimeInterval(60)
            successMessage = mode == .reset ? "如邮箱已注册，请查收密码重置验证码。" : "验证码已发送，请查收邮件。"
            focusedField = .code
        } catch {
            if case APIError.badResponse(500) = error {
                errorMessage = "验证码邮件发送失败，请稍后重试。"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        focusedField = nil
        let address = normalizedEmail(email)
        defer { submitting = false }
        do {
            if mode == .register {
                try await session.register(email: address, code: code, password: password)
            } else {
                try await session.resetPassword(email: address, code: code, password: password)
                onPasswordReset(address)
                dismiss()
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct PasswordVisibilityButton: View {
    @Binding var visible: Bool
    var body: some View {
        Button { visible.toggle() } label: {
            Image(systemName: visible ? "eye.slash" : "eye")
                .foregroundStyle(BrandTheme.pine)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(visible ? "隐藏密码" : "显示密码")
    }
}

private struct AuthInputRow<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(BrandTheme.ink.opacity(0.68))
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(BrandTheme.jade).frame(width: 18).accessibilityHidden(true)
                content.font(.body).tint(BrandTheme.pine)
            }
            .padding(.horizontal, 13).frame(minHeight: 49)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(.black.opacity(0.10), lineWidth: 1) }
        }
    }
}

private struct AuthAction: View {
    let title: String
    let busy: Bool
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy { ProgressView().tint(.white).controlSize(.small) }
                Text(busy ? "请稍候…" : title)
                if !busy { Image(systemName: "arrow.right") }
            }
            .font(.body.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(BrandTheme.pine, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!enabled).opacity(enabled ? 1 : 0.62)
    }
}

private struct AuthMessages: View {
    let error: String?
    let success: String?
    var body: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium)).foregroundStyle(BrandTheme.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let success {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium)).foregroundStyle(BrandTheme.pine)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func normalizedEmail(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func validEmail(_ email: String) -> Bool {
    normalizedEmail(email).wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
}
