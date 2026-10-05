/// Stored task priority. The raw value is what's persisted and exported.
///
/// | Value | Name   |
/// |-------|--------|
/// | 3     | Urgent |
/// | 2     | High   |
/// | 1     | Raised |
/// | 0     | Normal (default) |
/// | -1    | Low    |
public enum Priority: Int, CaseIterable, Codable, Sendable, Comparable {
    case low = -1
    case normal = 0
    case raised = 1
    case high = 2
    case urgent = 3

    public var name: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .raised: "Raised"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}
