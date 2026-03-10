import Foundation

private let olderDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter
}()

func relativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    if interval < 604800 { return "\(Int(interval / 86400))d" }
    return olderDateFormatter.string(from: date)
}

func formatCount(_ count: Int?) -> String {
    guard let count, count > 0 else { return "" }
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
}
