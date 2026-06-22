import AuthenticationServices
import CryptoKit
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Real Google OAuth without the GoogleSignIn SDK: ASWebAuthenticationSession
/// + PKCE against Google's OAuth 2.0 endpoints (installed-app client, no
/// client secret). Used for both Sign-In (id_token) and the Google Calendar
/// connection (authorization code handed to the backend).
@MainActor
final class GoogleOAuthService: NSObject {
    static let shared = GoogleOAuthService()

    struct SignInResult {
        let idToken: String
        let displayName: String?
    }

    /// Authorization code the backend exchanges for a Calendar refresh token.
    struct CalendarAuthorization {
        let code: String
        let codeVerifier: String
        let redirectURI: String
    }

    enum OAuthError: LocalizedError {
        case notConfigured
        case badCallback
        case tokenExchangeFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Google sign-in is not configured (missing GOOGLE_IOS_CLIENT_ID)."
            case .badCallback:
                "Google returned an unexpected callback."
            case .tokenExchangeFailed(let detail):
                "Google token exchange failed: \(detail)"
            case .cancelled:
                "Sign-in was cancelled."
            }
        }
    }

    // MARK: Configuration

    /// iOS OAuth client ID, e.g. `1234-abc.apps.googleusercontent.com`,
    /// injected through the GOOGLE_IOS_CLIENT_ID build setting.
    static var clientID: String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String,
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isConfigured: Bool {
        clientID != nil
    }

    /// `com.googleusercontent.apps.1234-abc` — Google's required scheme for
    /// installed-app redirects (reversed client ID).
    private static var redirectScheme: String? {
        guard let clientID else {
            return nil
        }
        let parts = clientID.components(separatedBy: ".")
        return parts.reversed().joined(separator: ".")
    }

    private static var redirectURI: String? {
        redirectScheme.map { "\($0):/oauth2redirect" }
    }

    // MARK: Public flows

    /// Full sign-in: browser auth -> on-device code exchange -> id_token.
    func signIn() async throws -> SignInResult {
        let auth = try await authorize(scopes: "openid email profile")
        let tokens = try await exchangeCode(
            code: auth.code,
            codeVerifier: auth.codeVerifier,
            redirectURI: auth.redirectURI
        )
        guard let idToken = tokens.idToken else {
            throw OAuthError.tokenExchangeFailed("response contained no id_token")
        }
        return SignInResult(idToken: idToken, displayName: Self.nameClaim(fromIDToken: idToken))
    }

    /// Calendar consent: returns the auth code so the *backend* can do the
    /// exchange and keep the refresh token server-side.
    func authorizeCalendar() async throws -> CalendarAuthorization {
        try await authorize(scopes: "https://www.googleapis.com/auth/calendar.readonly")
    }

    // MARK: Browser leg

    private func authorize(scopes: String) async throws -> CalendarAuthorization {
        guard
            let clientID = Self.clientID,
            let scheme = Self.redirectScheme,
            let redirectURI = Self.redirectURI
        else {
            throw OAuthError.notConfigured
        }

        let codeVerifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.s256Challenge(for: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components?.url else {
            throw OAuthError.notConfigured
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.badCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
            let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw OAuthError.badCallback
        }

        return CalendarAuthorization(code: code, codeVerifier: codeVerifier, redirectURI: redirectURI)
    }

    // MARK: Token exchange (sign-in only; calendar exchange happens server-side)

    private struct TokenEndpointResponse: Decodable {
        let idToken: String?
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
        }
    }

    private func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectURI: String
    ) async throws -> TokenEndpointResponse {
        guard let clientID = Self.clientID else {
            throw OAuthError.notConfigured
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OAuthError.tokenExchangeFailed(body)
        }
        return try JSONDecoder().decode(TokenEndpointResponse.self, from: data)
    }

    // MARK: Helpers

    private static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }

    private static func randomURLSafeString(length: Int) -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    private static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Best-effort `name` claim from the (already server-verified) id_token,
    /// used only for the display name on first sign-in.
    private static func nameClaim(fromIDToken token: String) -> String? {
        let segments = token.components(separatedBy: ".")
        guard segments.count >= 2 else {
            return nil
        }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json["name"] as? String
    }
}

extension GoogleOAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if canImport(UIKit)
            if let windowScene = (UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.first) as? UIWindowScene {
                return ASPresentationAnchor(windowScene: windowScene)
            }
            return ASPresentationAnchor()
            #else
            NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
