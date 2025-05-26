import SwiftUI
import AppKit
import Quartz
import QuickLook

struct ContentView: View {
    @StateObject var clipboardManager = ClipboardManager()
    @State private var showingDeleteAlert = false
    @State private var selectedEntry: ClipboardEntry?

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.horizontal)
                }

                List(selection: $selectedEntry) {
                    ForEach(clipboardManager.clipboardEntries) { entry in
                        HStack(spacing: 8) {
                            // 图标部分
                            switch entry.type {
                            case .image:
                                Image(systemName: "photo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .padding(10)
                            case .file:
                                Image(systemName: "doc")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .padding(10)
                            case .text:
                                Image(systemName: "doc.text")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .padding(10)
                            }

                            // 显示文件名或内容
                            Text(entry.displayName)
                                .lineLimit(2)
                                .truncationMode(.tail)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .tag(entry)
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 300)
            .alert(isPresented: $showingDeleteAlert) {
                Alert(
                    title: Text("确认清空"),
                    message: Text("是否确定要清空所有剪贴板数据？此操作不可撤销。"),
                    primaryButton: .destructive(Text("清空")) {
                        clipboardManager.clearAllData()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        } detail: {
            if let entry = selectedEntry {
                DetailView(entry: entry)
            } else {
                Text("选择内容查看详情")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            clipboardManager.loadEntriesFromDatabase()
        }
    }
}

struct DetailView: View {
    let entry: ClipboardEntry

    var body: some View {
        VStack {
            switch entry.type {
            case .image:
                if let nsImage = entry.image {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else {
                    Text("无法加载图片")
                        .foregroundColor(.red)
                }
            case .file:
                FilePreviewView(filePath: entry.content)
            case .text:
                ScrollView {
                    TextEditor(text: .constant(entry.content))
                        .font(.system(.body))
                        .padding()
                }
            }
        }
        .navigationTitle(entry.displayName)
        .toolbar {
            Button(action: {
                copyToClipboard()
            }) {
                Image(systemName: "doc.on.doc")
                Text("复制")
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.type {
        case .text:
            pasteboard.setString(entry.content, forType: .string)
        case .image:
            if let image = entry.image {
                pasteboard.writeObjects([image])
            }
        case .file:
            let url = URL(fileURLWithPath: entry.content)
            pasteboard.writeObjects([url as NSURL])
        }
    }
}

struct FilePreviewView: NSViewRepresentable {
    let filePath: String

    class Coordinator: NSObject, QLPreviewingController {
        var parent: FilePreviewView

        init(_ parent: FilePreviewView) {
            self.parent = parent
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let preview = QLPreviewView(frame: NSRect.zero, style: .normal)!
        preview.autostarts = true
        preview.previewItem = URL(fileURLWithPath: filePath) as QLPreviewItem
        return preview
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let preview = nsView as? QLPreviewView {
            preview.previewItem = URL(fileURLWithPath: filePath) as QLPreviewItem
        }
    }
}

#Preview {
    ContentView()
}
