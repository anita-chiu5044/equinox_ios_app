import Foundation

enum APIEnvironment {
    static let debugBaseURL = URL(string: "http://127.0.0.1:8000") ?? URL(fileURLWithPath: "/")
    static let productionFallbackURL = URL(string: "https://equinox-api-xxxxx.asia-east1.run.app") ?? URL(fileURLWithPath: "/")

    static var currentBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "EQUINOX_API_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let configuredURL = URL(string: trimmed) {
                return configuredURL
            }
        }

        #if DEBUG
        return debugBaseURL
        #else
        return productionFallbackURL
        #endif
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError {
    case invalidURL(String)
    case missingToken
    case status(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            "Invalid API path: \(path)"
        case .missingToken:
            "No saved access token."
        case .status(let code, let body):
            body.isEmpty ? "Server returned \(code)." : "Server returned \(code): \(body)"
        case .decoding(let error):
            "Could not decode server response: \(error.localizedDescription)"
        case .transport(let error):
            error.localizedDescription
        }
    }
}

struct AnyEncodable: Encodable {
    private let encodeBody: (Encoder) throws -> Void

    init(_ value: Encodable) {
        encodeBody = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBody(encoder)
    }
}

final class APIClient {
    nonisolated static let shared = APIClient()

    private let baseURL: URL
    private let keychain: KeychainStore
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) {
                return date
            }

            let fallbackFormats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd",
            ]
            for format in fallbackFormats {
                let fallback = DateFormatter()
                fallback.locale = Locale(identifier: "en_US_POSIX")
                fallback.timeZone = TimeZone(secondsFromGMT: 0)
                fallback.dateFormat = format
                if let date = fallback.date(from: raw) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 date, got \(raw)."
            )
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    init(
        baseURL: URL = APIEnvironment.currentBaseURL,
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.keychain = keychain
        self.session = session
    }

    var hasSavedToken: Bool {
        keychain.load() != nil
    }

    func saveToken(_ token: String) {
        keychain.save(token)
    }

    func clearToken() {
        keychain.delete()
    }

    func send<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        authed: Bool = true
    ) async throws -> T {
        let request = try makeRequest(path, method: method, body: body, authed: authed)
        let data = try await perform(request)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func sendNoContent(
        _ path: String,
        method: HTTPMethod,
        body: Encodable? = nil,
        authed: Bool = true
    ) async throws {
        let request = try makeRequest(path, method: method, body: body, authed: authed)
        _ = try await perform(request)
    }

    /// Multipart upload (used by `POST /materials`).
    func sendMultipart<T: Decodable>(
        _ path: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidURL(path)
        }
        guard let token = keychain.load() else {
            throw APIError.missingToken
        }

        let boundary = "equinox-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let data = try await perform(request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func makeRequest(
        _ path: String,
        method: HTTPMethod,
        body: Encodable?,
        authed: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if authed {
            guard let token = keychain.load() else {
                throw APIError.missingToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.status(-1, "Missing HTTP response.")
            }

            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.status(http.statusCode, body)
            }

            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }
}

extension APIClient {
    func devSignInApple() async throws -> TokenResponse {
        let token = try DevJWT.make(
            sub: "dev-anita",
            email: "anita@example.com",
            name: "Anita"
        )
        return try await signInApple(identityToken: token, name: "Anita")
    }

    func signInApple(identityToken: String, name: String?) async throws -> TokenResponse {
        try await send(
            "/auth/apple",
            method: .post,
            body: AuthRequest(identityToken: identityToken, idToken: nil, name: name),
            authed: false
        )
    }

    func signInGoogle(idToken: String, name: String? = nil) async throws -> TokenResponse {
        try await send(
            "/auth/google",
            method: .post,
            body: AuthRequest(identityToken: nil, idToken: idToken, name: name),
            authed: false
        )
    }

    func devSignInGoogle() async throws -> TokenResponse {
        let token = try DevJWT.make(
            sub: "dev-anita-google",
            email: "anita@example.com",
            name: "Anita"
        )
        return try await signInGoogle(idToken: token, name: "Anita")
    }

    func me() async throws -> UserDTO {
        try await send("/me")
    }

    func todaySessions() async throws -> [SessionDTO] {
        try await send("/sessions/today")
    }

    func currentGrowth() async throws -> GrowthCycleDTO? {
        try await send("/growth/current")
    }

    func growthHistory() async throws -> [GrowthCycleDTO] {
        try await send("/growth/history")
    }

    func todayCheckin() async throws -> CheckinDTO? {
        try await send("/checkins/today")
    }

    func createCheckin(energy: String) async throws -> CheckinDTO {
        try await send("/checkins", method: .post, body: CheckinCreateRequest(date: nil, energy: energy))
    }

    func listGoals() async throws -> [GoalDTO] {
        try await send("/goals")
    }

    func createGoal(
        title: String,
        deadline: Date?,
        tag: String?,
        materialIds: [String] = [],
        sourceText: String? = nil,
        generatedPhases: [ReplanPhaseRequest]? = nil
    ) async throws -> GoalDTO {
        try await send(
            "/goals",
            method: .post,
            body: GoalCreateRequest(
                title: title,
                deadline: deadline,
                tag: tag,
                color: "#c75d2c",
                materialIds: materialIds,
                sourceText: sourceText,
                generatedPhases: generatedPhases
            )
        )
    }

    func goal(id: String) async throws -> GoalDTO {
        try await send("/goals/\(id)")
    }

    func updateGoal(id: String, request: GoalUpdateRequest) async throws -> GoalDTO {
        try await send("/goals/\(id)", method: .patch, body: request)
    }

    func deleteGoal(id: String) async throws {
        try await sendNoContent("/goals/\(id)", method: .delete)
    }

    func replanGoal(id: String, request: ReplanGoalRequest) async throws -> GoalDTO {
        try await send("/goals/\(id)/replan", method: .post, body: request)
    }

    func addSession(goalID: String, request: SessionCreateRequest) async throws -> SessionDTO {
        try await send("/goals/\(goalID)/sessions", method: .post, body: request)
    }

    func updateSession(id: String, request: SessionUpdateRequest) async throws -> SessionDTO {
        try await send("/sessions/\(id)", method: .patch, body: request)
    }

    func deleteSession(id: String) async throws {
        try await sendNoContent("/sessions/\(id)", method: .delete)
    }

    func uploadMaterial(filename: String, data: Data) async throws -> MaterialDTO {
        let ext = (filename as NSString).pathExtension.lowercased()
        let mime: String = switch ext {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        default: "application/pdf"
        }
        return try await sendMultipart(
            "/materials",
            fieldName: "file",
            filename: filename,
            mimeType: mime,
            fileData: data
        )
    }

    func deleteMaterial(id: String) async throws {
        try await sendNoContent("/materials/\(id)", method: .delete)
    }

    func scheduleGoal(id: String) async throws -> SchedulePreviewDTO {
        try await send("/goals/\(id)/schedule", method: .post)
    }

    func schedule(goalID: String, week: String? = nil) async throws -> SchedulePreviewDTO {
        var path = "/goals/\(goalID)/schedule"
        if let week {
            path += "?week=\(week)"
        }
        return try await send(path)
    }

    func confirmSchedule(goalID: String) async throws -> SchedulePreviewDTO {
        try await send("/goals/\(goalID)/schedule/confirm", method: .post)
    }

    func todaySuggestion() async throws -> SuggestionDTO? {
        try await send("/suggestions/today")
    }

    func pendingSuggestions() async throws -> [SuggestionDTO] {
        try await send("/suggestions/pending")
    }

    func previewSuggestion(id: String, choice: String) async throws -> SuggestionPreviewDTO {
        try await send(
            "/suggestions/\(id)/preview", method: .post,
            body: SuggestionResponseRequest(choice: choice, rejectionReason: nil)
        )
    }

    func applySuggestion(
        id: String, choice: String, rejectionReason: String? = nil
    ) async throws -> SuggestionPreviewDTO {
        try await send(
            "/suggestions/\(id)/apply", method: .post,
            body: SuggestionResponseRequest(choice: choice, rejectionReason: rejectionReason)
        )
    }

    func respondToSuggestion(id: String, choice: String) async throws -> SuggestionDTO {
        try await send(
            "/suggestions/\(id)/respond",
            method: .post,
            body: SuggestionResponseRequest(choice: choice, rejectionReason: nil)
        )
    }

    func syncHealth(
        sleepHours: Double?,
        steps: Int?,
        workoutMinutes: Int? = nil
    ) async throws {
        try await sendNoContent(
            "/health/daily", method: .post,
            body: HealthDailyRequest(
                date: nil, sleepHours: sleepHours, steps: steps,
                workoutMinutes: workoutMinutes, source: "healthkit"
            )
        )
    }

    func todayCapacity() async throws -> CapacityDTO {
        try await send("/health/capacity/today")
    }

    func learningProfile() async throws -> LearningProfileDTO {
        try await send("/learning/profile")
    }

    func insights() async throws -> InsightsDTO {
        try await send("/insights")
    }

    func settings() async throws -> SettingsDTO {
        try await send("/settings")
    }

    func updateSettings(_ request: SettingsUpdateRequest) async throws -> SettingsDTO {
        try await send("/settings", method: .patch, body: request)
    }

    func connections() async throws -> ConnectionsDTO {
        try await send("/connections")
    }

    /// Dev/stub connect (no credentials); used when no OAuth client is configured.
    func connectGoogleCalendar() async throws -> ConnectionStateDTO {
        try await send("/connections/google-calendar", method: .post)
    }

    /// Real connect: hands the OAuth authorization code to the backend.
    func connectGoogleCalendar(_ request: GoogleCalendarConnectRequest) async throws -> ConnectionStateDTO {
        try await send("/connections/google-calendar", method: .post, body: request)
    }

    func disconnectGoogleCalendar() async throws {
        try await sendNoContent("/connections/google-calendar", method: .delete)
    }

    func deleteMe() async throws {
        try await sendNoContent("/me", method: .delete)
    }
}

extension APIClient {
    func pendingRevisions() async throws -> [PlanRevisionDTO] {
        try await send("/plan-revisions/pending", method: .get)
    }

    func revision(id: String) async throws -> PlanRevisionDTO {
        try await send("/plan-revisions/\(id)", method: .get)
    }

    func uploadProposal(revisionId: String, phases: [DraftPhaseDTO], source: String) async throws -> PlanRevisionDTO {
        try await send("/plan-revisions/\(revisionId)/proposal", method: .post,
                       body: ProposalUploadRequest(phases: phases, source: source))
    }

    func respondToRevision(id: String, action: String, rejectionReason: String? = nil) async throws -> PlanRevisionDTO {
        try await send("/plan-revisions/\(id)/respond", method: .post,
                       body: RevisionRespondRequest(action: action, rejectionReason: rejectionReason))
    }
}

enum DevJWT {
    static func make(sub: String, email: String, name: String) throws -> String {
        let header: [String: Any] = ["alg": "none", "typ": "JWT"]
        let payload: [String: Any] = [
            "sub": sub,
            "email": email,
            "name": name,
            "aud": "com.equinox.app",
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString())."
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
