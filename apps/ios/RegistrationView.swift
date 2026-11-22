import SwiftUI
import PhotosUI
import UIKit

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
    @State private var nickname = ""
    @State private var avatarGeneration = 0
    @State private var avatarPhoto: UIImage?
    @State private var avatarPhotoItem: PhotosPickerItem?
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
                    if mode == .register {
                        AuthInputRow(icon: "person", title: "昵称") {
                            TextField("给自己起个名字", text: $nickname)
                                .textContentType(.nickname)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                                .onChange(of: nickname) { _, value in
                                    if value.count > 20 { nickname = String(value.prefix(20)) }
                                }
                        }
                        avatarPicker
                    }
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
        .onChange(of: avatarPhotoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = "读取头像失败，请重新选择图片。"
                    return
                }
                avatarPhoto = image
                errorMessage = nil
            }
        }
    }

    private var canSubmit: Bool {
        validEmail(email) && code.count == 6 && password.count >= 8 && password.count <= 128
            && (mode == .reset || (password == confirmation && !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            && !submitting && !sending
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RegistrationAvatar(seed: avatarSeed, photo: avatarPhoto)
                    .frame(width: 104, height: 116)
                    .accessibilityLabel(avatarPhoto == nil ? "昵称生成的手绘头像" : "已选择的头像")
                VStack(alignment: .leading, spacing: 7) {
                    Text("为\(avatarDisplayName)制作专属头像")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(avatarPhoto == nil ? "点选喜欢的手绘形象" : "已使用你上传的照片")
                        .font(.caption).foregroundStyle(BrandTheme.ink.opacity(0.62))
                    HStack(spacing: 14) {
                        Button {
                            avatarPhoto = nil
                            avatarPhotoItem = nil
                            avatarGeneration += 1
                        } label: { Label("换一个", systemImage: "sparkles") }
                        PhotosPicker(selection: $avatarPhotoItem, matching: .images) {
                            Label("上传照片", systemImage: "photo")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(BrandTheme.pine)
                    .labelStyle(.titleAndIcon)
                }
            }

        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.black.opacity(0.08), lineWidth: 1) }
    }

    private var avatarSeed: String {
        "\(avatarDisplayName)-\(avatarGeneration)"
    }

    private var avatarDisplayName: String {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "旅行者" : name
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
                try await session.register(
                    email: address,
                    code: code,
                    password: password,
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarSeed: avatarSeed,
                    avatarPhoto: avatarPhoto
                )
            } else {
                try await session.resetPassword(email: address, code: code, password: password)
                onPasswordReset(address)
                dismiss()
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RegistrationAvatar: View {
    let seed: String
    let photo: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.94, green: 0.88, blue: 0.78))
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Canvas { context, size in
                    var canvas = context
                    canvas.scaleBy(x: size.width / 256, y: size.height / 320)
                    let design = AvatarDesign(seed: seed)
                    var brush = AvatarRandom(seed: seed + ":brush")
                    SketchyAvatarPainter.draw(design, in: &canvas, random: &brush)
                }
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .shadow(color: BrandTheme.pine.opacity(0.15), radius: 8, y: 3)
    }
}

private enum AvatarSpecies { case human, cat, dog, odd }
private enum AvatarHair { case messy, spiky, antennae, horns, bald }
private enum AvatarEyes { case round, dot, sleepy, glasses, hollow, many, angry }
private enum AvatarMouth { case smile, flat, open, teeth, cat, jagged }
private enum AvatarNose { case curve, button, big, triangle, snout }
private enum AvatarEars { case human, cat, dog, pointed }
private enum AvatarAccessory { case none, glasses, earrings, flower }

private struct AvatarDesign {
    let species: AvatarSpecies
    let hair: AvatarHair
    let eyes: AvatarEyes
    let mouth: AvatarMouth
    let nose: AvatarNose
    let ears: AvatarEars
    let accessory: AvatarAccessory
    let skin: Color
    let hairColor: Color
    let accent: Color
    let shirt: Color
    let paper: Color
    let bodyDetail: Int
    let faceWidth: CGFloat
    let faceHeight: CGFloat

    init(seed: String) {
        var rng = AvatarRandom(seed: seed)
        species = rng.pick([.human, .human, .cat, .dog, .human, .cat, .dog, .odd])
        let odd = species == .odd
        ears = odd ? rng.pick([.pointed, .cat, .human]) : (species == .cat ? .cat : (species == .dog ? .dog : .human))
        hair = odd ? rng.pick([.horns, .antennae, .messy, .spiky]) : rng.pick([.messy, .antennae, .spiky, .bald, .messy])
        eyes = odd ? rng.pick([.hollow, .many, .angry, .round]) : (species == .human ? rng.pick([.round, .round, .dot, .sleepy, .glasses]) : rng.pick([.round, .dot, .sleepy]))
        mouth = odd ? rng.pick([.jagged, .teeth, .open]) : (species == .cat ? rng.pick([.cat, .smile, .flat]) : (species == .human ? rng.pick([.smile, .smile, .open, .flat]) : rng.pick([.smile, .open, .flat])))
        nose = odd ? rng.pick([.curve, .triangle, .button]) : (species == .cat ? .triangle : (species == .dog ? .snout : rng.pick([.curve, .button, .big])))
        var accessories: [AvatarAccessory] = [.none, .none]
        if eyes != .glasses { accessories.append(.glasses) }
        if ears == .human { accessories.append(.earrings) }
        if ears == .cat || ears == .pointed { accessories.append(.flower) }
        accessory = rng.pick(accessories)
        skin = rng.pick([
            Color(red: 0.94, green: 0.79, blue: 0.64), Color(red: 0.84, green: 0.61, blue: 0.46),
            Color(red: 0.97, green: 0.86, blue: 0.72), Color(red: 0.89, green: 0.69, blue: 0.53),
        ])
        hairColor = rng.pick([
            Color(red: 0.18, green: 0.15, blue: 0.14), Color(red: 0.35, green: 0.23, blue: 0.17),
            Color(red: 0.14, green: 0.20, blue: 0.18), Color(red: 0.48, green: 0.32, blue: 0.21),
        ])
        accent = rng.pick([
            Color(red: 0.67, green: 0.28, blue: 0.23), Color(red: 0.25, green: 0.43, blue: 0.55),
            Color(red: 0.43, green: 0.49, blue: 0.24), Color(red: 0.66, green: 0.45, blue: 0.18),
            BrandTheme.jade, Color(red: 0.48, green: 0.34, blue: 0.52),
        ])
        shirt = rng.pick([BrandTheme.pine, BrandTheme.jade, accent, Color(red: 0.69, green: 0.42, blue: 0.28)])
        paper = rng.pick([
            Color(red: 0.95, green: 0.89, blue: 0.77), Color(red: 0.87, green: 0.91, blue: 0.82),
            Color(red: 0.92, green: 0.85, blue: 0.79), Color(red: 0.84, green: 0.89, blue: 0.92),
        ])
        bodyDetail = rng.int(0..<4)
        faceWidth = 0.94 + rng.value * 0.12
        faceHeight = 0.94 + rng.value * 0.12
    }
}

private struct AvatarRandom {
    private var state: UInt32
    init(seed: String) { state = seed.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 } }
    var value: CGFloat {
        mutating get {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return CGFloat(t ^ (t >> 14)) / CGFloat(UInt32.max)
        }
    }
    mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(value * CGFloat(range.count)) }
    mutating func pick<T>(_ values: [T]) -> T { values[min(values.count - 1, Int(value * CGFloat(values.count)))] }
    mutating func jitter(_ magnitude: CGFloat) -> CGFloat { (value - 0.5) * 2 * magnitude }
}

private enum SketchyAvatarPainter {
    private static let ink = Color(red: 0.17, green: 0.16, blue: 0.14)
    private static let rose = Color(red: 0.75, green: 0.34, blue: 0.29)

    static func draw(_ d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        let cx: CGFloat = 128
        // Ground stroke and torso establish the same full-body hand-drawn composition as the demo.
        stroke((0...16).map { CGPoint(x: CGFloat($0) * 16, y: 284 + rng.jitter(2)) }, in: &ctx, color: ink.opacity(0.28), width: 2, random: &rng)
        ellipse(cx: cx, cy: 286, rx: 85, ry: 91, fill: d.shirt, stroke: ink, in: &ctx, random: &rng)
        switch d.bodyDetail {
        case 0:
            for y in [258.0, 279.0, 300.0] { blob(cx: cx, cy: y, rx: 3, ry: 3, fill: ink, in: &ctx, random: &rng) }
        case 1:
            for y in [263.0, 283.0, 303.0] { stroke([CGPoint(x: 67, y: y), CGPoint(x: 189, y: y + 2)], in: &ctx, color: d.accent.opacity(0.8), width: 5, random: &rng) }
        case 2:
            ellipse(cx: cx, cy: 295, rx: 39, ry: 35, fill: d.paper.opacity(0.85), stroke: ink.opacity(0.55), in: &ctx, random: &rng)
        default: break
        }

        drawEar(d.ears, side: -1, d: d, in: &ctx, random: &rng)
        drawEar(d.ears, side: 1, d: d, in: &ctx, random: &rng)
        let rx = 69 * d.faceWidth, ry = 91 * d.faceHeight
        ellipse(cx: cx, cy: 153, rx: rx, ry: ry, fill: d.skin, stroke: ink, in: &ctx, random: &rng)
        if d.species != .odd {
            blob(cx: cx - rx * 0.57, cy: 177, rx: 12, ry: 6, fill: rose.opacity(0.22), in: &ctx, random: &rng)
            blob(cx: cx + rx * 0.57, cy: 177, rx: 12, ry: 6, fill: rose.opacity(0.22), in: &ctx, random: &rng)
        }
        drawHair(d.hair, d: d, in: &ctx, random: &rng)
        drawEyes(d.eyes, d: d, in: &ctx, random: &rng)
        drawNose(d.nose, d: d, in: &ctx, random: &rng)
        drawMouth(d.mouth, d: d, in: &ctx, random: &rng)
        if d.accessory == .glasses || d.eyes == .glasses { drawGlasses(in: &ctx, random: &rng) }
        if d.accessory == .earrings && d.ears == .human {
            for x in [48.0, 208.0] { ellipse(cx: x, cy: 194, rx: 5, ry: 7, fill: d.accent, stroke: ink, in: &ctx, random: &rng) }
        }
    }

    private static func drawEar(_ type: AvatarEars, side: CGFloat, d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        switch type {
        case .human:
            ellipse(cx: 58 * side + 128, cy: 158, rx: 17, ry: 23, fill: d.skin, stroke: ink, in: &ctx, random: &rng)
            stroke([CGPoint(x: 128 + side * 56, y: 150), CGPoint(x: 128 + side * 66, y: 159), CGPoint(x: 128 + side * 57, y: 169)], in: &ctx, color: rose.opacity(0.7), width: 2, random: &rng)
        case .dog:
            ellipse(cx: 128 + side * 69, cy: 161, rx: 19, ry: 39, fill: d.hairColor.opacity(0.92), stroke: ink, in: &ctx, random: &rng)
        case .cat, .pointed:
            let x = 128 + side * 53
            let top: CGFloat = type == .cat ? 68 : 82
            polygon([CGPoint(x: x - 27, y: 144), CGPoint(x: x + side * 5, y: top), CGPoint(x: x + side * 31, y: 145)], fill: d.skin, stroke: ink, in: &ctx, random: &rng)
            polygon([CGPoint(x: x - 13, y: 135), CGPoint(x: x + side * 5, y: top + 24), CGPoint(x: x + side * 17, y: 136)], fill: rose.opacity(0.58), stroke: nil, in: &ctx, random: &rng)
            if d.accessory == .flower && side < 0 {
                for i in 0..<5 {
                    let a = CGFloat(i) * .pi * 2 / 5
                    blob(cx: x - 17 + cos(a) * 7, cy: 135 + sin(a) * 7, rx: 5, ry: 5, fill: rose, in: &ctx, random: &rng)
                }
            }
        }
    }

    private static func drawHair(_ hair: AvatarHair, d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        switch hair {
        case .messy:
            var pts: [CGPoint] = []
            for i in 0...10 {
                let x = CGFloat(57 + i * 14)
                let peak = (i.isMultiple(of: 2) ? 102.0 : 63.0) + rng.jitter(10)
                pts.append(CGPoint(x: x, y: peak))
            }
            pts.append(contentsOf: [CGPoint(x: 202, y: 129), CGPoint(x: 186, y: 113), CGPoint(x: 166, y: 121), CGPoint(x: 145, y: 111), CGPoint(x: 120, y: 124), CGPoint(x: 93, y: 113), CGPoint(x: 67, y: 132)])
            polygon(pts, fill: d.hairColor, stroke: ink, in: &ctx, random: &rng)
        case .spiky:
            var pts = [CGPoint(x: 56, y: 125)]
            for i in 0...8 { pts.append(CGPoint(x: 60 + i * 17, y: i.isMultiple(of: 2) ? 103 : 63)) }
            pts.append(contentsOf: [CGPoint(x: 202, y: 133), CGPoint(x: 187, y: 114), CGPoint(x: 160, y: 123), CGPoint(x: 135, y: 111), CGPoint(x: 111, y: 123), CGPoint(x: 84, y: 112)])
            polygon(pts, fill: d.hairColor, stroke: ink, in: &ctx, random: &rng)
        case .antennae, .horns:
            for side: CGFloat in [-1, 1] {
                let from = CGPoint(x: 128 + side * 26, y: 99)
                let tip = CGPoint(x: 128 + side * (hair == .horns ? 52 : 60), y: 44 + rng.jitter(8))
                stroke([from, CGPoint(x: (from.x + tip.x) / 2, y: 71), tip], in: &ctx, color: d.hairColor, width: hair == .horns ? 8 : 4, random: &rng)
                if hair == .antennae { blob(cx: tip.x, cy: tip.y, rx: 8, ry: 8, fill: d.accent, in: &ctx, random: &rng) }
            }
            stroke([CGPoint(x: 62, y: 128), CGPoint(x: 80, y: 103), CGPoint(x: 104, y: 117), CGPoint(x: 127, y: 105), CGPoint(x: 151, y: 116), CGPoint(x: 177, y: 102), CGPoint(x: 195, y: 130)], in: &ctx, color: d.hairColor, width: 13, random: &rng)
        case .bald:
            stroke([CGPoint(x: 67, y: 119), CGPoint(x: 82, y: 91), CGPoint(x: 106, y: 79), CGPoint(x: 128, y: 76), CGPoint(x: 151, y: 79), CGPoint(x: 176, y: 92), CGPoint(x: 190, y: 119)], in: &ctx, color: d.hairColor, width: 5, random: &rng)
        }
    }

    private static func drawEyes(_ eyes: AvatarEyes, d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        let positions: [CGFloat] = eyes == .many ? [78, 128, 178] : [94, 162]
        for (i, x) in positions.enumerated() {
            let scale: CGFloat = eyes == .many && i == 1 ? 1.35 : 1
            if eyes == .sleepy {
                stroke([CGPoint(x: x - 11, y: 153), CGPoint(x: x, y: 148), CGPoint(x: x + 11, y: 153)], in: &ctx, color: ink, width: 4, random: &rng)
            } else if eyes == .dot || eyes == .angry {
                blob(cx: x, cy: 151, rx: 5 * scale, ry: 7 * scale, fill: ink, in: &ctx, random: &rng)
            } else {
                ellipse(cx: x, cy: 151, rx: 10 * scale, ry: 12 * scale, fill: eyes == .hollow ? ink : .white.opacity(0.7), stroke: ink, in: &ctx, random: &rng)
                blob(cx: x + 1, cy: 152, rx: eyes == .hollow ? 4 : 4.5, ry: 6, fill: eyes == .hollow ? d.paper : ink, in: &ctx, random: &rng)
                if eyes != .hollow { blob(cx: x + 2, cy: 149, rx: 1.8, ry: 2, fill: .white, in: &ctx, random: &rng) }
            }
            if eyes == .angry {
                let slant: CGFloat = i == 0 ? 1 : -1
                stroke([CGPoint(x: x - 12 * slant, y: 136), CGPoint(x: x + 11 * slant, y: 142)], in: &ctx, color: ink, width: 4, random: &rng)
            }
        }
    }

    private static func drawNose(_ nose: AvatarNose, d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        switch nose {
        case .curve:
            stroke([CGPoint(x: 129, y: 157), CGPoint(x: 135, y: 169), CGPoint(x: 126, y: 173)], in: &ctx, color: ink, width: 2.8, random: &rng)
        case .button:
            ellipse(cx: 128, cy: 168, rx: 5, ry: 4, fill: d.skin, stroke: ink, in: &ctx, random: &rng)
        case .big:
            ellipse(cx: 128, cy: 168, rx: 10, ry: 7, fill: rose.opacity(0.55), stroke: ink, in: &ctx, random: &rng)
        case .triangle:
            polygon([CGPoint(x: 122, y: 164), CGPoint(x: 134, y: 164), CGPoint(x: 128, y: 171)], fill: rose, stroke: ink, in: &ctx, random: &rng)
            for side: CGFloat in [-1, 1] { for i in 0..<2 { stroke([CGPoint(x: 128 + side * 12, y: 171 + CGFloat(i) * 4), CGPoint(x: 128 + side * 30, y: 166 + CGFloat(i) * 7)], in: &ctx, color: ink.opacity(0.65), width: 1.4, random: &rng) } }
        case .snout:
            ellipse(cx: 128, cy: 167, rx: 17, ry: 12, fill: Color(red: 0.95, green: 0.87, blue: 0.76), stroke: ink, in: &ctx, random: &rng)
            blob(cx: 128, cy: 162, rx: 5, ry: 4, fill: ink, in: &ctx, random: &rng)
        }
    }

    private static func drawMouth(_ mouth: AvatarMouth, d: AvatarDesign, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        switch mouth {
        case .smile:
            stroke([CGPoint(x: 116, y: 190), CGPoint(x: 122, y: 198), CGPoint(x: 130, y: 200), CGPoint(x: 138, y: 197), CGPoint(x: 142, y: 190)], in: &ctx, color: ink, width: 3, random: &rng)
        case .flat:
            stroke([CGPoint(x: 117, y: 193), CGPoint(x: 140, y: 194)], in: &ctx, color: ink, width: 3, random: &rng)
        case .open:
            ellipse(cx: 129, cy: 194, rx: 7, ry: 10, fill: rose.opacity(0.72), stroke: ink, in: &ctx, random: &rng)
        case .teeth:
            ellipse(cx: 129, cy: 193, rx: 12, ry: 8, fill: .white, stroke: ink, in: &ctx, random: &rng)
            stroke([CGPoint(x: 117, y: 193), CGPoint(x: 141, y: 193)], in: &ctx, color: ink, width: 1.6, random: &rng)
        case .cat:
            stroke([CGPoint(x: 116, y: 191), CGPoint(x: 122, y: 195), CGPoint(x: 128, y: 191), CGPoint(x: 134, y: 195), CGPoint(x: 141, y: 191)], in: &ctx, color: ink, width: 2.5, random: &rng)
        case .jagged:
            stroke((0...8).map { CGPoint(x: 115 + CGFloat($0) * 3.5, y: $0.isMultiple(of: 2) ? 190 : 199) }, in: &ctx, color: ink, width: 3, random: &rng)
        }
    }

    private static func drawGlasses(in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        for x: CGFloat in [94, 162] { ellipse(cx: x, cy: 151, rx: 17, ry: 17, fill: .clear, stroke: ink, in: &ctx, random: &rng, width: 2.2) }
        stroke([CGPoint(x: 111, y: 150), CGPoint(x: 145, y: 150)], in: &ctx, color: ink, width: 2, random: &rng)
    }

    private static func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, fill: Color, stroke color: Color?, in ctx: inout GraphicsContext, random rng: inout AvatarRandom, width: CGFloat = 2.2) {
        let points = (0...28).map { i -> CGPoint in
            let a = CGFloat(i) * .pi * 2 / 28
            let wobble = i.isMultiple(of: 2) ? 1 + rng.jitter(0.035) : 1
            return CGPoint(x: cx + cos(a) * rx * wobble, y: cy + sin(a) * ry * wobble)
        }
        polygon(points, fill: fill, stroke: color, in: &ctx, random: &rng, width: width)
    }

    private static func blob(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, fill: Color, in ctx: inout GraphicsContext, random rng: inout AvatarRandom) {
        ellipse(cx: cx, cy: cy, rx: rx, ry: ry, fill: fill, stroke: nil, in: &ctx, random: &rng)
    }

    private static func polygon(_ points: [CGPoint], fill: Color, stroke color: Color?, in ctx: inout GraphicsContext, random rng: inout AvatarRandom, width: CGFloat = 2.2) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        ctx.fill(path, with: .color(fill))
        if let color { strokePath(path, in: &ctx, color: color, width: width, random: &rng) }
    }

    private static func stroke(_ points: [CGPoint], in ctx: inout GraphicsContext, color: Color, width: CGFloat, random rng: inout AvatarRandom) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: CGPoint(x: first.x + rng.jitter(1.3), y: first.y + rng.jitter(1.3)))
        for point in points.dropFirst() {
            path.addQuadCurve(to: CGPoint(x: point.x + rng.jitter(1.3), y: point.y + rng.jitter(1.3)),
                              control: CGPoint(x: point.x + rng.jitter(2.2), y: point.y + rng.jitter(2.2)))
        }
        strokePath(path, in: &ctx, color: color, width: width, random: &rng)
    }

    private static func strokePath(_ path: Path, in ctx: inout GraphicsContext, color: Color, width: CGFloat, random rng: inout AvatarRandom) {
        var style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        style.lineWidth = max(1, width * (0.78 + rng.value * 0.36))
        ctx.stroke(path, with: .color(color.opacity(0.9)), style: style)
        ctx.stroke(path, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: style.lineWidth * 0.55, lineCap: .round, lineJoin: .round))
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
