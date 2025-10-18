import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showSuccessView = false
    @State private var hasCompletedInitialAuthCheck = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if !hasCompletedInitialAuthCheck {
                    ZStack {
                        Color.jetBlack.ignoresSafeArea()
                        VStack(spacing: 20) {
                            Image("meltixlogotransparent")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 200, maxHeight: 150)
                            Text("MELTIX TECHNOLOGIES")
                                .font(.title)
                                .fontWeight(.semibold)
                                .foregroundColor(.gold)
                        }
                    }
                    .transition(.opacity)
                }

                else if !authManager.isAuthenticated {
                    LoginView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                else if authManager.isAuthenticated && !authManager.isVerified {
                    VerifyEmailView(email: authManager.pendingVerificationEmail ?? "")
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                else if authManager.isAuthenticated && !authManager.hasCheckedHomeBase {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView("Checking HomeBase...")
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                else if authManager.hasHomeBase {
                    if showSuccessView {
                        HomeBaseSuccessView {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showSuccessView = false
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                    } else {
                        HomeBaseDevicesView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                else {
                    ProvisioningView {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSuccessView = true
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .animation(.easeInOut(duration: 0.45), value: authManager.isAuthenticated)
            .animation(.easeInOut(duration: 0.45), value: authManager.hasCheckedHomeBase)
            .animation(.easeInOut(duration: 0.45), value: authManager.isVerified)  // 👈 ADD THIS LINE
            .animation(.spring(), value: showSuccessView)
        }
        .task {
            await checkAuthState()
        }
    }
    
    private func checkAuthState() async {
        let isFreshLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch")
        if isFreshLaunch {
            authManager.logout()
            UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
        }
        if authManager.isAuthenticated {
            await authManager.checkHomeBaseStatus()
        }
        DispatchQueue.main.async {
            self.hasCompletedInitialAuthCheck = true
        }
    }
}
