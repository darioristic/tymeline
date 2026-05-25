#!/usr/bin/env swift
// Generate a placeholder macOS app icon for tymeline.
//
// Renders a 1024x1024 base PNG (clock SF Symbol on a blue squircle), then
// runs `sips` to produce the 10 standard sizes Xcode's AppIcon.appiconset
// expects, and writes a matching Contents.json that references them.
//
// Usage: ./scripts/generate-app-icon.swift
//        (run from the repo root - writes into Resources/Assets.xcassets/AppIcon.appiconset)

import AppKit
import Foundation

let iconsetDir = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// 1. Render 1024x1024 base
let baseSize = 1024
let img = NSImage(size: NSSize(width: baseSize, height: baseSize))
img.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: baseSize, height: baseSize)
// macOS Big Sur+ icon corner radius is ~18% of side
let cornerRadius = CGFloat(baseSize) * 0.18
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSColor.systemBlue.setFill()
bgPath.fill()

// Clock symbol, white, centered ~60% of canvas
let symbol = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)!
let symbolConfig = NSImage.SymbolConfiguration(pointSize: 640, weight: .regular)
    .applying(.init(paletteColors: [.white]))
let tinted = symbol.withSymbolConfiguration(symbolConfig)!
let inset = CGFloat(baseSize) * 0.20
let symbolRect = NSRect(
    x: inset,
    y: inset,
    width: CGFloat(baseSize) - inset * 2,
    height: CGFloat(baseSize) - inset * 2
)
tinted.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)

img.unlockFocus()

// Write 1024 base
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode base PNG\n", stderr)
    exit(1)
}
let basePath = iconsetDir.appendingPathComponent("icon_1024.png")
try png.write(to: basePath)
print("Wrote", basePath.path)

// 2. Downsample to all required sizes via `sips`
struct Variant {
    let size: Int        // pixel size
    let filename: String
    let logicalSize: String  // "16x16", etc.
    let scale: String        // "1x" or "2x"
}

let variants: [Variant] = [
    .init(size: 16,   filename: "icon_16.png",      logicalSize: "16x16",     scale: "1x"),
    .init(size: 32,   filename: "icon_16@2x.png",   logicalSize: "16x16",     scale: "2x"),
    .init(size: 32,   filename: "icon_32.png",      logicalSize: "32x32",     scale: "1x"),
    .init(size: 64,   filename: "icon_32@2x.png",   logicalSize: "32x32",     scale: "2x"),
    .init(size: 128,  filename: "icon_128.png",     logicalSize: "128x128",   scale: "1x"),
    .init(size: 256,  filename: "icon_128@2x.png",  logicalSize: "128x128",   scale: "2x"),
    .init(size: 256,  filename: "icon_256.png",     logicalSize: "256x256",   scale: "1x"),
    .init(size: 512,  filename: "icon_256@2x.png",  logicalSize: "256x256",   scale: "2x"),
    .init(size: 512,  filename: "icon_512.png",     logicalSize: "512x512",   scale: "1x"),
    .init(size: 1024, filename: "icon_512@2x.png",  logicalSize: "512x512",   scale: "2x"),
]

for variant in variants {
    let outPath = iconsetDir.appendingPathComponent(variant.filename)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = [
        "-z", "\(variant.size)", "\(variant.size)",
        basePath.path,
        "--out", outPath.path,
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        fputs("sips failed for \(variant.filename): \(output)\n", stderr)
        exit(1)
    }
    print("Wrote", outPath.lastPathComponent, "(\(variant.size)x\(variant.size))")
}

// Remove the working 1024 base now that we've sliced it
try? fileManager.removeItem(at: basePath)

// 3. Write Contents.json
struct ImageEntry: Codable {
    let idiom: String
    let scale: String
    let size: String
    let filename: String
}
struct Info: Codable {
    let author: String
    let version: Int
}
struct Manifest: Codable {
    let images: [ImageEntry]
    let info: Info
}

let manifest = Manifest(
    images: variants.map {
        ImageEntry(idiom: "mac", scale: $0.scale, size: $0.logicalSize, filename: $0.filename)
    },
    info: Info(author: "xcode", version: 1)
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let manifestData = try encoder.encode(manifest)
let manifestPath = iconsetDir.appendingPathComponent("Contents.json")
try manifestData.write(to: manifestPath)
print("Wrote", manifestPath.path)

print("Done. Re-run 'xcodegen generate' (no-op for assets) and rebuild the app.")
