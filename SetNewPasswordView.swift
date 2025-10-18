//
//  SetNewPasswordView.swift
//  MeltixSwift
//

import SwiftUI

struct SetNewPasswordView: View {
    @Environment(\.dismiss) private var dismissSheet          // closes NavStack
    @EnvironmentObject     private var auth : AuthManager

    // provided by previous screen
    let email : String
    let code  : String
    let onFinish : () -> Void        // called after success → closes sheet

    // local UI state
    @State private var newPW    = ""
    @State private var isBusy   = false
    @State private var errorMsg : String?
    @State private var showDone = false

    var body: some View {
        ZStack {
            Color.jetBlack.ignoresSafeArea()

            VStack(spacing: 28) {
                header

                SecureFieldRow(text: $newPW,
                               icon: "lock",
                               placeholder: "New password (min 6)")
                    .padding(.top, 6)

                if let err = errorMsg { Text(err).errorText() }

                Button(action: reset) {
                    if isBusy {
                        ProgressView().tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Reset Password")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(newPW.count < 6 || isBusy)

                Button("Cancel") { dismissSheet() }
                    .foregroundColor(.gold)
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)        // ← hides default “Back”
        .toast(isPresented: $showDone) {            // lightweight in-view toast
            Text("Password reset!")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color.gold)
                .cornerRadius(16)
                .shadow(radius: 6)
        }
    }

    // MARK: – Sections
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 54))
                .foregroundColor(.gold)
                .shadow(radius: 4)
            Text("Set New Password")
                .font(.title.bold())
                .foregroundColor(.gold)
        }
    }

    // MARK: – Networking
    @MainActor private func reset() {
        guard newPW.count >= 6 else {
            errorMsg = "Password too short"
            return
        }
        isBusy = true ; errorMsg = nil

        Task {
            do {
                let ok = try await auth.submitResetPassword(email: email,
                                                            code: code,
                                                            newPassword: newPW)
                if ok {
                    showDone = true                     // show toast
                    // auto-dismiss after 1.2 s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        onFinish()                      // <- closes sheet
                    }
                } else {
                    errorMsg = "Server rejected request"
                }
            } catch {
                errorMsg = "Network error"
            }
            isBusy = false
        }
    }
}

// MARK: – Small UI helpers
private struct SecureFieldRow: View {
    @Binding var text : String
    let icon, placeholder : String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gold).frame(width: 22)
            SecureField(placeholder, text: $text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .fieldFrame()
    }
}

// Same helpers used elsewhere
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
        self
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundColor(.red)
            .padding(.horizontal, 4)
    }

    // Simple toast helper
    func toast<Toast: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Toast
    ) -> some View {
        ZStack {
            self
            if isPresented.wrappedValue {
                content()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                    .onAppear {
                        // auto-hide handled by caller
                    }
            }
        }
        .animation(.easeInOut, value: isPresented.wrappedValue)
    }
}
