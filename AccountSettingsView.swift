import SwiftUI

struct AccountSettingsView: View {
    // ───────────────────────── Dependencies
    @EnvironmentObject private var authManager: AuthManager
    var onClose: () -> Void = {}

    // ───────────────────────── Profile fields
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var city      = ""
    @State private var state     = ""
    @State private var zip       = ""

    // ───────────────────────── Bug reporter
    private let bugMaxLen = 1_000
    @State private var bugText = ""
    @FocusState private var bugFocused: Bool      // Keyboard focus

    // ───────────────────────── UI state
    @State private var isLoading = false
    @State private var toastMsg  : String? = nil

    private let states      = USStates.all
    private let fieldHeight: CGFloat = 48

    // MARK: - Body
    var body: some View {
        ZStack {
            // Tap-to-dismiss background
            Color.jetBlack.ignoresSafeArea()
                .onTapGesture { dismissKeyboard() }

            ScrollView {
                VStack(spacing: 26) {
                    header
                    profileForm
                    bugReporter
                }
                .padding(.bottom, 60)
                // Tap inside the scroll view should also close the keyboard
                .contentShape(Rectangle())               // make empty space tappable
                .onTapGesture { dismissKeyboard() }
            }
            .onAppear(perform: populateFromUser)
            .onChange(of: authManager.user) { _ in populateFromUser() }

            toastOverlay
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 36))
                    .foregroundColor(.gold)
                Text("Account Settings")
                    .font(.title3.bold())
                    .foregroundColor(.gold)
            }
            Spacer()
            Button("Done") { onClose() }
                .font(.headline)
                .foregroundColor(.gold)
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }

    // MARK: - Profile form
    private var profileForm: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                InputField(text: $firstName, placeholder: "First Name", icon: "person", height: fieldHeight)
                InputField(text: $lastName , placeholder: "Last Name" , icon: "person", height: fieldHeight)
            }
            InputField(text: $city, placeholder: "City", icon: "building", height: fieldHeight)
            HStack(spacing: 16) {
                StateDropdown(state: $state, options: states, height: fieldHeight)
                ZipInputField(zip: $zip, height: fieldHeight)
            }

            Button(action: submitUpdate) {
                if isLoading { ProgressView().tint(.black) }
                else { Text("Save Changes").fontWeight(.semibold) }
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(isLoading)
            .frame(height: fieldHeight)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Bug reporter
    private var bugReporter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a Bug")
                .font(.headline)
                .foregroundColor(.gold)
                .padding(.horizontal, 20)

            TextEditor(text: $bugText)
                .focused($bugFocused)
                .frame(minHeight: 120, maxHeight: 160)
                .padding(12)
                .background(Color.charcoal)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gold.opacity(0.5), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .onChange(of: bugText) { newVal in
                    if newVal.count > bugMaxLen {
                        bugText = String(newVal.prefix(bugMaxLen))
                    }
                }

            // Character counter
            Text("\(bugText.count) / \(bugMaxLen)")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 26)

            // Centered submit button
            HStack {
                Spacer()
                Button("Send Bug Report") {
                    Task { await sendBug() }
                }
                .buttonStyle(GoldButtonStyle())
                .frame(height: fieldHeight)
                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Toast overlay
    private var toastOverlay: some View {
        Group {
            if let msg = toastMsg {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                        .shadow(radius: 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { toastMsg = nil }
                            }
                        }
                    Spacer().frame(height: 40)
                }
                .zIndex(100)
            }
        }
    }

    // MARK: - Actions
    private func submitUpdate() {
        dismissKeyboard()   
        isLoading = true
        Task {
            let ok = await authManager.updateProfile(
                firstName: firstName,
                lastName : lastName,
                city     : city,
                state    : state,
                zip      : zip
            )
            isLoading = false
            withAnimation {
                toastMsg = ok ? "Profile updated!" : (authManager.error ?? "Update failed")
            }
        }
    }

    private func sendBug() async {
        let trimmed = bugText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation { toastMsg = "Please enter a bug description." }
            return
        }

        dismissKeyboard()
        bugText = ""

        do {
            var req = URLRequest(url: URL(string: authManager.baseURL + "/bugreport")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let tok = authManager.token {
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            }
            let payload = [
                "description": trimmed,
                "email": authManager.user?.email ?? ""
            ]
            req.httpBody = try JSONEncoder().encode(payload)

            let (data, resp) = try await URLSession.shared.data(for: req)
            let ok = (resp as? HTTPURLResponse).map { 200...299 ~= $0.statusCode } ?? false

            withAnimation {
                toastMsg = ok
                    ? "Thank you – bug sent!"
                    : ((try? JSONDecoder().decode([String:String].self, from: data)["error"])
                        ?? "Failed to send bug.")
            }
        } catch {
            withAnimation { toastMsg = "Network error." }
        }
    }

    // MARK: - Helpers
    private func populateFromUser() {
        guard let u = authManager.user else { return }
        firstName = u.firstName
        lastName  = u.lastName
        city      = u.city
        state     = u.state
        zip       = u.zip
    }

    /// Clears focus & hides the system keyboard.
    private func dismissKeyboard() {
        bugFocused = false
        hideKeyboard()
    }
}

// MARK: - Global helper
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/* KEEP your existing InputField, StateDropdown, ZipInputField structs */

struct InputField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var height: CGFloat = 48

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.gold)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboardType)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(Color.charcoal)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gold.opacity(0.5), lineWidth: 1)
        )
        .foregroundColor(.white)
    }
}

/// Compact state-picker that matches the field styling.
struct StateDropdown: View {
    @Binding var state: String
    let options: [String]
    var height: CGFloat = 48

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { abbr in
                Button(abbr) { state = abbr }
            }
        } label: {
            HStack {
                Text(state.isEmpty ? "State" : state)
                    .foregroundColor(state.isEmpty ? .gray : .gold)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .foregroundColor(.gold)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Color.charcoal)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gold.opacity(0.5), lineWidth: 1)
            )
        }
    }
}

/// 5-digit ZIP code field (digits only, max 5).
struct ZipInputField: View {
    @Binding var zip: String
    var height: CGFloat = 48

    var body: some View {
        HStack {
            Image(systemName: "number")
                .foregroundColor(.gold)
                .frame(width: 20)
            TextField("ZIP", text: Binding(
                get: { zip },
                set: { zip = String($0.prefix(5).filter(\.isNumber)) }
            ))
            .keyboardType(.numberPad)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background(Color.charcoal)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gold.opacity(0.5), lineWidth: 1)
        )
        .foregroundColor(.white)
    }
}
