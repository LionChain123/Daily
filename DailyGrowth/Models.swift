import Foundation

enum Days {
    static func key(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    static func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let d = f.date(from: key), self.key(d) == key else { return nil }; return d
    }
    static func week(_ date: Date) -> [String] {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2
        let start = c.startOfDay(for: date)
        let monday = c.date(byAdding: .day, value: -((c.component(.weekday, from: date) + 5) % 7), to: start)!
        return (0..<7).map { key(c.date(byAdding: .day, value: $0, to: monday)!) }
    }
}

struct Journal: Codable, Identifiable, Equatable {
    var id: String
    var intention = ""
    var topic = ""
    var questions = ""
    var notes = ""
    var summary = ""
    var minutes = 0
    var work = ""
    var result = ""
    var nextStep = ""
    var win = ""
    var improvement = ""
    var tomorrow = ""
    var thoughts = ""
    var mood = "未记录"
    var updatedAt = Date()
    var hasContent: Bool {
        [intention, topic, questions, notes, summary, work, result, nextStep, win, improvement, tomorrow, thoughts]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } || minutes > 0 || mood != "未记录"
    }
    var searchable: String { [id, intention, topic, questions, notes, summary, work, result, nextStep, win, improvement, tomorrow, thoughts, mood].joined(separator: " ") }
}

struct Expense: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var cents: Int
    var category: String
    var note: String
    static let categories = ["餐饮", "交通", "购物", "居住", "学习", "健康", "娱乐", "其他"]
    static func parse(_ input: String) -> Int? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else { return nil }
        let parts = s.split(separator: ".")
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard let whole = Int(parts[0]), let decimal = Int(fraction.isEmpty ? "0" : fraction.padding(toLength: 2, withPad: "0", startingAt: 0)) else { return nil }
        let cents = whole * 100 + decimal
        return cents > 0 && cents <= 999_999_999 ? cents : nil
    }
    static func money(_ cents: Int) -> String { String(format: "¥%d.%02d", cents / 100, cents % 100) }
}

struct Review: Codable, Identifiable, Equatable {
    var id: String
    var achievement = ""
    var lesson = ""
    var action = ""
}

struct Backup: Codable, Equatable {
    var version = 1
    var journals: [Journal] = []
    var expenses: [Expense] = []
    var reviews: [Review] = []
    func validated() throws -> Backup {
        guard version == 1, journals.count <= 100_000, expenses.count <= 100_000,
              Set(journals.map(\.id)).count == journals.count,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(reviews.map(\.id)).count == reviews.count else { throw LogError.invalidBackup }
        for j in journals {
            guard Days.date(j.id) != nil, (0...1440).contains(j.minutes), j.searchable.count <= 200_000,
                  ["未记录", "低落", "疲惫", "平静", "充实", "开心"].contains(j.mood) else { throw LogError.invalidBackup }
        }
        for e in expenses {
            guard Days.date(e.day) != nil, (1...999_999_999).contains(e.cents),
                  Expense.categories.contains(e.category), e.note.count <= 10_000 else { throw LogError.invalidBackup }
        }
        for r in reviews {
            guard let day = Days.date(r.id), Days.week(day).first == r.id,
                  r.achievement.count + r.lesson.count + r.action.count <= 100_000 else { throw LogError.invalidBackup }
        }
        return self
    }
    func merging(_ incoming: Backup) throws -> Backup {
        _ = try incoming.validated()
        _ = try validated()
        var copy = self
        var journalsByID = Dictionary(uniqueKeysWithValues: journals.map { ($0.id, $0) })
        var expensesByID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
        var reviewsByID = Dictionary(uniqueKeysWithValues: reviews.map { ($0.id, $0) })
        for j in incoming.journals { journalsByID[j.id] = j }
        for e in incoming.expenses { expensesByID[e.id] = e }
        for r in incoming.reviews { reviewsByID[r.id] = r }
        copy.journals = journalsByID.values.sorted { $0.id < $1.id }
        copy.expenses = expensesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.reviews = reviewsByID.values.sorted { $0.id < $1.id }
        return try copy.validated()
    }
}

enum LogError: LocalizedError {
    case invalidBackup, locked, empty, large
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "数据格式不正确或版本不支持，未修改现有记录。"
        case .locked: return "原始数据无法读取，已暂停写入。请先导出原始文件，再导入有效备份恢复。"
        case .empty: return "写下一项内容，就可以保存今天。"
        case .large: return "备份超过 20 MB，请选择较小的文件。"
        }
    }
}

final class Library {
    let url: URL
    private(set) var data: Backup
    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            data = try Self.decode(Data(contentsOf: url))
        } else { data = Backup() }
    }
    static func decode(_ raw: Data) throws -> Backup {
        guard raw.count <= 20 * 1024 * 1024 else { throw LogError.large }
        return try JSONDecoder().decode(Backup.self, from: raw).validated()
    }
    static func encode(_ data: Backup) throws -> Data {
        _ = try data.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let raw = try encoder.encode(data)
        guard raw.count <= 20 * 1024 * 1024 else { throw LogError.large }
        return raw
    }
    func save(_ next: Backup) throws {
        let raw = try Self.encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: url, options: .atomic)
        data = next
    }
}
