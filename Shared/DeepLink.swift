import Foundation

/// URLs the widget uses to open the app (scheme registered in Config/Tasks-Info.plist).
///
///     fi.sannier.tasks://add              quick add
///     fi.sannier.tasks://add?area=<uuid>  quick add in an area
///     fi.sannier.tasks://task/<uuid>      show a task
enum DeepLink: Equatable {
    case add(areaID: UUID?)
    case task(UUID)

    static let scheme = "fi.sannier.tasks"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .add(let areaID):
            components.host = "add"
            if let areaID {
                components.queryItems = [URLQueryItem(name: "area", value: areaID.uuidString)]
            }
        case .task(let id):
            components.host = "task"
            components.path = "/" + id.uuidString
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.host {
        case "add":
            let area = components.queryItems?.first { $0.name == "area" }?.value
            self = .add(areaID: area.flatMap(UUID.init(uuidString:)))
        case "task":
            guard let id = UUID(uuidString: String(components.path.dropFirst())) else { return nil }
            self = .task(id)
        default:
            return nil
        }
    }
}
