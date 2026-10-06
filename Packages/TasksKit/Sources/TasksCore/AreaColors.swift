/// Area colors are stored by name (e.g. "Terracotta"), not by value, so the palette
/// can be tuned later. Each platform maps the name to its light/dark values; see
/// design/palette-preview.html for the current values.
public enum AreaColors {
    /// Palette order; also the order new areas get colors in.
    public static let names = [
        "Terracotta", "Sage", "Slate", "Ochre", "Plum", "Rose", "Teal", "Olive", "Clay", "Iris",
    ]

    public static let fallback = "Slate"

    /// The first palette color no area in `used` has yet; cycles once all are taken.
    public static func nextUnused(after used: [String]) -> String {
        if let free = names.first(where: { !used.contains($0) }) { return free }
        return names[used.count % names.count]
    }

    /// Before named colors, areas stored a hex value from an earlier palette. Maps
    /// those to the closest named color (any other value → `fallback`).
    public static func name(forLegacyHex hex: String) -> String {
        switch hex.uppercased() {
        case "#E5484D": "Terracotta"  // red
        case "#F76B15": "Clay"  // orange
        case "#E2A336": "Ochre"  // amber
        case "#46A758": "Sage"  // green
        case "#12A594": "Teal"
        case "#0090FF": "Slate"  // blue
        case "#3E63DD": "Iris"  // indigo
        case "#8E4EC6": "Plum"  // purple
        case "#D6409F": "Rose"  // pink
        case "#8D8D8D": "Olive"  // grey
        default: fallback
        }
    }
}
