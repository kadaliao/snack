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

    private let libraryURL: URL
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
        await Task.detached { Inbox.prepare(documents.appending(path: "Inbox")) }.value
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
            var merged = library
            merged.merge(sources, now: .now)
            if merged != library {
                library = merged
                let url = libraryURL
                await Task.detached { try? merged.save(to: url) }.value
            }
            lastMerged = .now
            isReading = false
            if isReadAgain {
                isReadAgain = false
                refresh()
            }
        }
    }

    struct ReadProblem: Error {
        var message: String
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
