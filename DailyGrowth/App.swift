import SwiftUI
import Combine
import UniformTypeIdentifiers

@main
struct DailyGrowthApp: App {
    @StateObject private var store = LogStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Palette.lime)
                .preferredColorScheme(.dark)
                .alert("记录提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}

enum Palette {
    static let lime = Color(red: 0.79, green: 0.96, blue: 0.35)
    static let background = Color(red: 0.055, green: 0.065, blue: 0.065)
    static let panel = Color(red: 0.10, green: 0.12, blue: 0.12)
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var data = Backup()
    @Published var error: String?
    @Published private(set) var locked = false
    private var library: Library?
    let fileURL: URL
    init() {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyGrowth/records.json")
        do { let lib = try Library(url: fileURL); library = lib; data = lib.data }
        catch { locked = true; self.error = LogError.locked.localizedDescription }
    }
    func journal(_ day: String) -> Journal { data.journals.first { $0.id == day } ?? Journal(id: day) }
    @discardableResult func commit(_ next: Backup) -> Bool {
        do {
            guard !locked, let library else { throw LogError.locked }
            try library.save(next); data = next; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func save(_ journal: Journal) -> Bool {
        guard journal.hasContent else { error = LogError.empty.localizedDescription; return false }
        var next = data; var j = journal; j.updatedAt = Date()
        next.journals.removeAll { $0.id == j.id }; next.journals.append(j); return commit(next)
    }
    func save(_ expense: Expense) -> Bool {
        var next = data; next.expenses.removeAll { $0.id == expense.id }; next.expenses.append(expense); return commit(next)
    }
    func save(_ review: Review) -> Bool {
        var next = data; next.reviews.removeAll { $0.id == review.id }; next.reviews.append(review); return commit(next)
    }
    func deleteJournal(_ day: String) { var next = data; next.journals.removeAll { $0.id == day }; _ = commit(next) }
    func deleteExpense(_ id: UUID) { var next = data; next.expenses.removeAll { $0.id == id }; _ = commit(next) }
    func save(_ record: TimeRecord) -> Bool {
        var t = record
        t.category = t.category.trimmingCharacters(in: .whitespacesAndNewlines)
        t.activity = t.activity.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = data; next.times.removeAll { $0.id == t.id }; next.times.append(t); return commit(next)
    }
    func deleteTime(_ id: UUID) { var next = data; next.times.removeAll { $0.id == id }; _ = commit(next) }
    func startTimer(_ record: TimeRecord) -> Bool {
        guard data.activeTimer == nil else { error = "请先结束正在进行的计时。"; return false }
        var next = data
        next.activeTimer = ActivityTimer(category: record.category.trimmingCharacters(in: .whitespacesAndNewlines), activity: record.activity.trimmingCharacters(in: .whitespacesAndNewlines), note: record.note, runningSince: Date())
        return commit(next)
    }
    func pauseTimer() {
        guard var timer = data.activeTimer else { return }
        do { try timer.stop(at: Date()); var next = data; next.activeTimer = timer; _ = commit(next) }
        catch { self.error = error.localizedDescription }
    }
    func resumeTimer() {
        guard var timer = data.activeTimer, timer.runningSince == nil else { return }
        do { try timer.resume(at: Date()); var next = data; next.activeTimer = timer; _ = commit(next) }
        catch { self.error = error.localizedDescription }
    }
    func finishTimer() {
        do {
            guard !locked, let library else { throw LogError.locked }
            try library.finishTimer(at: Date()); data = library.data
        } catch { if let library { data = library.data }; self.error = error.localizedDescription }
    }
    func discardTimer() { var next = data; next.activeTimer = nil; _ = commit(next) }
    func export() throws -> URL {
        let raw = locked ? try Data(contentsOf: fileURL) : try Library.encode(data)
        let name = locked ? "拾日-原始数据" : "拾日-备份"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(Days.key(Date()))-\(UUID().uuidString.prefix(8)).json")
        try raw.write(to: destination, options: .atomic); return destination
    }
    func restore(_ incoming: Backup) -> Bool {
        do {
            let next = try data.merging(incoming)
            if locked {
                let preserved = fileURL.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: preserved)
                let raw = try Library.encode(next); try raw.write(to: fileURL, options: .atomic)
                library = try Library(url: fileURL); data = next; locked = false; return true
            }
            let before = fileURL.deletingLastPathComponent().appendingPathComponent("before-import-\(UUID().uuidString).json")
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.copyItem(at: fileURL, to: before) }
            return commit(next)
        } catch { self.error = error.localizedDescription; return false }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("今日", systemImage: "sun.max") }
            HistoryView().tabItem { Label("日志", systemImage: "book.closed") }
            TimeTrackingView().tabItem { Label("时间", systemImage: "clock") }
            ReviewView().tabItem { Label("回顾", systemImage: "chart.bar.xaxis") }
            SettingsView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.07)))
    }
}
