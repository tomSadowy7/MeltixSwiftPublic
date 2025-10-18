import SwiftUI

struct VerifyEmailView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss   // for manual dismissal if needed

    let email: String

    // UI state
    @State private var code           = ""
    @State private var errorMessage   : String? = nil
    @State private var isSubmitting   = false
    @State private var isResending    = false
    @State private var resendTimer    = 30      // seconds
    private  let resendInterval       = 30

    var body: some View {
        NavigationStack {
            ZStack {
                Color.jetBlack.ignoresSafeArea()

                VStack(spacing: 26) {
                    // ── Header
                    VStack(spacing: 6) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 46))
                            .foregroundColor(.gold)

                        Text("Verify Your Email")
                            .font(.title.bold())
                            .foregroundColor(.gold)

                        Text(email)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    // ── Code field
                    TextField("8-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(Color.charcoal)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gold.opacity(0.5), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                        .onChange(of: code) { newValue in
                            // allow only digits, max length 8
                            code = String(newValue.prefix(8).filter(\.isWholeNumber))
                        }

                    // ── Error
                    if let err = errorMessage {
                        Text(err)
                            .foregroundColor(.red)
                            .transition(.opacity)
                    }

                    // ── Buttons
                    VStack(spacing: 14) {
                        Button {
                            verifyCode()
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            } else {
                                Text("Verify")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(GoldButtonStyle())
                        .disabled(isSubmitting || code.count != 8)

                        Button("Resend Code") {
                            resendCode()
                        }
                        .disabled(isResending || resendTimer > 0)
                        .foregroundColor(.gold)
                        .opacity((isResending || resendTimer > 0) ? 0.5 : 1.0)

                        if resendTimer > 0 {
                            Text("You can resend in \(resendTimer)s")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
            .toolbar {
                // ── Logout (same style as other views)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") {
                        authManager.logout()
                        dismiss()
                    }
                    .foregroundColor(.gold)
                }
            }
        }
        .onAppear { startResendCountdown() }
    }

    // MARK: - Actions
    private func verifyCode() {
        guard code.count == 8 else { return }
        isSubmitting  = true
        errorMessage  = nil

        Task {
            let ok = await authManager.verifyEmail(email: email, code: code)
            await MainActor.run {
                isSubmitting = false
                if ok {
                    authManager.markVerified()      // flips flag → RootView navigates
                    dismiss()
                } else {
                    errorMessage = authManager.error ?? "Invalid code"
                }
            }
        }
    }

    private func resendCode() {
        isResending  = true
        errorMessage = nil

        Task {
            let ok = await authManager.resendVerificationCode()
            await MainActor.run {
                isResending = false
                if ok {
                    startResendCountdown()
                } else {
                    errorMessage = authManager.error ?? "Failed to resend"
                }
            }
        }
    }

    private func startResendCountdown() {
        resendTimer = resendInterval
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            resendTimer -= 1
            if resendTimer <= 0 { timer.invalidate() }
        }
    }
}
