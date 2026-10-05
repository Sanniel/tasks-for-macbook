import Foundation
import Testing
@testable import TasksCore

@Suite struct PurgeTests {
    let now = instant("2026-10-31")
    let area = Area(name: "Private", colorHex: "#FF0000", sortOrder: 0)

    private func task(completed: String? = nil, archived: String? = nil, area: Area? = nil) -> TaskItem {
        var t = TaskItem(title: "t", areaID: (area ?? self.area).id)
        t.completedAt = completed.map { instant($0) }
        t.archivedAt = archived.map { instant($0) }
        return t
    }

    @Test func retentionIsOneConstant() {
        #expect(Retention.purgeAfterDays == 30)
    }

    @Test func completedTasksPurgedAfterThirtyDays() {
        let thirtyDays = task(completed: "2026-10-01")    // exactly 30 days before now
        let twentyNine = task(completed: "2026-10-02")
        let open = task()
        let plan = Purge.plan(areas: [area], tasks: [thirtyDays, twentyNine, open], now: now, calendar: utc)
        #expect(plan.purgedTaskIDs == [thirtyDays.id])
        #expect(plan.purgedAreaIDs.isEmpty)
    }

    @Test func archivedTasksPurgedAfterThirtyDays() {
        let old = task(archived: "2026-09-15")
        let recent = task(archived: "2026-10-20")
        let plan = Purge.plan(areas: [area], tasks: [old, recent], now: now, calendar: utc)
        #expect(plan.purgedTaskIDs == [old.id])
    }

    @Test func completedThenArchivedKeptUntilLaterDate() {
        let t = task(completed: "2026-09-01", archived: "2026-10-20")
        #expect(Purge.plan(areas: [area], tasks: [t], now: now, calendar: utc).purgedTaskIDs.isEmpty)
    }

    @Test func archivedAreaPurgedWithItsTasks() {
        var oldArea = Area(name: "Old", colorHex: "#00FF00", sortOrder: 1)
        oldArea.archivedAt = instant("2026-09-20")
        let inOldArea = task(completed: "2026-10-30", area: oldArea)
        let plan = Purge.plan(areas: [area, oldArea], tasks: [inOldArea], now: now, calendar: utc)
        #expect(plan.purgedAreaIDs == [oldArea.id])
        // Not listed separately: the repository purges an area's tasks with it.
        #expect(plan.purgedTaskIDs.isEmpty)
    }

    @Test func daysUntilPurge() {
        let archived = instant("2026-10-31", hour: 9)
        #expect(Retention.daysUntilPurge(after: archived, now: instant("2026-10-31", hour: 23), calendar: utc) == 30)
        #expect(Retention.daysUntilPurge(after: archived, now: instant("2026-11-29"), calendar: utc) == 1)
        #expect(Retention.daysUntilPurge(after: archived, now: instant("2026-11-30"), calendar: utc) == 0)
        #expect(Retention.daysUntilPurge(after: archived, now: instant("2026-12-15"), calendar: utc) == 0)
    }
}
