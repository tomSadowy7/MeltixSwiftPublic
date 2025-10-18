//
//  ForgotAndVerifyView.swift
//  MeltixSwift
//

import SwiftUI

struct ForgotAndVerifyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject     private var auth: AuthManager
    
    // MARK: – Local state
    @State private var email    = ""
    @State private var code     = ""
    @State private var stage    : Stage = .enterEmail
    @State private var busy     = false
    @State private var resendCD = 0
    @State private var errorMsg : String?
    @State private var goReset  = false           // navigation trigger
    
    private enum Stage { case enterEmail, enterCode }
    
    // MARK: – Body
    var body: some View {
        NavigationStack {
            ZStack {
                Color.jetBlack.ignoresSafeArea()
                
                // Invisible nav-link → SetNewPasswordView
                NavigationLink(isActive: $goReset) {
                    SetNewPasswordView(email: email, code: code) {
                        dismiss()                    // back to LoginView
                    }
                    .environmentObject(auth)
                } label: { EmptyView() }
                .hidden()
                
                VStack(spacing: 26) {
                    header
                    ZStack {
                        form
                            .animation(.easeInOut, value: stage)
                    }
                    .frame(height: 60)
                    if let err = errorMsg { Text(err).errorText() }
                    actionSection
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gold)
                        .padding(.top, 4)
                }
                .padding()
            }
        }
    }
}

// MARK: – UI sections
private extension ForgotAndVerifyView {
    
    var header: some View {
        VStack(spacing: 8) {
            Image(systemName: stage == .enterEmail ? "envelope.badge" : "number.circle")
                .font(.system(size: 52))
                .foregroundColor(.gold)
                .shadow(radius: 4)
            Text(stage == .enterEmail ? "Forgot Password" : "Enter Reset Code")
                .font(.title.bold())
                .foregroundColor(.gold)
        }
    }
    
    var form: some View {
        ZStack {
            // Email input
            TextFieldRow(text: $email,
                         icon: "envelope",
                         placeholder: "Email",
                         keyboard: .emailAddress)
                .opacity(stage == .enterEmail ? 1 : 0)
                .allowsHitTesting(stage == .enterEmail)

            // Code input
            TextFieldRow(text: $code,
                         icon: "number",
                         placeholder: "8-digit code",
                         keyboard: .numberPad)
                .onChange(of: code) { if $0.count > 8 { code = String($0.prefix(8)) } }
                .opacity(stage == .enterCode ? 1 : 0)
                .allowsHitTesting(stage == .enterCode)
        }
        .animation(.easeInOut, value: stage)
        .frame(height: 60) // fixed height to prevent vertical shifts
    }
    @ViewBuilder var actionSection: some View {
        if stage == .enterEmail {
            roundedButton(title: "Send Reset Code") {
                Task { await sendEmail() }
            }
        } else {
            VStack(spacing: 14) {
                roundedButton(title: "Verify Code") {
                    Task { await verifyCode() }
                }

                // ── Resend (identical UX to VerifyEmailView) ──
                Button("Resend Code") { Task { await sendEmail() } }
                    .disabled(busy || resendCD > 0)
                    .foregroundColor(.gold)
                    .opacity((busy || resendCD > 0) ? 0.5 : 1)

                if resendCD > 0 {
                    Text("You can resend in \(resendCD)s")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .transition(.opacity)
        }
    }
    
    // Common rounded button
    @ViewBuilder
    func roundedButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if busy {
                ProgressView().tint(.black)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(busy)
    }
    
    var resendLabel: String {
        resendCD > 0 ? "Resend Email (\(resendCD))" : "Resend Email"
    }
}

// MARK: – Networking helpers
private extension ForgotAndVerifyView {
    
    /// 1️⃣  Sends /auth/forgot-password
    @MainActor func sendEmail() async {
        errorMsg = nil
        guard email.isValidEmail else { errorMsg = "Enter a valid e-mail"; return }
        
        busy = true
        defer { busy = false }
        
        do {
            let ok = try await auth.sendForgotPassword(email: email)
            if ok {
                withAnimation { stage = .enterCode }
                startCooldown()
            } else {
                errorMsg = "Failed to send e-mail"
            }
        } catch {
            errorMsg = "Network error"
        }
    }
    
    /// 2️⃣  Calls /auth/verify-reset-code then navigates
    @MainActor func verifyCode() async {
        errorMsg = nil
        guard !code.isEmpty else { errorMsg = "Enter the code"; return }
        
        busy = true
        defer { busy = false }
        
        let ok = await auth.verifyResetCode(email: email, code: code)
        if ok { goReset = true } else { errorMsg = "Invalid or expired code" }
    }
    
    func startCooldown() {
        resendCD = 30
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            resendCD -= 1
            if resendCD <= 0 { t.invalidate() }
        }
    }
}

// MARK: – Small UI bits
private struct TextFieldRow: View {
    @Binding var text : String
    let icon, placeholder: String
    var keyboard : UIKeyboardType = .default
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gold)
                .frame(width: 22)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .fieldFrame()
    }
}

private extension View {
    func fieldFrame(height: CGFloat = 48) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .background(Color.charcoal)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gold.opacity(0.35), lineWidth: 1)
            )
            .foregroundColor(.white)
    }
    func errorText() -> some View {
        self.font(.callout)
            .multilineTextAlignment(.center)
            .foregroundColor(.red)
            .padding(.horizontal, 4)
    }
}
