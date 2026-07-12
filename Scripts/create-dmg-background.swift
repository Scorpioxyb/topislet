#!/usr/bin/env swift

import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2 else {
    fputs("usage: create-dmg-background.swift OUTPUT\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pointWidth = 660
let pointHeight = 400
let scale = 2
let pixelWidth = pointWidth * scale
let pixelHeight = pointHeight * scale

guard let context = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: pixelWidth * 4,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("error: failed to create DMG background context\n", stderr)
    exit(1)
}

context.setFillColor(CGColor(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
context.setStrokeColor(CGColor(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 147.0 / 255.0, alpha: 0.72))
context.setLineWidth(5 * CGFloat(scale))
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: CGFloat(302 * scale), y: CGFloat(210 * scale)))
context.addLine(to: CGPoint(x: CGFloat(358 * scale), y: CGFloat(210 * scale)))
context.move(to: CGPoint(x: CGFloat(344 * scale), y: CGFloat(224 * scale)))
context.addLine(to: CGPoint(x: CGFloat(358 * scale), y: CGFloat(210 * scale)))
context.addLine(to: CGPoint(x: CGFloat(344 * scale), y: CGFloat(196 * scale)))
context.strokePath()

guard let cgImage = context.makeImage() else {
    fputs("error: failed to create DMG background image\n", stderr)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
bitmap.size = NSSize(width: pointWidth, height: pointHeight)
guard
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("error: failed to render DMG background\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
