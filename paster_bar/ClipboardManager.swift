import Foundation
import AppKit
import SQLite3
import SwiftUI

struct ClipboardEntry: Identifiable, Hashable {
    let id: Int
    let content: String  // 对于文件，这里存储文件路径
    let type: ClipboardType
    let image: NSImage?

    enum ClipboardType: String, Hashable {
        case text
        case image
        case file
    }

    var displayName: String {
        switch type {
        case .text:
            return content
        case .image, .file:
            return (content as NSString).lastPathComponent
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(content)
        hasher.combine(type)
    }

    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.type == rhs.type
    }
}

class ClipboardManager: ObservableObject {
    private var lastChangeCount: Int
    private var clipboardTimer: Timer?
    private var refreshTimer: Timer?
    private var db: OpaquePointer?
    @Published var clipboardEntries: [ClipboardEntry] = []

    private var imageSaveDirectory: URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return homeDirectory.appendingPathComponent("paster_bar/copy_image")
    }

    private func setupImageDirectory() {
        do {
            try FileManager.default.createDirectory(at: imageSaveDirectory,
                                                  withIntermediateDirectories: true,
                                                  attributes: nil)
        } catch {
            print("创建图片目录失败: \(error)")
        }
    }

    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        setupImageDirectory()
        setupDatabase()
        startClipboardMonitoring()
        startUIRefreshTimer()
        loadEntriesFromDatabase()
    }

    deinit {
        stopClipboardMonitoring()
        stopUIRefreshTimer()
        sqlite3_close(db)
    }

    private func setupDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("clipboard_data.db").path

        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true, attributes: nil)

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("无法打开数据库")
            return
        }

        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS clipboard (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """

        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            print("无法创建表格")
            let errorMsg = String(cString: sqlite3_errmsg(db)!)
            print("SQLite error: \(errorMsg)")
        }
    }

    private func startClipboardMonitoring() {
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let pasteboard = NSPasteboard.general
            let currentCount = pasteboard.changeCount

            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount
                self.checkClipboard()
            }
        }
    }

    private func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general


        // 检查是否有文件
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            var isFile = false
            for url in urls {
                if url.isFileURL {
                    isFile = true
                    let path = url.path
                    if !isDuplicateContent(path) {
                        if isImageFile(url) {
                            saveToDatabase(content: path, type: .image)
                        } else {
                            saveToDatabase(content: path, type: .file)
                        }
                    }
                }
            }
            if (isFile) {
                return
            }
        }

        // 检查是否有图片
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let path = saveImageToFile(image) {
                    if !isDuplicateContent(path) {
                        saveToDatabase(content: path, type: .image)
                    }
                }
            }
            if !images.isEmpty {
                return
            }
        }

        // 检查是否有文本内容
        if let text = pasteboard.string(forType: .string) {
            if !text.isEmpty && !isDuplicateContent(text) {
                print("检测到新的文本内容：\(text.prefix(20))...")
                saveToDatabase(content: text, type: .text)
            }
        }
    }

    private func saveImageToFile(_ image: NSImage) -> String? {
        // 创建位图表示
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("无法创建 CGImage")
            return nil
        }

        let imageRep = NSBitmapImageRep(cgImage: cgImage)
        guard let imageData = imageRep.representation(using: .png, properties: [:]) else {
            print("无法创建 PNG 数据")
            return nil
        }

        let fileName = UUID().uuidString + ".png"
        let fileURL = imageSaveDirectory.appendingPathComponent(fileName)

        do {
            try imageData.write(to: fileURL)
            return fileURL.path
        } catch {
            print("保存图片失败: \(error)")
            return nil
        }
    }

    private func isImageFile(_ url: URL) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private func isDuplicateContent(_ content: String) -> Bool {
        var statement: OpaquePointer?
        let query = "SELECT id FROM clipboard WHERE content = ? ORDER BY id DESC LIMIT 1"
        var isDuplicate = false

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (content as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                isDuplicate = true
            }
        }
        sqlite3_finalize(statement)
        return isDuplicate
    }

    private func startUIRefreshTimer() {
        stopUIRefreshTimer()

        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.loadEntriesFromDatabase()
                }
            }

            if let timer = self?.refreshTimer {
                RunLoop.current.add(timer, forMode: .common)
            }
        }
    }

    private func stopUIRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func loadEntriesFromDatabase() {
        var statement: OpaquePointer?
        let query = "SELECT id, content, type FROM clipboard ORDER BY id DESC"

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var newEntries: [ClipboardEntry] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int(statement, 0)
                if let contentCString = sqlite3_column_text(statement, 1),
                   let typeCString = sqlite3_column_text(statement, 2) {
                    let content = String(cString: contentCString)
                    let typeString = String(cString: typeCString)
                    let type = ClipboardEntry.ClipboardType(rawValue: typeString) ?? .text

                    let image: NSImage? = type == .image ? NSImage(contentsOfFile: content) : nil

                    newEntries.append(ClipboardEntry(
                        id: Int(id),
                        content: content,
                        type: type,
                        image: image
                    ))
                }
            }

            // 在主线程更新 UI
            DispatchQueue.main.async {
                self.clipboardEntries = newEntries
            }
        }
        sqlite3_finalize(statement)
    }

    private func saveToDatabase(content: String, type: ClipboardEntry.ClipboardType) {
        var statement: OpaquePointer?
        let query = "INSERT INTO clipboard (content, type) VALUES (?, ?)"

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (type.rawValue as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_DONE {
                // 保存成功后立即刷新数据
                DispatchQueue.main.async {
                    self.loadEntriesFromDatabase()
                }
            }
        }
        sqlite3_finalize(statement)
    }

    func clearAllData() {
        let deleteQuery = "DELETE FROM clipboard"
        if sqlite3_exec(db, deleteQuery, nil, nil, nil) != SQLITE_OK {
            print("无法清空数据库")
            let errorMsg = String(cString: sqlite3_errmsg(db)!)
            print("SQLite error: \(errorMsg)")
            return
        }

        DispatchQueue.main.async {
            self.clipboardEntries.removeAll()
        }
    }
}
