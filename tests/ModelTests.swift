import Foundation

@main
struct ModelTests {
    static func main() throws {
        func check(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
        }
        check(Expense.parse("0.01") == 1, "smallest expense")
        check(Expense.parse("12.3") == 1230, "fraction padding")
        check(Expense.parse("12.34") == 1234, "exact cents")
        check(Expense.parse("9999999.99") == 999999999, "maximum")
        for invalid in ["0", "-1", "NaN", "1e3", "1.234", "1,20", "10000000", ".5"] {
            check(Expense.parse(invalid) == nil, "reject invalid amount: \(invalid)")
        }
        check(Days.date("2026-02-30") == nil, "invalid date")
        check(Days.week(Days.date("2026-10-05")!).first == "2026-10-05", "Monday")
        check(Days.week(Days.date("2026-10-11")!).first == "2026-10-05", "Sunday")
        check(Days.week(Days.date("2027-01-01")!).first == "2026-12-28", "year boundary")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("records.json")
        let library = try Library(url: url)
        var data = Backup()
        var j = Journal(id: "2026-10-05"); j.notes = "这是一次学习"; j.minutes = 35
        data.journals = [j]
        let e = Expense(day: j.id, cents: 1234, category: "学习", note: "书")
        data.expenses = [e]
        data.reviews = [Review(id: "2026-10-05", achievement: "完成笔记")]
        try library.save(data)
        check(try Library(url: url).data == data, "reopen persisted data")
        check(try Library.decode(Library.encode(data)) == data, "backup roundtrip")
        var changed = data; changed.journals[0].notes = "新版"
        let merged = try data.merging(changed)
        check(merged.journals.count == 1 && merged.journals[0].notes == "新版", "replace matching date")
        check(merged.expenses.count == 1, "deduplicate expense id")
        var more = Backup(); more.journals = [Journal(id: "2026-10-06", thoughts: "翌日")]
        check(try data.merging(more).journals.count == 2, "retain unrelated days")
        var bad = data; bad.expenses[0].cents = -1
        do { try library.save(bad); fatalError("accepted negative amount") } catch {}
        check(library.data == data, "failed validation must preserve memory")
        check(try Library(url: url).data == data, "failed validation must preserve disk")
        bad = data; bad.journals.append(j)
        do { _ = try bad.validated(); fatalError("accepted duplicate date") } catch {}
        let blockedURL = folder.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
        // A directory cannot be decoded as a data file; do not silently reset it.
        do { _ = try Library(url: blockedURL); fatalError("accepted unreadable file") } catch {}
        try Data("not json".utf8).write(to: url)
        do { _ = try Library(url: url); fatalError("accepted corrupt data") } catch {}
        check(try Data(contentsOf: url) == Data("not json".utf8), "corrupt file preserved")
        let oldJSON = try JSONSerialization.jsonObject(with: Library.encode(data)) as! [String: Any]
        var legacy = oldJSON; legacy["version"] = 1; legacy.removeValue(forKey: "times"); legacy.removeValue(forKey: "activeTimer")
        let upgraded = try Library.decode(JSONSerialization.data(withJSONObject: legacy))
        check(upgraded.journals == data.journals && upgraded.expenses == data.expenses && upgraded.times.isEmpty, "v1.0 migration")
        check(upgraded.version == 2, "upgrade backup schema")
        check(upgraded.statistics(for: [j.id]).reduce(0) { $0 + $1.seconds } == 35 * 60, "legacy learning fallback")
        var timed = upgraded
        let reading = TimeRecord(day: j.id, category: "学习", activity: "阅读", seconds: 1800)
        timed.times = [reading, TimeRecord(day: j.id, category: "工作", activity: "写方案", seconds: 3600)]
        check(timed.statistics(for: [j.id]).reduce(0) { $0 + $1.seconds } == 5400, "no duplicated legacy learning")
        var onlyWork = upgraded; onlyWork.times = [timed.times[1]]
        check(onlyWork.statistics(for: [j.id]).reduce(0) { $0 + $1.seconds } == 3600, "detailed records authoritative for entire day")
        check(try timed.merging(timed).times.count == 2, "time import idempotence")
        check(try Library.decode(Library.encode(timed)) == timed, "time persistence roundtrip")
        let midnight = Days.date("2026-10-06")!
        var timer = ActivityTimer(category: "工作", activity: "项目", runningSince: midnight.addingTimeInterval(-600))
        timer.pause(at: midnight.addingTimeInterval(300))
        check(timer.elapsed(at: midnight.addingTimeInterval(600)) == 900, "pause excludes elapsed gap")
        timer.runningSince = midnight.addingTimeInterval(600)
        let split = try timer.finished(at: midnight.addingTimeInterval(900))
        check(split.count == 2, "split midnight")
        check(split.first { $0.day == "2026-10-05" }?.seconds == 600, "before midnight")
        check(split.first { $0.day == "2026-10-06" }?.seconds == 600, "after midnight excludes pause")
        timed.activeTimer = timer
        check(try Library.decode(Library.encode(timed)).activeTimer == timer, "timer survives restart")
        var importedTimer = timed; importedTimer.activeTimer = nil
        check(try timed.merging(importedTimer).activeTimer == timer, "import preserves live local timer")
        var invalidTime = timed; invalidTime.times[0].seconds = 0
        do { _ = try invalidTime.validated(); fatalError("accepted zero duration") } catch {}
        invalidTime = timed; invalidTime.times.append(reading)
        do { _ = try invalidTime.validated(); fatalError("accepted duplicate time id") } catch {}
        invalidTime = timed; invalidTime.times = [TimeRecord(day: j.id, category: "工作", activity: "过长", seconds: 86400), reading]
        do { _ = try invalidTime.validated(); fatalError("accepted more than a day") } catch {}
        let tooLong = ActivityTimer(category: "工作", activity: "忘记结束", runningSince: midnight)
        do { _ = try tooLong.finished(at: midnight.addingTimeInterval(32 * 86400)); fatalError("accepted stale timer") } catch {}
        print("PASS: time migration, exact seconds, learning deduplication, time merge, midnight split, pause, timer restart and validation")
        print("PASS: currency, dates, persistence, backup, merge, validation and corrupt-file protection")
    }
}
