import Foundation

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var isAuthenticated = false
    @Published var hasHomeBase: Bool = false
    @Published var homeBaseName: String = ""
    @Published private(set) var hasCheckedInitialState = false
    @Published var hasCheckedHomeBase = false
    @Published var homeBaseId: String? = nil
    @Published var isVerified: Bool = false
    @Published var pendingVerificationEmail: String? = nil   // for navigation
    @Published var user: UserProfile?

    func markVerified() {
        isVerified = true
    }

    let baseURL = "http://192.168.68.68:3001"
    private let tokenKey = "userToken"
    
    private(set) var token: String? {
        didSet {
            UserDefaults.standard.set(token, forKey: tokenKey)
            isAuthenticated = token != nil
        }
    }
    
    private init() {
        /*
        if UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            self.token = UserDefaults.standard.string(forKey: tokenKey)
            self.isAuthenticated = token != nil
        } else {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            self.token = nil
            self.isAuthenticated = false
        }
         */
        self.token = nil
        self.isAuthenticated = false
        self.isVerified = false
    }
    
    func completeInitialAuthCheck() {
        hasCheckedInitialState = true
    }

    // MARK: - Authentication Methods
    
    func login(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let body: [String: Any] = ["email": email, "password": password]
            let request = try createRequest(endpoint: "/auth/login", method: "POST", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleAuthResponse(data: data, response: response)
            await checkHomeBaseStatus()
            self.pendingVerificationEmail = email
        } catch let error as AuthError {
            self.error = error.localizedDescription
        } catch {
            self.error = "An unknown error occurred"
        }
    }
    
    func signup(email: String, password: String, firstName: String, lastName: String, city: String, state: String, zip: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let body: [String: Any] = [
                "email": email,
                "password": password,
                "firstName": firstName,
                "lastName": lastName,
                "city": city,
                "state": state,
                "zip": zip
            ]
            let request = try createRequest(endpoint: "/auth/signup", method: "POST", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try handleAuthResponse(data: data, response: response)
            self.pendingVerificationEmail = email
            return true
        } catch let error as AuthError {
            self.error = error.localizedDescription
            return false
        } catch {
            self.error = "An unknown error occurred"
            return false
        }
    }
    
    func logout() {
        token = nil
        hasHomeBase = false
        homeBaseName = ""
        hasCheckedHomeBase = false
        user = nil
        BLEManager.shared.reset()
        DeviceWebSocketManager.shared.reset()
        print("logged out")
    }
    
    func fullReset() {
        token = nil
        user = nil
        isAuthenticated = false
        hasHomeBase = false
        homeBaseName = ""
        error = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        BLEManager.shared.reset()
        print("AuthManager fully reset")
    }
    
    func checkHomeBaseStatus() async {
        guard isAuthenticated else { return }
        defer { self.hasCheckedHomeBase = true }
        do {
            let request = try createGetRequest(endpoint: "/homebase/getname")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                let response = try JSONDecoder().decode(HomeBaseResponse.self, from: data)
                hasHomeBase = response.hasHomeBase
                homeBaseName = response.name
                
            case 404:
                hasHomeBase = false
                homeBaseName = ""
            default:
                throw AuthError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch {
            hasHomeBase = false
            homeBaseName = ""
        }
    }
    
    // MARK: - Helpers
    
    private func createRequest(endpoint: String, method: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func createGetRequest(endpoint: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + endpoint) else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
    
    private func handleAuthResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        if let json = String(data: data, encoding: .utf8) {
                print("🛰️  Auth raw JSON →", json)
            }
        switch httpResponse.statusCode {
        case 200...201:
            struct AuthResponse: Decodable {
                let token: String
                let isVerified: Bool
                let user: UserProfile?
            }
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            print("set token")
            token = authResponse.token
            isVerified = authResponse.isVerified
            user       = authResponse.user
        case 400...499:
            struct ErrorResponse: Decodable { let error: String? }
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.customMessage(message: errorResponse.error ?? "Invalid request")
        default:
            throw AuthError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    func verifyEmail(email: String, code: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        error = nil
        
        do {
            let body: [String: Any] = [
                "email": email,
                "code": code
            ]
            let request = try createRequest(endpoint: "/auth/verify", method: "POST", body: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            switch httpResponse.statusCode {
            case 200:
                return true
            case 400...499:
                struct ErrorResponse: Decodable {
                    let error: String?
                }
                let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                self.error = errorResponse.error ?? "Invalid code"
                return false
            default:
                throw AuthError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let authError as AuthError {
            self.error = authError.localizedDescription
            return false
        } catch {
            self.error = "An unknown error occurred"
            return false
        }
    }
    
    
    @MainActor
    func updateProfile(firstName: String, lastName: String, city: String, state: String, zip: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body: [String: Any] = [
                "firstName": firstName,
                "lastName": lastName,
                "city": city,
                "state": state,
                "zip": zip
            ]
            var request = try createRequest(endpoint: "/account/update", method: "POST", body: body)

            // Add auth header
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                struct UpdateResponse: Decodable { let user: UserProfile }
                let res = try JSONDecoder().decode(UpdateResponse.self, from: data)
                self.user = res.user              // keep local copy current
                return true
            case 400...499:
                struct ErrorResponse: Decodable { let error: String? }
                let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                self.error = errorResponse.error ?? "Update failed"
                return false
            default:
                throw AuthError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let authError as AuthError {
            self.error = authError.localizedDescription
            return false
        } catch {
            self.error = "An unknown error occurred"
            return false
        }
    }
    
    func resendVerificationCode() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        error = nil
        
        do {
            // Create request
            var request = try createRequest(endpoint: "/auth/resend-verification", method: "POST", body: [:])
            
            // Add Authorization header with token
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            // Perform request
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            // Handle response codes
            switch httpResponse.statusCode {
            case 200:
                return true
            case 400...499:
                struct ErrorResponse: Decodable { let error: String? }
                let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
                self.error = errorResponse.error ?? "Unable to resend"
                return false
            default:
                throw AuthError.serverError(statusCode: httpResponse.statusCode)
            }
        } catch let authError as AuthError {
            self.error = authError.localizedDescription
            return false
        } catch {
            self.error = "An unknown error occurred"
            return false
        }
    }
    struct UserProfile: Codable, Equatable {   // ← add Equatable
        var firstName: String
        var lastName : String
        var city     : String
        var state    : String
        var zip      : String
        var email    : String
    }
    
    
    func sendForgotPassword(email: String) async throws -> Bool {
        let body: [String: Any] = ["email": email]
        let request = try createRequest(endpoint: "/auth/forgot-password", method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        return httpResponse.statusCode == 200
    }

    func submitResetPassword(email: String, code: String, newPassword: String) async throws -> Bool {
        let body: [String: Any] = [
            "email": email,
            "code": code,
            "newPassword": newPassword
        ]
        let request = try createRequest(endpoint: "/auth/reset-password", method: "POST", body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        return httpResponse.statusCode == 200
    }
    func verifyResetCode(email: String, code: String) async -> Bool {
        let body: [String: Any] = ["email": email, "code": code]
        do {
            let req = try createRequest(endpoint: "/auth/verify-reset-code",
                                        method: "POST", body: body)
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    

    
    // MARK: - Types
    struct HomeBaseResponse: Decodable {
        let hasHomeBase: Bool
        let name: String
        let id: String?
    }
    
    enum AuthError: Error, LocalizedError {
        case invalidURL, invalidCredentials, invalidResponse
        case serverError(statusCode: Int)
        case customMessage(message: String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .invalidCredentials: return "Invalid email or password"
            case .invalidResponse: return "Invalid server response"
            case .serverError(let code): return "Server error (Code: \(code))"
            case .customMessage(let message): return message
            }
        }
    }
    // AuthManager.swift ─ add near the bottom
    @MainActor
    func sendBugReport(_ text: String) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        isLoading = true;  defer { isLoading = false }
        do {
            let body: [String:Any] = ["description": text]
            var req = try createRequest(endpoint: "/api/bugreport", method: "POST", body: body)

            // attach token if present (optional on the server side)
            if let token = token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 201
        } catch {
            print("Bug-report error:", error)
            return false
        }
    }
}
