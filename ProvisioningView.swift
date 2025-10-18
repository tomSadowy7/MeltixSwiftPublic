import SwiftUI

struct ProvisioningView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var bleManager = BLEManager.shared
    @State private var ssid = ""
    @State private var password = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isProvisioning = false
    
    let onSuccess: () -> Void

    // Called when provisioning succeeds (navigation logic in parent view)

    // Theme colors
    private let goldColor = Color(red: 0.95, green: 0.75, blue: 0.3)
    private let darkBackground = Color(red: 0.08, green: 0.08, blue: 0.08)
    private let cardBackground = Color(red: 0.2, green: 0.2, blue: 0.2)

    var body: some View {
        NavigationStack {
            ZStack {
                darkBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        statusCard
                        credentialsCard
                        provisionButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                }
            }
            .navigationTitle("WiFi Provisioning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") {
                        resetAllStates()
                        authManager.logout()
                    }
                    .foregroundColor(goldColor)
                }
            }
            .onAppear {
                resetBLEState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .homeBaseClaimed)) { _ in
                print("Received homeBaseClaimed notification")
                handleProvisioningSuccess()
            }
            .onReceive(NotificationCenter.default.publisher(for: .provisioningFailed)) { notification in
                let message = (notification.object as? String) ?? "Unknown error occurred"
                handleProvisioningFailed(message)
            }
            .alert("Provisioning Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { resetAfterError() }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func showStatusSpinner(_ status: String) -> Bool {
        let s = status.lowercased()
        // Only show spinner when it's actively working
        return s.contains("scanning") || s.contains("discovering") || s.contains("sending") || s.contains("connecting") || s.contains("claiming")
    }
    
    
    // MARK: - UI Components

    private var statusCard: some View {
        VStack(alignment: .center, spacing: 12) {  // Slightly more spacing between lines
            Text("DEVICE STATUS")
                .font(.system(size: 13, weight: .medium))  // Slightly larger (from 12)
                .foregroundColor(goldColor.opacity(0.7))
                .padding(.bottom, 2)
            
            // Main status row with tight icon spacing
            ZStack {
                // Centered text
                Text(bleManager.bleStatus)
                    .font(.system(size: 17, weight: .medium))  // Slightly larger (from 16)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                
                // Status icons with tight spacing
                HStack(spacing: 0) {
                    Spacer()
                    
                    if bleManager.bleStatus.lowercased() == "homebase detected" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 19))  // Slightly larger (from 18)
                            .padding(.leading, 4)  // Tighter spacing (from 8)
                    } else if bleManager.bleStatus.lowercased().contains("disconnected") {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 19))
                            .padding(.leading, 4)
                    }
                    
                    if showStatusSpinner(bleManager.bleStatus) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.9)  // Slightly larger
                            .padding(.leading, 4)
                    }
                }
            }
            .frame(height: 26)  // Slightly taller to accommodate larger text
            
            Text(bleManager.provisioningStatus)
                .foregroundColor(statusColor(for: bleManager.provisioningStatus))
                .font(.system(size: 15))  // Slightly larger (from 14)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(12)
        .frame(width: 270)  // Slightly wider to accommodate larger text
        .background(cardBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(goldColor, lineWidth: 1)
        )
    }


    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WIFI CREDENTIALS")
                .font(.caption)
                .foregroundColor(goldColor.opacity(0.7))
            CustomTextField(icon: "wifi", placeholder: "Network SSID", text: $ssid)
            CustomTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(goldColor, lineWidth: 1)
        )
    }

    private var provisionButton: some View {
        Button(action: startProvisioningProcess) {
            HStack {
                if isProvisioning {
                    ProgressView()
                        .tint(.black)
                }
                Text(isProvisioning ? "PROVISIONING..." : "PROVISION DEVICE")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(canProvision ? goldColor : Color.gray)
        .foregroundColor(.black)
        .cornerRadius(10)
        .shadow(color: goldColor.opacity(0.3), radius: 10, x: 0, y: 5)
        .disabled(!canProvision || isProvisioning)
    }

    // MARK: - Logic

    private var canProvision: Bool {
        return bleManager.isConnected && !ssid.isEmpty && !password.isEmpty && !isProvisioning
    }

    private func statusColor(for status: String) -> Color {
        let lowercased = status.lowercased()
        if lowercased.contains("fail") {
            return .red
        } else if lowercased.contains("success") || lowercased.contains("complete") || lowercased.contains("claimed") {
            return .green
        } else if lowercased.contains("ready") {
            return goldColor
        } else {
            return .white
        }
    }

    private func startProvisioningProcess() {
        guard canProvision else { return }
        isProvisioning = true
        bleManager.provision(ssid: ssid, password: password)
    }

    private func handleProvisioningSuccess() {
        isProvisioning = false
        Task {
            // 1. Wait for the server to confirm HomeBase is set up (fetch name, etc)
            await authManager.checkHomeBaseStatus()
            // 2. When done, animate out and move to the success view
            
            onSuccess()
        }
    }

    private func handleProvisioningFailed(_ message: String) {
        isProvisioning = false
        errorMessage = message
        showErrorAlert = false
    }

    private func resetAfterError() {
        resetBLEState()
    }

    private func resetBLEState() {
        bleManager.reset()
        bleManager.startScan()
    }

    private func resetAllStates() {
        isProvisioning = false
        ssid = ""
        password = ""
        bleManager.reset()
    }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.3))
                .frame(width: 20)
            if isSecure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.95, green: 0.75, blue: 0.3), lineWidth: 1)
        )
    }
}
