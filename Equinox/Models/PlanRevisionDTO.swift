import Foundation

struct PlanRevisionDTO: Codable, Identifiable {
    let id: String
    let goalId: String
    let trigger: String
    let triggerDetail: String
    let status: String  // awaiting_generation | pending_response | applied | rejected | stale
    let aiDraft: AIDraftDTO?
    let diff: RevisionDiffDTO?
    let outcome: String?
    let rejectionReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, trigger, status, outcome, diff
        case goalId = "goal_id"
        case triggerDetail = "trigger_detail"
        case aiDraft = "ai_draft"
        case rejectionReason = "rejection_reason"
        case createdAt = "created_at"
    }
}

struct AIDraftDTO: Codable {
    let phases: [DraftPhaseDTO]
    let source: String
}

struct DraftPhaseDTO: Codable {
    let name: String
    let sessions: [DraftSessionDTO]
}

struct DraftSessionDTO: Codable {
    let title: String
    let minutes: Int
    let priority: String
    let difficulty: Int
    let emoji: String?
}

struct RevisionDiffDTO: Codable {
    let added: [DiffSessionDTO]
    let removed: [DiffSessionDTO]
    let modified: [DiffModifiedDTO]
    let preservedDone: [DiffSessionDTO]
    let totalBefore: Int
    let totalAfter: Int
    let minutesBefore: Int
    let minutesAfter: Int

    enum CodingKeys: String, CodingKey {
        case added, removed, modified
        case preservedDone = "preserved_done"
        case totalBefore = "total_before"
        case totalAfter = "total_after"
        case minutesBefore = "minutes_before"
        case minutesAfter = "minutes_after"
    }
}

struct DiffSessionDTO: Codable {
    let title: String
    let minutes: Int
    let priority: String
}

struct DiffModifiedDTO: Codable {
    let title: String
    let minutesBefore: Int
    let minutesAfter: Int

    enum CodingKeys: String, CodingKey {
        case title
        case minutesBefore = "minutes_before"
        case minutesAfter = "minutes_after"
    }
}

struct ProposalUploadRequest: Encodable {
    let phases: [DraftPhaseDTO]
    let source: String
}

struct RevisionRespondRequest: Encodable {
    let action: String  // accept | edit | reject
    let rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case action
        case rejectionReason = "rejection_reason"
    }
}
