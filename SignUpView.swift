import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    // Form fields
    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    
    // Validation
    @State private var showingValidationError = false
    @State private var validationError = ""
    
    private let states = USStates.all
    private let fieldHeight: CGFloat = 48
    
    var body: some View {
        ZStack {
            Color.jetBlack.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.gold)
                        Text("Create Account")
                            .font(.title.bold())
                            .foregroundColor(.gold)
                    }
                    .padding(.vertical, 32)
                    
                    VStack(spacing: 16) {
                        InputField(
                            text: $email,
                            placeholder: "Email",
                            icon: "envelope",
                            keyboardType: .emailAddress,
                            height: fieldHeight
                        )
                        InputField(
                            text: $password,
                            placeholder: "Password",
                            icon: "lock",
                            isSecure: true,
                            height: fieldHeight
                        )
                        HStack(spacing: 16) {
                            InputField(
                                text: $firstName,
                                placeholder: "First Name",
                                icon: "person",
                                height: fieldHeight
                            )
                            InputField(
                                text: $lastName,
                                placeholder: "Last Name",
                                icon: "person",
                                height: fieldHeight
                            )
                        }
                        .frame(height: fieldHeight)
                        
                        InputField(
                            text: $city,
                            placeholder: "City",
                            icon: "building",
                            height: fieldHeight
                        )
                        HStack(spacing: 16) {
                            StateDropdown(
                                state: $state,
                                options: states,
                                height: fieldHeight
                            )
                            ZipInputField(
                                zip: $zip,
                                height: fieldHeight
                            )
                        }
                        .frame(height: fieldHeight)
                    }
                    .padding(.horizontal, 20)
                    
                    if showingValidationError {
                        Text(validationError)
                            .foregroundColor(.red)
                            .transition(.opacity)
                    }
                    if let authError = authManager.error {
                        Text(authError)
                            .foregroundColor(.red)
                            .transition(.opacity)
                    }
                    
                    Button(action: handleSignUp) {
                        if authManager.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text("Sign Up").fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(GoldButtonStyle())
                    .disabled(authManager.isLoading)
                    .frame(height: fieldHeight)
                    .padding(.top, 8)
                    
                    Button(action: { dismiss() }) {
                        Text("Already have an account? Sign In")
                            .foregroundColor(.gold)
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 40)
            }
        }
        .animation(.default, value: showingValidationError)
        .onAppear {
            authManager.error = nil
            validationError = ""
            showingValidationError = false
        }
    }
    
    private func handleSignUp() {
        guard validateFields() else {
            withAnimation { showingValidationError = true }
            return
        }
        Task {
            let success = await authManager.signup(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                city: city,
                state: state,
                zip: zip
            )
            
            if success {
                authManager.hasHomeBase = false
                authManager.hasCheckedHomeBase = true
                dismiss()
            }
        }
    }
    
    private func validateFields() -> Bool {
        let fields = [
            (email, "Email"),
            (password, "Password"),
            (firstName, "First name"),
            (lastName, "Last name"),
            (city, "City"),
            (state, "State"),
            (zip, "ZIP code")
        ]
        for (field, name) in fields {
            if field.trimmingCharacters(in: .whitespaces).isEmpty {
                validationError = "\(name) is required"
                return false
            }
        }
        if !email.isValidEmail {
            validationError = "Please enter a valid email"
            return false
        }
        if password.count < 6 {
            validationError = "Password must be at least 6 characters"
            return false
        }
        if zip.count != 5 || zip.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            validationError = "ZIP code must be exactly 5 digits"
            return false
        }
        return true
    }
}


// MARK: - State List
enum USStates {
    static let all = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]
}

// MARK: - Email Validator
extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: self)
    }
}
