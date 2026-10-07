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

struct TimeRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var category: String
    var activity: String
    var seconds: Int
    var note = ""
    static let categories = ["学习", "工作", "运动", "阅读", "家务", "通勤", "休闲", "其他"]
    static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds), h = value / 3600, m = value % 3600 / 60, s = value % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)小时") }
        if m > 0 { parts.append("\(m)分钟") }
        if s > 0 || parts.isEmpty { parts.append("\(s)秒") }
        return parts.joined()
    }
    static func clock(_ seconds: Int) -> String { String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) }
    var searchable: String { [day, category, activity, note].joined(separator: " ") }
}

struct TimeEditorDraft: Identifiable {
    enum Mode { case manual, timer }
    let id = UUID()
    let record: TimeRecord
    let mode: Mode
    var startingTimer: Bool { mode == .timer }
}

struct TimeSpan: Codable, Equatable {
    var start: Date
    var end: Date
}

struct ActivityTimer: Codable, Equatable {
    var category: String
    var activity: String
    var note = ""
    var spans: [TimeSpan] = []
    var runningSince: Date?
    func elapsed(at now: Date) -> Int {
        Int(spans.reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) } + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0))
    }
    private mutating func pause(at now: Date) {
        if let start = runningSince { spans.append(TimeSpan(start: start, end: max(start, now))); runningSince = nil }
    }
    mutating func stop(at now: Date) throws {
        if let start = runningSince {
            guard now >= start else { throw LogError.clockChanged }
            guard now.timeIntervalSince(start) <= 31 * 86400 else { throw LogError.timerTooLong }
            pause(at: now)
        }
    }
    mutating func resume(at now: Date) throws {
        guard runningSince == nil else { return }
        guard spans.last.map({ now >= $0.end }) ?? true else { throw LogError.clockChanged }
        runningSince = now
    }
    func finished(at now: Date) throws -> [TimeRecord] {
        var copy = self; try copy.stop(at: now)
        var totals: [String: Double] = [:]
        let calendar = Calendar(identifier: .gregorian)
        for span in copy.spans {
            guard span.end.timeIntervalSince(span.start) <= 31 * 86400 else { throw LogError.timerTooLong }
            var cursor = span.start
            while cursor < span.end {
                let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
                let end = min(midnight, span.end)
                totals[Days.key(cursor), default: 0] += end.timeIntervalSince(cursor)
                cursor = end
            }
        }
        // Round the session once, then distribute leftover seconds by largest remainder.
        // Per-day flooring would lose a second for 0.6s + 0.6s over midnight.
        let target = copy.elapsed(at: now)
        var secondsByDay = totals.mapValues { Int($0) }
        let remainder = target - secondsByDay.values.reduce(0, +)
        let ranked = totals.keys.sorted {
            let a = totals[$0]! - floor(totals[$0]!), b = totals[$1]! - floor(totals[$1]!)
            return a == b ? $0 < $1 : a > b
        }
        for day in ranked.prefix(max(0, remainder)) { secondsByDay[day, default: 0] += 1 }
        let records = totals.keys.sorted().compactMap { day -> TimeRecord? in
            let seconds = secondsByDay[day]!
            return seconds > 0 ? TimeRecord(day: day, category: category, activity: activity, seconds: seconds, note: note) : nil
        }
        guard !records.isEmpty else { throw LogError.emptyTime }; return records
    }
}

struct Backup: Codable, Equatable {
    var version = 2
    var journals: [Journal] = []
    var expenses: [Expense] = []
    var reviews: [Review] = []
    var times: [TimeRecord] = []
    var activeTimer: ActivityTimer?
    init() {}
    enum CodingKeys: String, CodingKey { case version, journals, expenses, reviews, times, activeTimer }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try c.decode(Int.self, forKey: .version)
        guard decodedVersion == 1 || decodedVersion == 2 else { throw LogError.invalidBackup }
        version = 2
        journals = try c.decode([Journal].self, forKey: .journals)
        expenses = try c.decode([Expense].self, forKey: .expenses)
        reviews = try c.decode([Review].self, forKey: .reviews)
        // v1.0 files have no time records; keep every existing journal and expense.
        times = try c.decodeIfPresent([TimeRecord].self, forKey: .times) ?? []
        activeTimer = try c.decodeIfPresent(ActivityTimer.self, forKey: .activeTimer)
    }
    func statistics(for days: [String]) -> [TimeRecord] {
        var result = times.filter { days.contains($0.day) }
        for j in journals where days.contains(j.id) && j.minutes > 0 {
            if !times.contains(where: { $0.day == j.id }) {
                result.append(TimeRecord(day: j.id, category: "学习", activity: "日志学习时间", seconds: j.minutes * 60, note: "来自旧版学习分钟；新增时间记录后，该日完全使用明细统计。"))
            }
        }
        return result
    }
    func validated() throws -> Backup {
        guard version == 2, journals.count <= 100_000, expenses.count <= 100_000,
              Set(journals.map(\.id)).count == journals.count,
              Set(expenses.map(\.id)).count == expenses.count,
              times.count <= 100_000, Set(times.map(\.id)).count == times.count,
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
        for t in times {
            guard Days.date(t.day) != nil, (1...90000).contains(t.seconds),
                  !t.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.category.count <= 40,
                  !t.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.activity.count <= 200,
                  t.note.count <= 10000 else { throw LogError.invalidBackup }
        }
        for (day, records) in Dictionary(grouping: times, by: \.day) {
            let start = Days.date(day)!
            let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: start)!
            guard records.reduce(0, { $0 + $1.seconds }) <= Int(end.timeIntervalSince(start)) else { throw LogError.tooMuchTime }
        }
        if let timer = activeTimer {
            guard !timer.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, timer.category.count <= 40,
                  !timer.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, timer.activity.count <= 200,
                  timer.note.count <= 10000, timer.spans.count <= 10000 else { throw LogError.invalidBackup }
            var previous: Date?
            for span in timer.spans {
                guard span.start.timeIntervalSinceReferenceDate.isFinite, span.end.timeIntervalSinceReferenceDate.isFinite,
                      span.end >= span.start, span.end.timeIntervalSince(span.start) <= 31 * 86400,
                      previous.map({ span.start >= $0 }) ?? true else { throw LogError.invalidBackup }
                previous = span.end
            }
            if let since = timer.runningSince {
                guard since.timeIntervalSinceReferenceDate.isFinite, abs(since.timeIntervalSinceReferenceDate) < 1e10,
                      previous.map({ since >= $0 }) ?? true else { throw LogError.invalidBackup }
            }
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
        var timesByID = Dictionary(uniqueKeysWithValues: times.map { ($0.id, $0) })
        for j in incoming.journals { journalsByID[j.id] = j }
        for e in incoming.expenses { expensesByID[e.id] = e }
        for r in incoming.reviews { reviewsByID[r.id] = r }
        for t in incoming.times { timesByID[t.id] = t }
        copy.journals = journalsByID.values.sorted { $0.id < $1.id }
        copy.expenses = expensesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        copy.reviews = reviewsByID.values.sorted { $0.id < $1.id }
        copy.times = timesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        return try copy.validated()
    }
}

enum LogError: LocalizedError {
    case invalidBackup, locked, empty, large, emptyTime, tooMuchTime, timerTooLong, clockChanged
    var errorDescription: String? {
        switch self {
        case .invalidBackup: return "数据格式不正确或版本不支持，未修改现有记录。"
        case .locked: return "原始数据无法读取，已暂停写入。请先导出原始文件，再导入有效备份恢复。"
        case .empty: return "写下一项内容，就可以保存今天。"
        case .large: return "备份超过 20 MB，请选择较小的文件。"
        case .emptyTime: return "请至少记录 1 秒时间。"
        case .tooMuchTime: return "该日记录的总时长超过一天，请检查是否重复补记。计时器会保留，修正后可再结束保存。"
        case .timerTooLong: return "这段计时超过 31 天，请放弃本次计时并按实际情况手动补记。"
        case .clockChanged: return "设备时间早于计时起点或上次暂停时间。计时状态未改变，请校正设备时间，或放弃本次计时并手动补记。"
        }
    }
}

final class Library {
    let url: URL
    private(set) var data: Backup
    private let write: (Data, URL) throws -> Void
    init(url: URL, write: @escaping (Data, URL) throws -> Void = { data, url in try data.write(to: url, options: .atomic) }) throws {
        self.url = url
        self.write = write
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
        try write(raw, url)
        data = next
    }
    func finishTimer(at now: Date) throws {
        guard var timer = data.activeTimer else { return }
        try timer.stop(at: now)
        // Freeze and persist the final timestamp before creating records. If saving
        // the records fails, retry uses this same paused duration rather than now.
        if timer != data.activeTimer {
            var paused = data; paused.activeTimer = timer; try save(paused)
        }
        let records = try timer.finished(at: now)
        var next = data; next.times.append(contentsOf: records); next.activeTimer = nil
        try save(next)
    }
}
