import Foundation

struct ComplianceReport {
    let period: String
    let totalBreaks: Int
    let completedBreaks: Int
    let skippedBreaks: Int
    let complianceRate: Double
    let averagePerDay: Double
}

func calculateComplianceRate(completed: Int, total: Int) -> Double {
    guard total > 0 else { return 0 }
    return (Double(completed) / Double(total)) * 100
}
