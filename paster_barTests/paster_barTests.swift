//
//  paster_barTests.swift
//  paster_barTests
//
//  Created by ph on 2024/12/26.
//

import Testing
@testable import paster_bar

import Cocoa



struct paster_barTests {


    @Test func example() async throws {
        // 获取通用剪贴板
        let pasteboard = NSPasteboard.general

        if pasteboard.pasteboardItems?.count ?? 0 > 0 {
            // 获取剪贴板中的第一个项目
            if let pasteboardItem = pasteboard.pasteboardItems?.first {
                // 检查剪贴板项目中是否有字符串数据
                if let stringData = pasteboardItem.string(forType: NSPasteboard.PasteboardType.string) {
                    print("剪贴板内容: \(stringData)")
                } else if let urlString = pasteboardItem.string(forType: NSPasteboard.PasteboardType.fileURL),
                          let url = URL(string: urlString) {
                    print("剪贴板内容: \(url)")
                } else {
                    print("剪贴板中没有文本或URL数据")
                }
            }
        } else {
            print("剪贴板为空")
        }
    }

}
