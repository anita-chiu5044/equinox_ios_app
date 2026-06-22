import Foundation

struct InsightsDTO: Codable, Equatable {
    let stats: [InsightStatDTO]
    let peakHours: [Int]
    let rhythm: [Double]
    let capacitySeries: [Int]
    let doneSeries: [Int]
    let adjustments: [String]
    let timeBias: Double?
    let healthAnalysis: HealthAnalysisDTO

    enum CodingKeys: String, CodingKey {
        case stats
        case peakHours = "peak_hours"
        case rhythm
        case capacitySeries = "capacity_series"
        case doneSeries = "done_series"
        case adjustments
        case timeBias = "time_bias"
        case healthAnalysis = "health_analysis"
    }
}

struct HealthAnalysisDTO: Codable, Equatable {
    let checkinDays: Int
    let averageEnergyScore: Double?
    let trend: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case checkinDays = "checkin_days"
        case averageEnergyScore = "average_energy_score"
        case trend
        case summary
    }
}

struct InsightStatDTO: Codable, Identifiable, Equatable {
    var id: String {
        "\(n)-\(unit)-\(sub)"
    }

    let n: String
    let unit: String
    let sub: String
}
