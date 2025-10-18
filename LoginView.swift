import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @FocusState private var focusedField: Field?
    @State private var showVerifyEmail = false
    @State private var showingForgotPassword = false
    
    enum Field: Hashable {
        case email, password
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.jetBlack.edgesIgnoringSafeArea(.all)
            
            // Content
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack {
                        Image("meltixlogotransparent")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 150)
                            .padding(.top, 20)
                            .frame(height: 100)
                        
                        Text("MELTIX HOME")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.gold)
                    }
                    .padding(.bottom, 20)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Email Field
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.gold)
                                .frame(width: 20)
                            TextField("Email", text: $email)
                                .focused($focusedField, equals: .email)
                                .foregroundColor(.white)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gold, lineWidth: 1)
                        )
                        
                        // Password Field
                        HStack {
                            Image(systemName: "lock")
                                .foregroundColor(.gold)
                                .frame(width: 20)
                            SecureField("Password", text: $password)
                                .focused($focusedField, equals: .password)
                                .foregroundColor(.white)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .onSubmit {
                                    attemptLogin()
                                }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gold, lineWidth: 1)
                        )
                        
                        // Error Message
                        if let error = authManager.error {
                            Text(error)
                                .foregroundColor(.red)
                                .transition(.opacity)
                        }
                        
                        // Login Button
                        Button(action: attemptLogin) {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("LOG IN")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .shadow(color: .gold.opacity(0.3), radius: 10, x: 0, y: 5)
                        .disabled(authManager.isLoading)
                        .onChange(of: authManager.isVerified) { verified in
                            if authManager.isAuthenticated && !verified {
                                showVerifyEmail = true
                            }
                        }
                        .sheet(isPresented: $showVerifyEmail) {
                            if let email = authManager.pendingVerificationEmail ?? (authManager.error == nil ? email : nil) {
                                VerifyEmailView(email: email)
                                    .environmentObject(authManager)
                            }
                        }
                        
                        // Sign Up Prompt
                        Button {
                            dismissKeyboard()
                            showingSignUp = true
                        } label: {
                            HStack {
                                Text("Don't have an account?")
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Sign Up")
                                    .foregroundColor(.gold)
                                    .fontWeight(.medium)
                            }
                        }
                        .sheet(isPresented: $showingSignUp) {
                            SignUpView()
                                .environmentObject(authManager)
                        }
                        
                        Button("Forgot your password?") {
                            showingForgotPassword = true
                        }
                        .foregroundColor(.gold)
                        .sheet(isPresented: $showingForgotPassword) {
                            ForgotAndVerifyView().environmentObject(authManager)
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .padding(.vertical, 40)
            }
            .onTapGesture {
                dismissKeyboard()
            }
        }
    }
    
    private func attemptLogin() {
        dismissKeyboard()
        
        Task {
            await authManager.login(email: email, password: password)
        }
    }
    
    func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
