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

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("Could not get CGContext\n", stderr)
    exit(1)
}

let canvas = NSRect(x: 0, y: 0, width: baseSize, height: baseSize)
// macOS Big Sur+ icon corner radius is ~18% of side
let cornerRadius = CGFloat(baseSize) * 0.18

// Squircle clip + subtle vertical gradient background (deep black → off-black)
let bgPath = NSBezierPath(roundedRect: canvas, xRadius: cornerRadius, yRadius: cornerRadius)
ctx.saveGState()
bgPath.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1.0),  // top, soft graphite
    NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1.0),  // bottom, near-black
])!
gradient.draw(in: canvas, angle: -90)

// Inner clock dial - white face, slightly inset from the squircle
let center = NSPoint(x: CGFloat(baseSize) / 2, y: CGFloat(baseSize) / 2)
let dialRadius = CGFloat(baseSize) * 0.30  // 30% of canvas radius
let dialRect = NSRect(
    x: center.x - dialRadius,
    y: center.y - dialRadius,
    width: dialRadius * 2,
    height: dialRadius * 2
)

// Faint outer ring to add depth around the dial
let ringInset: CGFloat = 14
let outerRingRect = dialRect.insetBy(dx: -ringInset, dy: -ringInset)
let ringPath = NSBezierPath(ovalIn: outerRingRect)
NSColor(calibratedWhite: 1.0, alpha: 0.06).setStroke()
ringPath.lineWidth = 4
ringPath.stroke()

// White dial
let dialPath = NSBezierPath(ovalIn: dialRect)
NSColor.white.setFill()
dialPath.fill()

// Thin gray border on the dial for definition
NSColor(calibratedWhite: 0.85, alpha: 1.0).setStroke()
dialPath.lineWidth = 2
dialPath.stroke()

// 12 hour markers - small black ticks around the dial
// Major (12, 3, 6, 9) are longer/thicker, minor are smaller
let markerOuter = dialRadius * 0.92
let markerInnerMajor = dialRadius * 0.78
let markerInnerMinor = dialRadius * 0.85

for hour in 0..<12 {
    // 12 o'clock points up (angle = 90° in standard cartesian), advance clockwise
    let angle = CGFloat.pi / 2 - CGFloat(hour) * (CGFloat.pi / 6)
    let isMajor = hour % 3 == 0
    let inner = isMajor ? markerInnerMajor : markerInnerMinor

    let outerPt = NSPoint(
        x: center.x + cos(angle) * markerOuter,
        y: center.y + sin(angle) * markerOuter
    )
    let innerPt = NSPoint(
        x: center.x + cos(angle) * inner,
        y: center.y + sin(angle) * inner
    )

    let tick = NSBezierPath()
    tick.move(to: outerPt)
    tick.line(to: innerPt)
    tick.lineWidth = isMajor ? 8 : 4
    tick.lineCapStyle = .round
    NSColor.black.setStroke()
    tick.stroke()
}

// Hands at 10:10 (the classic clock-ad time, also frames a smile shape)
// Hour hand: points to 10 - angle = 90° + 60° = 150° (since 10 is 2 hours back from 12)
let hourAngle = CGFloat.pi / 2 + (CGFloat.pi / 6) * 2  // 10 o'clock
let hourLength = dialRadius * 0.55
let hourEnd = NSPoint(
    x: center.x + cos(hourAngle) * hourLength,
    y: center.y + sin(hourAngle) * hourLength
)
let hourPath = NSBezierPath()
hourPath.move(to: center)
hourPath.line(to: hourEnd)
hourPath.lineWidth = 18
hourPath.lineCapStyle = .round
NSColor.black.setStroke()
hourPath.stroke()

// Minute hand: points to 2 (10:10) - angle = 90° - 60° = 30°
let minuteAngle = CGFloat.pi / 2 - (CGFloat.pi / 6) * 2  // 2 o'clock
let minuteLength = dialRadius * 0.78
let minuteEnd = NSPoint(
    x: center.x + cos(minuteAngle) * minuteLength,
    y: center.y + sin(minuteAngle) * minuteLength
)
let minutePath = NSBezierPath()
minutePath.move(to: center)
minutePath.line(to: minuteEnd)
minutePath.lineWidth = 14
minutePath.lineCapStyle = .round
NSColor.black.setStroke()
minutePath.stroke()

// Center cap - small black dot covering the hand pivot
let capRadius: CGFloat = 18
let capRect = NSRect(
    x: center.x - capRadius,
    y: center.y - capRadius,
    width: capRadius * 2,
    height: capRadius * 2
)
NSColor.black.setFill()
NSBezierPath(ovalIn: capRect).fill()

ctx.restoreGState()

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
