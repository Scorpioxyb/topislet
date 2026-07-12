import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: move-to-trash.swift PATH\n", stderr)
    exit(64)
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.trashItem(at: url, resultingItemURL: nil)
