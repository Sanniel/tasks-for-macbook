import GRDB
import TasksCore

/// SQLite schema. Kept deliberately portable (to Android/SQLite or a web backend):
/// - ids are lowercase UUID strings
/// - timestamps are GRDB's default text format, UTC: `YYYY-MM-DD HH:MM:SS.SSS`
/// - startDate/dueDate are `YYYY-MM-DD` text
/// - recurrence is a JSON text column (see `RecurrenceRule`)
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "area") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("colorHex", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("archivedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "task") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("areaId", .text).notNull().indexed()
                    .references("area", onDelete: .cascade)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("startDate", .text)
                t.column("dueDate", .text)
                t.column("recurrence", .text)
                t.column("completedAt", .datetime)
                t.column("archivedAt", .datetime)
                t.column("archivedWithArea", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "subtask") { t in
                t.primaryKey("id", .text)
                t.column("taskId", .text).notNull().indexed()
                    .references("task", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("isDone", .boolean).notNull().defaults(to: false)
                t.column("sortOrder", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "tombstone") { t in
                t.primaryKey("id", .text)
                t.column("entityType", .text).notNull()
                t.column("deletedAt", .datetime).notNull().indexed()
            }
        }

        migrator.registerMigration("v2-previousOccurrence") { db in
            try db.alter(table: "task") { t in
                // No foreign key: the previous occurrence may be purged before this one.
                t.add(column: "previousOccurrenceId", .text)
            }
        }

        // Area colors become palette names instead of hex values (see AreaColors).
        migrator.registerMigration("v3-areaColorName") { db in
            try db.alter(table: "area") { t in
                t.add(column: "colorName", .text).notNull().defaults(to: AreaColors.fallback)
            }
            let rows = try Row.fetchAll(db, sql: "SELECT id, colorHex FROM area")
            for row in rows {
                let hex: String = row["colorHex"]
                try db.execute(
                    sql: "UPDATE area SET colorName = ? WHERE id = ?",
                    arguments: [AreaColors.name(forLegacyHex: hex), row["id"] as String])
            }
            try db.alter(table: "area") { t in t.drop(column: "colorHex") }
        }

        return migrator
    }
}
