import SwiftUI
import Combine
import UniformTypeIdentifiers

struct TodayView: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            DayView(day: Days.key(now))
                .navigationTitle("拾日")
                .onReceive(clock) { now = $0 }
                .onChange(of: scenePhase) { _, phase in if phase == .active { now = Date() } }
                .toolbar { Text("把日子写成自己的成长").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct DayView: View {
    @EnvironmentObject var store: LogStore
    let day: String
    @State private var editor = false
    @State private var expenseDraft: Expense?
    @State private var deleting: Expense?
    var journal: Journal { store.journal(day) }
    var expenses: [Expense] { store.data.expenses.filter { $0.day == day } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(day).font(.subheadline.monospaced()).foregroundStyle(Palette.lime)
                Text(journal.hasContent ? "每一小步，\n都值得留下。" : "今天，\n留下一点成长。")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Text("早上定方向 · 白天随手记 · 晚上轻复盘").font(.subheadline).foregroundStyle(.secondary)
                Card {
                    HStack {
                        Label(journal.mood, systemImage: "face.smiling").foregroundStyle(Palette.lime)
                        Spacer()
                        Text("学习 \(TimeRecord.duration(store.data.statistics(for: [day]).filter { $0.category == "学习" }.reduce(0) { $0 + $1.seconds }))").font(.subheadline)
                    }
                    Text(journal.intention.isEmpty ? "今天最重要的一件事是什么？" : journal.intention).font(.title3.bold())
                    Button { editor = true } label: {
                        Label(journal.hasContent ? "编辑这一天" : "开始记录", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity).padding(8)
                    }.buttonStyle(.borderedProminent).tint(Palette.lime).foregroundStyle(.black)
                }
                if journal.hasContent {
                    Card {
                        Label("每日学习", systemImage: "graduationcap").font(.headline).foregroundStyle(.cyan)
                        Detail("主题", journal.topic); Detail("问题 / 线索", journal.questions)
                        Detail("笔记", journal.notes); Detail("用自己的话总结", journal.summary)
                    }
                    Card {
                        Label("工作与产出", systemImage: "briefcase").font(.headline).foregroundStyle(.orange)
                        Detail("做了什么", journal.work); Detail("产出 / 结果", journal.result); Detail("下一步 / 阻碍", journal.nextStep)
                    }
                    Card {
                        Label("个人成长", systemImage: "leaf").font(.headline).foregroundStyle(Palette.lime)
                        Detail("今天的收获", journal.win); Detail("可以改进", journal.improvement); Detail("明日一个小行动", journal.tomorrow)
                    }
                    if !journal.thoughts.isEmpty {
                        Card { Label("随想", systemImage: "quote.bubble").font(.headline); Text(journal.thoughts).textSelection(.enabled) }
                    }
                }
                Card {
                    HStack {
                        Label("日常支出", systemImage: "creditcard").font(.headline)
                        Spacer(); Text(Expense.money(expenses.reduce(0) { $0 + $1.cents })).font(.title3.bold()).foregroundStyle(Palette.lime)
                    }
                    if expenses.isEmpty { Text("买杯咖啡，也可以随手记一笔。").foregroundStyle(.secondary) }
                    ForEach(expenses) { expense in
                        HStack {
                            Button { expenseDraft = expense } label: {
                                HStack {
                                    VStack(alignment: .leading) { Text(expense.category); Text(expense.note.isEmpty ? "无备注" : expense.note).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Text(Expense.money(expense.cents)).monospacedDigit()
                                }
                            }.buttonStyle(.plain)
                            Button(role: .destructive) { deleting = expense } label: { Image(systemName: "trash").padding(8) }.accessibilityLabel("删除支出")
                        }
                        Divider()
                    }
                    Button { expenseDraft = Expense(day: day, cents: 0, category: "餐饮", note: "") } label: { Label("记一笔支出", systemImage: "plus") }
                }
                Card {
                    Label("时间花在哪里", systemImage: "clock").font(.headline)
                    let records = store.data.statistics(for: [day])
                    Text("已记录 \(TimeRecord.duration(records.reduce(0) { $0 + $1.seconds }))").font(.title3.bold()).foregroundStyle(Palette.lime)
                    NavigationLink("记录 / 查看这一天的时间") { TimeTrackingView(initialDate: Days.date(day) ?? Date(), embedded: true) }
                }
                Text("只记录有价值的内容。没感想的时候，可以留白。").font(.caption).foregroundStyle(.secondary).padding(.bottom)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Palette.background)
        .sheet(isPresented: $editor) { JournalEditor(journal: journal) }
        .sheet(item: $expenseDraft) { ExpenseEditor(expense: $0) }
        .alert("删除这笔支出？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { if let e = deleting { store.deleteExpense(e.id) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("删除后无法撤销。") }
    }
}

struct Detail: View {
    let title: String; let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(text).textSelection(.enabled) }
        }
    }
}

struct JournalEditor: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) var dismiss
    @State var journal: Journal
    @State private var discard = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("今天最重要的一件事", text: $journal.intention, axis: .vertical)
                    Picker("今天的状态", selection: $journal.mood) {
                        ForEach(["未记录", "低落", "疲惫", "平静", "充实", "开心"], id: \.self) { Text($0) }
                    }
                } header: { Text("晨间定方向") } footer: { Text("所有栏目都可留白，写一项也算记录。") }
                Section {
                    TextField("学习主题 / 材料", text: $journal.topic, axis: .vertical)
                    TextField("问题 / 关键词：我想弄懂什么？", text: $journal.questions, axis: .vertical)
                    TextField("笔记：重要概念、例子或证据", text: $journal.notes, axis: .vertical).lineLimit(3...12)
                    TextField("总结：合上资料，我能解释什么？", text: $journal.summary, axis: .vertical).lineLimit(2...8)
                    Stepper("学习时间（无明细时）：\(journal.minutes) 分钟", value: $journal.minutes, in: 0...1440, step: 5)
                    Text("同一天如有时间明细，统计完全采用明细，不重复累计这里的分钟；请在时间页分别记录学习和其他事项。").font(.caption).foregroundStyle(.secondary)
                } header: { Text("每日学习 · 康奈尔笔记简化版") }
                Section("工作 · 事项 → 结果 → 下一步") {
                    TextField("今天做了什么？可分行写多项", text: $journal.work, axis: .vertical).lineLimit(2...10)
                    TextField("留下了什么具体产出？", text: $journal.result, axis: .vertical).lineLimit(2...8)
                    TextField("下一步 / 需要解决的阻碍", text: $journal.nextStep, axis: .vertical)
                }
                Section("成长 · 晚间轻复盘") {
                    TextField("一件收获 / 做得好的事", text: $journal.win, axis: .vertical)
                    TextField("一个可改进的地方", text: $journal.improvement, axis: .vertical)
                    TextField("明天能执行的一个小行动", text: $journal.tomorrow, axis: .vertical)
                }
                Section("随想 · 选填") {
                    TextField("感受、灵感，或想留给未来的自己一句话", text: $journal.thoughts, axis: .vertical).lineLimit(4...15)
                }
            }.navigationTitle(journal.id).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") {
                    if journal != store.journal(journal.id) { discard = true } else { dismiss() }
                } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if store.save(journal) { dismiss() } else { failure = store.error; store.error = nil }
                }.disabled(!journal.hasContent || store.locked) }
            }
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
        }.interactiveDismissDisabled().saveError($failure)
    }
}

struct ExpenseEditor: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) var dismiss
    @State var expense: Expense
    @State private var amount = ""
    @State private var discard = false
    @State private var original: Expense?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(expense.day).foregroundStyle(.secondary)
                    TextField("金额（元）", text: $amount).keyboardType(.decimalPad)
                    Picker("分类", selection: $expense.category) { ForEach(Expense.categories, id: \.self) { Text($0) } }
                    TextField("备注（选填）", text: $expense.note, axis: .vertical)
                } footer: { Text("人民币支出，金额大于 0，最多两位小数。") }
            }.navigationTitle(expense.cents == 0 ? "记一笔" : "编辑支出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") {
                    if expense != original || amount != (original.map { $0.cents == 0 ? "" : String(format: "%.2f", Double($0.cents) / 100) } ?? "") { discard = true } else { dismiss() }
                } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    guard let cents = Expense.parse(amount) else { return }; expense.cents = cents
                    if store.save(expense) { dismiss() } else { failure = store.error; store.error = nil }
                }.disabled(Expense.parse(amount) == nil || store.locked) }
            }.onAppear { if original == nil { original = expense; amount = expense.cents == 0 ? "" : String(format: "%.2f", Double(expense.cents) / 100) } }
            .confirmationDialog("放弃尚未保存的修改？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
        }.interactiveDismissDisabled().saveError($failure)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: LogStore
    @State private var search = ""
    @State private var date = Date()
    @State private var removing: String?
    var days: [String] {
        let all = Set(store.data.journals.map(\.id) + store.data.expenses.map(\.day) + store.data.times.map(\.day))
        return all.filter { day in
            search.isEmpty || store.journal(day).searchable.localizedCaseInsensitiveContains(search) ||
            store.data.expenses.contains { $0.day == day && ($0.category + " " + $0.note + " " + Expense.money($0.cents)).localizedCaseInsensitiveContains(search) } ||
            store.data.times.contains { $0.day == day && $0.searchable.localizedCaseInsensitiveContains(search) }
        }.sorted(by: >)
    }
    var body: some View {
        NavigationStack {
            List {
                Section("补记 / 查看某一天") {
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    NavigationLink("打开 \(Days.key(date))") { DayView(day: Days.key(date)).navigationTitle("当天日志") }
                }
                Section("\(days.count) 个有记录的日子") {
                    if days.isEmpty { ContentUnavailableView(search.isEmpty ? "还没有日志" : "没有匹配的记录", systemImage: "book", description: Text("从今日开始记录，或选择日期补记。")) }
                    ForEach(days, id: \.self) { day in
                        NavigationLink {
                            DayView(day: day).navigationTitle("当天日志")
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(day).font(.headline); Spacer(); Text(store.journal(day).mood).font(.caption).foregroundStyle(.secondary) }
                                let j = store.journal(day)
                                Text([j.intention, j.topic, j.work, j.win].first { !$0.isEmpty } ?? "支出记录").lineLimit(2).foregroundStyle(.secondary)
                                let cents = store.data.expenses.filter { $0.day == day }.reduce(0) { $0 + $1.cents }
                                Text("时间 \(TimeRecord.duration(store.data.statistics(for: [day]).reduce(0) { $0 + $1.seconds })) · 支出 \(Expense.money(cents))").font(.caption).foregroundStyle(Palette.lime)
                            }.padding(.vertical, 5)
                        }.swipeActions {
                            if store.data.journals.contains(where: { $0.id == day }) { Button("删除日志", role: .destructive) { removing = day } }
                        }
                    }
                }
            }.navigationTitle("日子有迹可循").searchable(text: $search, prompt: "搜索日期、日志、支出或时间事项")
            .alert("删除这一天的文字日志？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("删除", role: .destructive) { if let day = removing { store.deleteJournal(day) }; removing = nil }
                Button("取消", role: .cancel) { removing = nil }
            } message: { Text("支出记录会保留。删除文字日志无法撤销。") }
        }
    }
}

struct ReviewView: View {
    @EnvironmentObject var store: LogStore
    @State private var date = Date()
    @State private var draft: Review?
    var week: [String] { Days.week(date) }
    var journals: [Journal] { store.data.journals.filter { week.contains($0.id) } }
    var expenses: [Expense] { store.data.expenses.filter { week.contains($0.day) } }
    var review: Review { store.data.reviews.first { $0.id == week[0] } ?? Review(id: week[0]) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DatePicker("选择一周", selection: $date, in: ...Date(), displayedComponents: .date)
                    Text("\(week[0]) — \(week[6])").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Card {
                        Text("看见积累，而不只看见忙碌。").font(.title2.bold())
                        HStack {
                            Stat(value: "\(Set(journals.map(\.id) + expenses.map(\.day) + store.data.times.filter { week.contains($0.day) }.map(\.day)).count)", title: "记录天数")
                            Spacer(); Stat(value: "\(store.data.statistics(for: week).filter { $0.category == "学习" }.reduce(0) { $0 + $1.seconds } / 60)", title: "学习分钟")
                            Spacer(); Stat(value: Expense.money(expenses.reduce(0) { $0 + $1.cents }), title: "本周支出")
                        }
                    }
                    Card {
                        Label("本周时间", systemImage: "clock").font(.headline)
                        TimeDistribution(records: store.data.statistics(for: week), byActivity: false)
                        NavigationLink("查看每日趋势与事项统计") { TimeTrackingView(initialDate: date, embedded: true) }
                    }
                    Card {
                        Label("本周积累", systemImage: "leaf").font(.headline)
                        if journals.isEmpty { Text("有了记录，这里就能看见你的收获。").foregroundStyle(.secondary) }
                        ForEach(journals.sorted { $0.id < $1.id }) { j in
                            NavigationLink { DayView(day: j.id).navigationTitle("当天日志") } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(j.id).font(.caption).foregroundStyle(.secondary)
                                    Text([j.win, j.summary, j.result, j.topic, j.intention, j.work, j.thoughts].first { !$0.isEmpty } ?? "已记录状态").lineLimit(3)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                    Card {
                        Label("支出分布", systemImage: "chart.bar").font(.headline)
                        if expenses.isEmpty { Text("本周暂无支出记录。").foregroundStyle(.secondary) }
                        ForEach(Expense.categories, id: \.self) { category in
                            let total = expenses.filter { $0.category == category }.reduce(0) { $0 + $1.cents }
                            if total > 0 {
                                HStack { Text(category); Spacer(); Text(Expense.money(total)).monospacedDigit() }
                                ProgressView(value: Double(total), total: Double(max(1, expenses.reduce(0) { $0 + $1.cents }))).tint(Palette.lime)
                            }
                        }
                    }
                    Card {
                        Label("每周复盘", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                        Detail("最有价值的成果", review.achievement); Detail("发现的规律 / 教训", review.lesson); Detail("下周一个具体行动", review.action)
                        Button("写下本周复盘") { draft = review }
                    }
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }.navigationTitle("成长回顾").sheet(item: $draft) { ReviewEditor(review: $0) }
        }
    }
}

struct Stat: View {
    let value: String; let title: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(value).font(.title3.bold()).foregroundStyle(Palette.lime).minimumScaleFactor(0.6).lineLimit(1); Text(title).font(.caption).foregroundStyle(.secondary) } }
}

struct ReviewEditor: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) var dismiss
    @State var review: Review
    @State private var discard = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("\(review.id) 开始的一周") {
                    TextField("最有价值的成果", text: $review.achievement, axis: .vertical).lineLimit(3...10)
                    TextField("发现的规律 / 教训", text: $review.lesson, axis: .vertical).lineLimit(3...10)
                    TextField("下周一个具体行动", text: $review.action, axis: .vertical).lineLimit(3...10)
                }
            }.navigationTitle("每周复盘").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") {
                    let original = store.data.reviews.first { $0.id == review.id } ?? Review(id: review.id)
                    if original != review { discard = true } else { dismiss() }
                } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") {
                    if store.save(review) { dismiss() } else { failure = store.error; store.error = nil }
                }.disabled(store.locked) }
            }.confirmationDialog("放弃尚未保存的修改？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
        }.interactiveDismissDisabled().saveError($failure)
    }
}

extension View {
    func saveError(_ failure: Binding<String?>) -> some View {
        alert("保存失败", isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } })) {
            Button("知道了", role: .cancel) { failure.wrappedValue = nil }
        } message: { Text(failure.wrappedValue ?? "") }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LogStore
    @State private var exportURL: URL?
    @State private var importer = false
    @State private var incoming: Backup?
    @State private var imported = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("拾日 · 每天留一点成长", systemImage: "leaf.fill").font(.headline).foregroundStyle(Palette.lime)
                    Text("简单记录，定期回看。学习、工作、成长和支出放在同一天里。")
                }
                Section("数据与备份") {
                    Text("已保存 \(store.data.journals.count) 篇日志 · \(store.data.expenses.count) 笔支出 · \(store.data.times.count) 条时间记录")
                    if store.locked { Text("数据读取异常，写入已暂停。请导出原始文件后再恢复。保存文件仍在 App 内。").foregroundStyle(.orange) }
                    Button(store.locked ? "准备导出原始数据" : "准备 JSON 备份") {
                        do { exportURL = try store.export() } catch { store.error = error.localizedDescription }
                    }
                    if let url = exportURL { ShareLink(item: url) { Label("保存 / 分享备份文件", systemImage: "square.and.arrow.up") } }
                    Button("从 JSON 备份恢复") { importer = true }
                    Text("数据保存在本机，没有账号或云同步。卸载 App 会删除本地数据；请将备份存到“文件”或其他安全位置。分享文件含个人日志和支出。").font(.caption).foregroundStyle(.secondary)
                }
                Section("记录方法") {
                    Text("晨间：选一件最重要的事。白天：用短句快速记录。晚间：看一眼收获，再定一个明日行动。")
                    Link("Bullet Journal · 每日日志", destination: URL(string: "https://bulletjournal.com/blogs/faq/how-to-write-a-daily-log")!)
                    Text("学习采用康奈尔笔记的简化结构：问题 / 线索、笔记、总结。总结时尝试不看原资料，用自己的话解释。")
                    Link("康奈尔大学 · Cornell Notes", destination: URL(string: "https://lsc.cornell.edu/how-to-study/taking-notes/cornell-note-taking-system/")!)
                    Text("支出采用分类流水：日期、金额、分类、备注；按周查看类别占比。")
                    Link("CFPB · Spending Tracker", destination: URL(string: "https://www.consumerfinance.gov/consumer-tools/educator-tools/your-money-your-goals/toolkit/")!)
                    Text("工作与成长模板为本 App 的轻量设计，不是上述方法的完整复刻。感想选填，记录无需面面俱到。").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("我的")
            .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 20 * 1024 * 1024 else { throw LogError.large }
                    incoming = try Library.decode(Data(contentsOf: url))
                } catch { if (error as NSError).code != NSUserCancelledError { store.error = error.localizedDescription } }
            }
            .alert("合并备份？", isPresented: Binding(get: { incoming != nil }, set: { if !$0 { incoming = nil } })) {
                Button("合并并恢复") { if let data = incoming { imported = store.restore(data) }; incoming = nil; exportURL = nil }
                Button("取消", role: .cancel) { incoming = nil }
            } message: {
                Text("备份含 \(incoming?.journals.count ?? 0) 篇日志、\(incoming?.expenses.count ?? 0) 笔支出、\(incoming?.times.count ?? 0) 条时间。同日期日志、同 ID 支出/时间和同周复盘以备份为准，其他记录保留。本机计时器保持原状，不从备份启动计时器。导入前会保存原数据副本。")
            }
            .alert("恢复完成", isPresented: $imported) { Button("好", role: .cancel) {} } message: { Text("记录已合并并保存。") }
        }
    }
}

struct TimeTrackingView: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var date: Date
    @State private var followsToday: Bool
    @State private var draft: TimeRecord?
    @State private var starting = false
    @State private var deleting: TimeRecord?
    @State private var discardTimer = false
    let embedded: Bool
    init(initialDate: Date = Date(), embedded: Bool = false) {
        _date = State(initialValue: initialDate)
        _followsToday = State(initialValue: !embedded)
        self.embedded = embedded
    }
    var day: String { Days.key(date) }
    var week: [String] { Days.week(date) }
    var records: [TimeRecord] { store.data.times.filter { $0.day == day } }
    var stats: [TimeRecord] { store.data.statistics(for: [day]) }
    var suggestions: [String] { Array(Set(TimeRecord.categories + store.data.times.map(\.category))).sorted() }
    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }
    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DatePicker("查看日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    .onChange(of: date) { _, _ in followsToday = Days.key(date) == Days.key(Date()) }
                HStack {
                    Text("\(day) · 已记录").foregroundStyle(.secondary)
                    Spacer()
                    Button("今天") { date = Date(); followsToday = true }
                }
                Text(TimeRecord.duration(stats.reduce(0) { $0 + $1.seconds })).font(.largeTitle.bold()).foregroundStyle(Palette.lime)
                Text("把时间记在具体的事情上。").foregroundStyle(.secondary)
                if let timer = store.data.activeTimer {
                    Card {
                        Label(timer.runningSince == nil ? "计时已暂停" : "正在计时", systemImage: "stopwatch").font(.headline)
                        Text("\(timer.category) · \(timer.activity)").font(.title3.bold())
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(TimeRecord.clock(timer.elapsed(at: context.date))).font(.system(size: 36, weight: .bold, design: .monospaced)).foregroundStyle(Palette.lime)
                        }
                        HStack {
                            Button(timer.runningSince == nil ? "继续" : "暂停") { if timer.runningSince == nil { store.resumeTimer() } else { store.pauseTimer() } }.buttonStyle(.bordered)
                            Button("结束并保存") { store.finishTimer() }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                            Spacer()
                            Button(role: .destructive) { discardTimer = true } label: { Image(systemName: "xmark") }.accessibilityLabel("放弃计时")
                        }.disabled(store.locked)
                        Text("后台或关闭 App 后按实际经过时间计算；暂停时间不计入。结束保存后才加入统计。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button { starting = false; draft = TimeRecord(day: day, category: "学习", activity: "", seconds: 0) } label: { Label("手动补记", systemImage: "plus") }.buttonStyle(.bordered)
                    Button { starting = true; draft = TimeRecord(day: Days.key(Date()), category: "学习", activity: "", seconds: 0) } label: { Label("开始计时", systemImage: "play.fill") }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(store.data.activeTimer != nil)
                }.disabled(store.locked)
                Card {
                    Label("当天时间分布", systemImage: "chart.bar").font(.headline)
                    TimeDistribution(records: stats, byActivity: false)
                }
                Card {
                    Label("具体事项", systemImage: "list.bullet").font(.headline)
                    TimeDistribution(records: stats, byActivity: true)
                }
                Card {
                    Label("当天明细", systemImage: "clock").font(.headline)
                    if records.isEmpty { Text("暂无时间明细，试试记录“阅读 30 分钟”。").foregroundStyle(.secondary) }
                    ForEach(records) { record in
                        HStack {
                            Button { starting = false; draft = record } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(record.activity); Text(record.category).font(.caption).foregroundStyle(.secondary); if !record.note.isEmpty { Text(record.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                                    Spacer(); Text(TimeRecord.duration(record.seconds)).monospacedDigit()
                                }
                            }.buttonStyle(.plain)
                            Button(role: .destructive) { deleting = record } label: { Image(systemName: "trash").padding(8) }.accessibilityLabel("删除时间记录")
                        }
                        Divider()
                    }
                    Text("点按明细可编辑。当天有时间明细时，统计完全采用明细；没有明细时才使用日志里的旧学习分钟。").font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    Label("本周每日趋势", systemImage: "chart.bar.xaxis").font(.headline)
                    Text("\(week[0]) — \(week[6])").font(.caption).foregroundStyle(.secondary)
                    let weekly = store.data.statistics(for: week)
                    let maximum = max(1, week.map { day in weekly.filter { $0.day == day }.reduce(0) { $0 + $1.seconds } }.max() ?? 0)
                    ForEach(week, id: \.self) { day in
                        let total = weekly.filter { $0.day == day }.reduce(0) { $0 + $1.seconds }
                        HStack { Text(String(day.suffix(5))); Spacer(); Text(TimeRecord.duration(total)) }.font(.subheadline)
                        ProgressView(value: Double(total), total: Double(maximum))
                    }
                    Text("本周合计 \(TimeRecord.duration(weekly.reduce(0) { $0 + $1.seconds }))").font(.headline).foregroundStyle(Palette.lime)
                }
                Card {
                    Label("本周事项累计", systemImage: "sum").font(.headline)
                    TimeDistribution(records: store.data.statistics(for: week), byActivity: true)
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("时间花在哪里")
        .onChange(of: scenePhase) { _, phase in if phase == .active && followsToday { date = Date() } }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in if followsToday && Days.key(now) != day { date = now } }
        .sheet(item: $draft) { TimeRecordEditor(record: $0, startingTimer: starting, suggestions: suggestions) }
        .alert("删除这条时间记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { if let record = deleting { store.deleteTime(record.id) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("删除后无法撤销。") }
        .confirmationDialog("放弃本次计时？不会加入时间统计。", isPresented: $discardTimer, titleVisibility: .visible) { Button("放弃计时", role: .destructive) { store.discardTimer() } }
    }
}

struct TimeDistribution: View {
    let records: [TimeRecord]
    let byActivity: Bool
    var totals: [(name: String, seconds: Int)] {
        let grouped = Dictionary(grouping: records) { byActivity ? "\($0.category) · \($0.activity)" : $0.category }
        return grouped.map { (name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }
    var body: some View {
        if records.isEmpty { Text("有了时间记录，这里就能看见分布。").foregroundStyle(.secondary) }
        let total = max(1, records.reduce(0) { $0 + $1.seconds })
        ForEach(totals, id: \.name) { row in
            HStack(alignment: .firstTextBaseline) {
                Text(row.name); Spacer()
                Text("\(TimeRecord.duration(row.seconds)) · \(Int((Double(row.seconds) / Double(total) * 100).rounded()))%").font(.caption).foregroundStyle(Palette.lime)
            }
            ProgressView(value: Double(row.seconds), total: Double(total))
        }
    }
}

struct TimeRecordEditor: View {
    @EnvironmentObject var store: LogStore
    @Environment(\.dismiss) var dismiss
    @State var record: TimeRecord
    let startingTimer: Bool
    let suggestions: [String]
    @State private var date = Date()
    @State private var hours = "0"
    @State private var minutes = "30"
    @State private var seconds = "0"
    @State private var initialized = false
    @State private var discard = false
    @State private var failure: String?
    var duration: Int? {
        guard let h = Int(hours), let m = Int(minutes), let s = Int(seconds), (0...24).contains(h), (0...59).contains(m), (0...59).contains(s), h * 3600 + m * 60 + s > 0, h * 3600 + m * 60 + s <= 86400 else { return nil }
        return h * 3600 + m * 60 + s
    }
    var valid: Bool { !record.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && record.category.count <= 40 && !record.activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && record.activity.count <= 200 && (startingTimer || duration != nil) }
    var body: some View {
        NavigationStack {
            Form {
                Section("记录什么事情") {
                    TextField("具体事项，例如：阅读、写方案、练琴", text: $record.activity, axis: .vertical)
                    TextField("分类（可自定义）", text: $record.category)
                    Menu("选择常用分类") { ForEach(suggestions, id: \.self) { category in Button(category) { record.category = category } } }
                    TextField("备注（选填）", text: $record.note, axis: .vertical)
                }
                if !startingTimer {
                    Section("日期与时长") {
                        DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        HStack { Text("小时"); TextField("0", text: $hours).keyboardType(.numberPad); Text("分钟"); TextField("30", text: $minutes).keyboardType(.numberPad); Text("秒"); TextField("0", text: $seconds).keyboardType(.numberPad) }
                        if let duration { Text("合计 \(TimeRecord.clock(duration))").foregroundStyle(Palette.lime) }
                        Text("最多 24 小时；分钟、秒为 0–59。请避免重复记录同一段时间。").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section { Text("一次只计时一件事。开始后可暂停、继续、结束保存；后台和重启后会保留计时状态。").foregroundStyle(.secondary) }
                }
            }.navigationTitle(startingTimer ? "开始一件事" : "记录时间").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !initialized {
                    date = Days.date(record.day) ?? Date()
                    if record.seconds > 0 { hours = String(record.seconds / 3600); minutes = String(record.seconds % 3600 / 60); seconds = String(record.seconds % 60) }
                    initialized = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { discard = true } }
                ToolbarItem(placement: .confirmationAction) { Button(startingTimer ? "开始" : "保存") {
                    var next = record; next.day = Days.key(date); next.seconds = duration ?? 0
                    let saved = startingTimer ? store.startTimer(next) : store.save(next)
                    if saved { dismiss() } else { failure = store.error; store.error = nil }
                }.disabled(!valid || store.locked || (startingTimer && store.data.activeTimer != nil)) }
            }.confirmationDialog("放弃尚未保存的内容？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() } }
        }.interactiveDismissDisabled().saveError($failure)
    }
}
