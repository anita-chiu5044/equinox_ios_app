import Foundation

/// Offline-first write path: try the backend; if the network is down,
/// apply the change to the local cache and queue it for replay.
/// Reads stay in the ViewModels (cache-first, then refresh).
@MainActor
final class SyncService {
    static let shared = SyncService()

    private let api: APIClient
    private let store: LocalStore
    private var isReplaying = false

    init(api: APIClient? = nil, store: LocalStore? = nil) {
        self.api = api ?? .shared
        self.store = store ?? .shared
    }

    // MARK: Mutations

    /// Returns `true` when the backend accepted the write, `false` when it
    /// was queued locally for later replay.
    @discardableResult
    func completeSession(id: String, actualMinutes: Int?, familiarity: Int? = nil) async throws -> Bool {
        do {
            _ = try await api.updateSession(id: id, request: .done(actualMinutes: actualMinutes, familiarity: familiarity))
            store.markSessionDone(id: id, actualMinutes: actualMinutes)
            if let familiarity { store.setFamiliarity(id: id, value: familiarity) }
            return true
        } catch let error as APIError {
            guard case .transport = error else {
                throw error
            }
            store.markSessionDone(id: id, actualMinutes: actualMinutes)
            store.enqueue(PendingMutation(
                kind: "complete_session",
                targetId: id,
                intValue: actualMinutes,
                secondIntValue: familiarity
            ))
            return false
        }
    }

    @discardableResult
    func setFamiliarity(id: String, value: Int) async throws -> Bool {
        do {
            _ = try await api.updateSession(id: id, request: .familiarity(value))
            store.setFamiliarity(id: id, value: value)
            return true
        } catch let error as APIError {
            guard case .transport = error else {
                throw error
            }
            store.setFamiliarity(id: id, value: value)
            store.enqueue(PendingMutation(
                kind: "set_familiarity",
                targetId: id,
                intValue: value
            ))
            return false
        }
    }

    @discardableResult
    func checkIn(energy: String) async throws -> Bool {
        do {
            let checkin = try await api.createCheckin(energy: energy)
            store.cacheCheckin(checkin)
            return true
        } catch let error as APIError {
            guard case .transport = error else {
                throw error
            }
            let today = ISO8601DateFormatter.dateOnly.string(from: .now)
            store.cacheCheckin(CheckinDTO(id: "pending-\(today)", date: today, energy: energy))
            store.enqueue(PendingMutation(kind: "checkin", stringValue: energy))
            return false
        }
    }

    // MARK: Replay

    /// Replays queued mutations in order. Stops at the first network
    /// failure; non-network failures (e.g. 404) drop the mutation so the
    /// queue can't wedge.
    func replayPending() async {
        guard !isReplaying else {
            return
        }
        isReplaying = true
        defer { isReplaying = false }

        for mutation in store.pendingMutations() {
            do {
                switch mutation.kind {
                case "complete_session":
                    if let id = mutation.targetId {
                        _ = try await api.updateSession(
                            id: id,
                            request: .done(actualMinutes: mutation.intValue, familiarity: mutation.secondIntValue)
                        )
                    }
                case "set_familiarity":
                    if let id = mutation.targetId, let value = mutation.intValue {
                        _ = try await api.updateSession(id: id, request: .familiarity(value))
                    }
                case "checkin":
                    if let energy = mutation.stringValue {
                        _ = try await api.createCheckin(energy: energy)
                    }
                default:
                    break
                }
                store.remove(mutation)
            } catch let error as APIError {
                if case .transport = error {
                    return // still offline; retry on the next sync
                }
                store.remove(mutation) // permanent failure; drop it
            } catch {
                store.remove(mutation)
            }
        }
    }
}
