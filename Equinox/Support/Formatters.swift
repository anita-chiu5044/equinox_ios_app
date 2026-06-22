import Foundation

enum Formatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

extension Date {
    var shortDisplay: String {
        Formatters.shortDate.string(from: self)
    }

    var timeDisplay: String {
        Formatters.time.string(from: self)
    }
}
