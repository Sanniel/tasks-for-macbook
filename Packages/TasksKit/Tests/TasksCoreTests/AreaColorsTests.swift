import Foundation
import Testing
@testable import TasksCore

@Suite struct AreaColorsTests {
    @Test func nextUnusedFollowsPaletteOrder() {
        #expect(AreaColors.nextUnused(after: []) == "Terracotta")
        #expect(AreaColors.nextUnused(after: ["Terracotta", "Slate"]) == "Sage")
        #expect(AreaColors.nextUnused(after: AreaColors.names) == "Terracotta")
    }

    @Test func legacyHexMapsToNames() {
        #expect(AreaColors.name(forLegacyHex: "#0090FF") == "Slate")
        #expect(AreaColors.name(forLegacyHex: "#e5484d") == "Terracotta")
        #expect(AreaColors.name(forLegacyHex: "#123456") == AreaColors.fallback)
    }

    @Test func version1BackupAreasDecodeWithColorNames() throws {
        let json = """
            {"format":"fi.sannier.tasks.backup","version":1,"exportedAt":"2026-10-06T08:00:00.000Z",
             "areas":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Private","colorHex":"#46A758",
                       "sortOrder":0,"createdAt":"2026-10-01T08:00:00.000Z","updatedAt":"2026-10-01T08:00:00.000Z"}],
             "tasks":[],"subtasks":[],"tombstones":[]}
            """
        let document = try Backup.decode(Data(json.utf8))
        #expect(document.areas.map(\.colorName) == ["Sage"])
    }
}
