#!/usr/bin/env swift
// 把体积较大的国旗 SVG 预先栅格化为同名 PNG（Flagpack、Noto 波浪旗、flag-icons 方形旗）。
// 规格与 CountryFlagImageCache.rasterized 完全一致，运行时直接加载位图，
// 外观不变，同时省去 SVG 解析并显著减小 App 体积。
//
// 用法：swift scripts/rasterize-flags.swift Prism/Resources/WavedFlags/*.svg
// 生成 PNG 后删除对应 SVG；含 <use> 引用的 SVG 需先运行 expand-flag-uses.py。

import AppKit

// 与 CountryFlagImageCache.rasterized 完全相同的栅格化逻辑。
func rasterize(_ vector: NSImage, maximumPixelDimension: CGFloat = 176) -> NSBitmapImageRep? {
    let size = vector.size
    guard size.width > 0, size.height > 0 else { return nil }
    let longestSide = max(size.width, size.height)
    let targetLongestSide = min(maximumPixelDimension, longestSide * 4)
    let scale = targetLongestSide / longestSide
    let pixelsWide = max(1, Int((size.width * scale).rounded(.up)))
    let pixelsHigh = max(1, Int((size.height * scale).rounded(.up)))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    vector.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh), from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    rep.size = size
    return rep
}

let args = CommandLine.arguments.dropFirst()
var sizes: [String: Int] = [:]
for path in args {
    let url = URL(fileURLWithPath: path)
    guard let vector = NSImage(contentsOf: url), let rep = rasterize(vector),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("FAILED \(path)"); exit(1)
    }
    let out = url.deletingPathExtension().appendingPathExtension("png")
    try! png.write(to: out)
    sizes["\(vector.size.width)x\(vector.size.height) -> \(rep.pixelsWide)x\(rep.pixelsHigh)", default: 0] += 1
}
print(sizes)
