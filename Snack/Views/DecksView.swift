import SnackKit
import SwiftUI

/// The decks the Inbox has brought, and how the Inbox stands.
struct DecksView: View {
    let inbox: Inbox
    let study: Study

    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                if inbox.library.decks.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "还没有牌组",
                            systemImage: "tray",
                            description: Text("把 .deck.json 文件放进 iCloud 云盘的 Snack › Inbox 文件夹，或者点右上角的 + 导入，这里就会出现。")
                        )
                    }
                } else {
                    Section("牌组") {
                        ForEach(inbox.library.sortedDecks, id: \.info.id) { deck in
                            NavigationLink {
                                DeckView(deck: deck, library: inbox.library, study: study)
                            } label: {
                                DeckRow(deck: deck, study: study)
                            }
                        }
                    }
                }
                Section {
                    status
                    ForEach(inbox.files) { file in
                        FileRow(file: file)
                    }
                } header: {
                    Text("收件箱")
                } footer: {
                    Text(verbatim: "在 Mac 上是 ~/Library/Mobile Documents/iCloud~com~kadaliao~snack/Documents/Inbox")
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("牌组")
            .refreshable { inbox.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入牌组", systemImage: "plus") { isImporting = true }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    for url in urls { await inbox.importDeck(from: url) }
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch inbox.state {
        case .starting:
            Label("正在连接 iCloud…", systemImage: "icloud")
        case .noICloud:
            Label("没有 iCloud：在「设置」里登录 Apple 账户并打开 iCloud 云盘", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
        case .watching:
            let waiting = inbox.files.filter { !$0.isDownloaded }.count
            if inbox.files.isEmpty {
                Label("收件箱是空的", systemImage: "icloud")
            } else if waiting > 0 {
                Label("\(inbox.files.count) 个文件，\(waiting) 个正在下载", systemImage: "icloud.and.arrow.down")
            } else {
                Label("\(inbox.files.count) 个文件，都是最新的", systemImage: "checkmark.icloud")
            }
        }
    }
}

private struct DeckRow: View {
    let deck: Library.StoredDeck
    let study: Study

    var body: some View {
        let cards = deck.visible
        let studied = cards.count { study.mastery(CardKey(deck: deck.info.id, card: $0.id)) != .new }
        HStack(spacing: 14) {
            Ring(value: cards.isEmpty ? 0 : Double(studied) / Double(cards.count), width: 5)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.info.title).font(.headline)
                Text("学过 \(studied)/\(cards.count) · \(breakdown(cards))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func breakdown(_ cards: [Card]) -> String {
        Card.Kind.allCases
            .compactMap { kind in
                let n = cards.filter { $0.kind == kind }.count
                return n > 0 ? "\(kind.label) \(n)" : nil
            }
            .joined(separator: " · ")
    }
}

private struct FileRow: View {
    let file: Inbox.FileStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name).font(.footnote.monospaced())
            Group {
                if let problem = file.problem {
                    Text(problem).foregroundStyle(.orange)
                } else if !file.isDownloaded {
                    Text("正在下载")
                } else if let cards = file.cards {
                    Text("\(cards) 张")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

extension Card.Kind {
    var label: String {
        switch self {
        case .phrase: "短语"
        case .pattern: "句型"
        case .fix: "纠错"
        case .qa: "问答"
        }
    }
}
