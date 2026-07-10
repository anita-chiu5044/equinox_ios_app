import Foundation
import Combine
import AuthenticationServices

@MainActor
final class AppState: ObservableObject {
    @Published var user: UserDTO?
    @Published var authStatus: AuthStatus = .checkingSession
    @Published var authError: String?

    private let api: APIClient

    init(api: APIClient? = nil) {
        self.api = api ?? .shared
    }

    var isSignedIn: Bool {
        user != nil
    }

    func restoreSession() async {
        guard api.hasSavedToken else {
            authStatus = .signedOut
            return
        }

        authStatus = .checkingSession
        do {
            user = try await api.me()
            authStatus = .signedIn
            authError = nil
        } catch {
            api.clearToken()
            user = nil
            authStatus = .signedOut
            authError = "Your saved session expired. Please sign in again."
        }
    }

    func signInForDevelopment() async {
        authStatus = .signingIn
        do {
            let response = try await api.devSignInApple()
            api.saveToken(response.accessToken)
            user = response.user
            authStatus = .signedIn
            authError = nil
        } catch {
            user = nil
            authStatus = .signedOut
            authError = error.localizedDescription
        }
    }

    /// Google sign-in. When a real OAuth client ID is configured the full
    /// browser PKCE flow runs and the backend verifies the id_token against
    /// Google's JWKS. Without a client ID, DEBUG builds fall back to the
    /// backend dev bypass so local development stays credential-free.
    func signInWithGoogle() async {
        authStatus = .signingIn
        do {
            let response: TokenResponse
            if GoogleOAuthService.isConfigured {
                let result = try await GoogleOAuthService.shared.signIn()
                response = try await api.signInGoogle(
                    idToken: result.idToken,
                    name: result.displayName
                )
            } else {
                #if DEBUG
                response = try await api.devSignInGoogle()
                #else
                throw GoogleOAuthService.OAuthError.notConfigured
                #endif
            }
            api.saveToken(response.accessToken)
            user = response.user
            authStatus = .signedIn
            authError = nil
        } catch GoogleOAuthService.OAuthError.cancelled {
            user = nil
            authStatus = .signedOut
        } catch {
            user = nil
            authStatus = .signedOut
            authError = error.localizedDescription
        }
    }

    func signInWithApple(identityToken: String, name: String?) async {
        authStatus = .signingIn
        do {
            let response = try await api.signInApple(identityToken: identityToken, name: name)
            api.saveToken(response.accessToken)
            user = response.user
            authStatus = .signedIn
            authError = nil
        } catch {
            user = nil
            authStatus = .signedOut
            authError = error.localizedDescription
        }
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                authError = "Apple did not return an identity token."
                return
            }

            let displayName = [
                credential.fullName?.givenName,
                credential.fullName?.familyName,
            ]
                .compactMap { $0 }
                .joined(separator: " ")

            await signInWithApple(identityToken: token, name: displayName.isEmpty ? nil : displayName)

        case .failure(let error):
            authError = error.localizedDescription
        }
    }

    func signInForPreview() {
        user = UserDTO(id: "preview-user", email: "anita@example.com", name: "Anita", timezone: "Asia/Taipei")
        authStatus = .signedIn
    }

    func signOut() {
        api.clearToken()
        user = nil
        authStatus = .signedOut
        authError = nil
    }

    func updateDisplayName(_ name: String) async -> Bool {
        do {
            user = try await api.updateMe(name: name)
            authError = nil
            return true
        } catch {
            authError = error.localizedDescription
            return false
        }
    }

    func deleteAccount() async {
        do {
            try await api.deleteMe()
            signOut()
        } catch {
            authError = error.localizedDescription
        }
    }
}

enum AuthStatus: Equatable {
    case signedOut
    case checkingSession
    case signingIn
    case signedIn
}
