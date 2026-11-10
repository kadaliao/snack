import SnackKit
import SwiftUI

struct SettingsView: View {
    let study: Study

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.goal) private var goal = 300
    @AppStorage(Prefs.newPerDay) private var newPerDay = 10
    @AppStorage(Prefs.speak) private var speaks = true
    @AppStorage(Prefs.sounds) private var sounds = true
    @AppStorage(Prefs.remind) private var reminds = true
    @AppStorage(Prefs.remindAt) private var remindAt = 20 * 60

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("每天的目标", selection: $goal) {
                        ForEach(Prefs.goals, id: \.0) { xp, name in Text("\(name) · \(xp) XP").tag(xp) }
                    }
                    Picker("每天新卡", selection: $newPerDay) {
                        ForEach([5, 10, 15, 20, 30, 50], id: \.self) { Text("\($0) 张").tag($0) }
                    }
                } header: {
                    Text("目标")
                } footer: {
                    Text("一节 10 题左右，大约 100 XP：答对一题 10，连对 5 题起每题再加 5，刷完一节加 10，全对再加 20。到期的卡先复习，新卡每天最多这么多张。")
                }

                Section {
                    LabeledContent("冻结卡", value: "\(study.streak().freezes)/\(Streak.mostFreezes) 张")
                } footer: {
                    Text("每刷 \(Streak.lessonsPerFreeze) 节送一张，最多存 \(Streak.mostFreezes) 张。哪天一节都没刷，会自动用掉一张，连胜不断。")
                }

                Section("提醒") {
                    Toggle("每天提醒", isOn: $reminds)
                    if reminds {
                        DatePicker("时间", selection: time, displayedComponents: .hourAndMinute)
                    }
                }

                Section("声音") {
                    Toggle("答完朗读答案", isOn: $speaks)
                    Toggle("音效", isOn: $sounds)
                }

                Section {
                    LabeledContent("版本", value: version)
                    Link("牌组格式", destination: URL(string: "https://github.com/kadaliao/snack/blob/main/spec/deck-format.md")!)
                    Link("源代码", destination: URL(string: "https://github.com/kadaliao/snack")!)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onChange(of: reminds) { _, on in
            Task {
                if on { await Reminders.requestPermission() }
                await study.syncReminders()
            }
        }
        .onChange(of: remindAt) { Task { await study.syncReminders() } }
        .onChange(of: goal) { Task { await study.syncReminders() } }
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: remindAt / 60, minute: remindAt % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            remindAt = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
