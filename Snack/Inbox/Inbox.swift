import Foundation
import Observation
import SnackKit

/// The iCloud folder producers put decks in, watched: each `*.deck.json` there is
/// downloaded, read and merged into the library the app keeps on its own.
///
/// The app only reads the Inbox. Files the producers write belong to them; the one
/// file the app writes there is the README that brings the folder into being, so it
/// shows up on the Mac for them to write into.
@MainActor
@Observable
final class Inbox {
    nonisolated static let containerID = "iCloud.com.kadaliao.snack"

    enum State: Equatable {
        case starting
        /// iCloud is off, or the app has no container in it.
        case noICloud
        case watching
    }

    /// A file of the Inbox, as last seen.
    struct FileStatus: Identifiable, Equatable {
        var name: String
        var isDownloaded: Bool
        /// Why it could not be read, if it could not.
        var problem: String?
        var cards: Int?
        var id: String { name }
    }

    private(set) var state: State = .starting
    private(set) var library: Library
    private(set) var files: [FileStatus] = []
    private(set) var lastMerged: Date?
    /// Told of fix cards a producer saw again: the same mistake made again.
    @ObservationIgnored var onRepeated: (([CardKey]) -> Void)?

    /// What the last import did, to tell the learner.
    var notice: String?

    /// A deck that comes with the app, added with a tap. It joins the library
    /// straight away, iCloud or not, as a producer file of its own.
    struct Starter: Identifiable {
        var name: String
        var file: DeckFile
        var id: String { name }
    }

    /// The decks that come with the app.
    let starters: [Starter] = Inbox.loadStarters()
    /// The ones added, by file name.
    private(set) var addedStarters: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "addedStarters") ?? [])
    /// What the Inbox's files held when last read, to merge again with a starter added.
    private var lastSources: [Library.Source] = []

    private let libraryURL: URL
    private var inboxURL: URL?
    private var query: NSMetadataQuery?
    private var isReading = false
    private var isReadAgain = false

    init(libraryURL: URL = Inbox.defaultLibraryURL) {
        self.libraryURL = libraryURL
        library = (try? Library.load(from: libraryURL)) ?? Library()
    }

    static var defaultLibraryURL: URL {
        URL.applicationSupportDirectory.appending(path: "content.json")
    }

    /// Finds the container, makes sure its Inbox exists, and starts watching it.
    func start() async {
        guard state == .starting else { return }
        // Asking for the container can take a while the first time: never on the main thread.
        let documents = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: Inbox.containerID)?.appending(path: "Documents")
        }.value
        guard let documents else {
            state = .noICloud
            return
        }
        let inbox = documents.appending(path: "Inbox")
        await Task.detached { Inbox.prepare(inbox) }.value
        inboxURL = inbox
        watch()
        state = .watching
    }

    /// Looks again: asks for files not yet downloaded, and reads what changed.
    /// Called as the app comes to the front, since iCloud may have held back.
    func refresh() {
        guard let query else { return }
        query.disableUpdates()
        handle(query)
        query.enableUpdates()
    }

    private func watch() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.deck.json")
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let query = self.query else { return }
                    query.disableUpdates()
                    self.handle(query)
                    query.enableUpdates()
                }
            }
        }
        self.query = query
        query.start()
    }

    private func handle(_ query: NSMetadataQuery) {
        var current: [URL] = []
        var seen: [FileStatus] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
            if isDownloaded {
                current.append(url)
            } else {
                // Since iOS 18.4 a file left alone may stay at an old version: ask for it.
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            let old = files.first { $0.name == name }
            seen.append(FileStatus(name: name, isDownloaded: isDownloaded, problem: old?.problem, cards: old?.cards))
        }
        files = seen.sorted { $0.name < $1.name }
        read(current)
    }

    /// Reads the downloaded files off the main thread and merges them. A read asked
    /// for while one runs is done once that one ends, with the files as they are then.
    private func read(_ urls: [URL]) {
        guard !isReading else {
            isReadAgain = true
            return
        }
        isReading = true
        Task {
            let results = await Task.detached { urls.map { ($0.lastPathComponent, Inbox.readFile($0)) } }.value
            var sources: [Library.Source] = []
            for (name, result) in results {
                guard let index = files.firstIndex(where: { $0.name == name }) else { continue }
                switch result {
                case .success(let file):
                    sources.append(Library.Source(name: name, file: file))
                    files[index].problem = file.skipped > 0 ? "有 \(file.skipped) 张卡读不出来" : nil
                    files[index].cards = file.cards.count
                case .failure(let problem):
                    // The library keeps what the last good version of the file brought.
                    files[index].problem = problem.message
                }
            }
            lastSources = sources
            await merge()
            lastMerged = .now
            isReading = false
            if isReadAgain {
                isReadAgain = false
                refresh()
            }
        }
    }

    /// Merges the Inbox's files as last read and the starters added into the
    /// library, and keeps it.
    private func merge() async {
        let starting = starters.filter { addedStarters.contains($0.name) }.map { Library.Source(name: $0.name, file: $0.file) }
        var merged = library
        let change = merged.merge(lastSources + starting, now: .now)
        if !change.repeated.isEmpty { onRepeated?(change.repeated) }
        guard merged != library else { return }
        library = merged
        let url = libraryURL
        await Task.detached { try? merged.save(to: url) }.value
    }

    func isAdded(_ starter: Starter) -> Bool {
        addedStarters.contains(starter.name) || library.decks[starter.file.deck.id] != nil
    }

    func add(_ starter: Starter) {
        addedStarters.insert(starter.name)
        UserDefaults.standard.set(addedStarters.sorted(), forKey: "addedStarters")
        Task { await merge() }
    }

    nonisolated private static func loadStarters() -> [Starter] {
        (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("starter.") && $0.lastPathComponent.hasSuffix(".deck.json") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let file = try? DeckFile.read(data) else { return nil }
                return Starter(name: url.lastPathComponent, file: file)
            }
            .sorted { $0.name < $1.name }
    }

    struct ReadProblem: Error {
        var message: String
    }

    /// Copies a deck file from elsewhere (Files, the share sheet, AirDrop) into the
    /// Inbox, as a producer of its own: `imported.<its name>`. Importing it again
    /// replaces that copy. Sets `notice` to how it went.
    func importDeck(from url: URL) async {
        guard let inbox = inboxURL else {
            notice = "导入不了：没有 iCloud。在「设置」里登录 Apple 账户并打开 iCloud 云盘。"
            return
        }
        let result = await Task.detached { Inbox.copyIn(url, to: inbox) }.value
        switch result {
        case .success(let file):
            notice = "导入了「\(file.deck.title)」，\(file.cards.count) 张卡。"
            refresh()
        case .failure(let problem):
            notice = "\(url.lastPathComponent) 导入不了：\(problem.message)"
        }
    }

    nonisolated private static func copyIn(_ url: URL, to inbox: URL) -> Result<DeckFile, ReadProblem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file: DeckFile
        switch readFile(url) {
        case .success(let read): file = read
        case .failure(let problem): return .failure(problem)
        }
        var name = url.lastPathComponent
        if !name.hasSuffix(".deck.json") {
            name = file.deck.id.replacingOccurrences(of: "/", with: "-") + ".deck.json"
        }
        if !name.hasPrefix("imported.") { name = "imported." + name }
        guard let data = try? Data(contentsOf: url) else { return .failure(ReadProblem(message: "读不了这个文件")) }
        let target = inbox.appending(path: name)
        var written = false
        var coordination: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordination) { target in
            written = (try? data.write(to: target, options: .atomic)) != nil
        }
        // What the system handed over in the app's own folder is a copy: done with it.
        if url.path.contains("/Documents/Inbox/"), !url.path.contains("Mobile Documents") {
            try? FileManager.default.removeItem(at: url)
        }
        return written ? .success(file) : .failure(ReadProblem(message: "写不进 iCloud 的收件箱"))
    }

    nonisolated private static func readFile(_ url: URL) -> Result<DeckFile, ReadProblem> {
        var data: Data?
        var coordination: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { url in
            data = try? Data(contentsOf: url)
        }
        guard let data else { return .failure(ReadProblem(message: "读不了这个文件")) }
        do {
            return .success(try DeckFile.read(data))
        } catch {
            switch error {
            case .notJSON: return .failure(ReadProblem(message: "不是 JSON，或者还没写完"))
            case .wrongFormat(let format): return .failure(ReadProblem(message: "格式是 \(format ?? "空的")，不是 deck/1"))
            case .noDeck: return .failure(ReadProblem(message: "缺少 deck 的 id 或 title"))
            }
        }
    }

    /// Makes the Inbox and its README, which brings the container into iCloud Drive
    /// so it shows on the Mac for producers to write into.
    nonisolated private static func prepare(_ inbox: URL) {
        let readme = inbox.appending(path: "README.md")
        guard !FileManager.default.fileExists(atPath: readme.path) else { return }
        var coordination: NSError?
        NSFileCoordinator().coordinate(writingItemAt: readme, options: [], error: &coordination) { url in
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try? Data(Self.readme.utf8).write(to: url, options: .atomic)
        }
    }

    nonisolated private static let readme = """
        # Snack 收件箱

        把牌组文件（`*.deck.json`）放在这个文件夹里，卡片零食会自动读进来。
        格式见 https://github.com/kadaliao/snack/blob/main/spec/deck-format.md

        这个文件夹里的文件归写它们的程序所有，卡片零食只读不改。
        删掉一个文件不会删掉已经读进来的卡片和复习进度。
        """
}
