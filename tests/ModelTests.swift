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
        print("PASS: currency, dates, persistence, backup, merge, validation and corrupt-file protection")
    }
}
