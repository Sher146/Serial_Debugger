import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift render_dmg_background.swift <output.png>")
}

let size = NSSize(width: 680, height: 440)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 880,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
bitmap.size = size
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

func centeredText(_ text: String, top: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let rect = NSRect(x: 24, y: size.height - top - 36, width: size.width - 48, height: 36)
    (text as NSString).draw(in: rect, withAttributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

let primary = NSColor(calibratedWhite: 0.16, alpha: 1)
let secondary = NSColor(calibratedWhite: 0.43, alpha: 1)
centeredText("Serial Monitor", top: 34, font: .systemFont(ofSize: 28, weight: .semibold), color: primary)
centeredText("拖动图标，完成安装", top: 79, font: .systemFont(ofSize: 15), color: secondary)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 304, y: 220))
arrow.line(to: NSPoint(x: 376, y: 220))
arrow.move(to: NSPoint(x: 364, y: 232))
arrow.line(to: NSPoint(x: 376, y: 220))
arrow.line(to: NSPoint(x: 364, y: 208))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.25, green: 0.48, blue: 0.83, alpha: 1).setStroke()
arrow.stroke()

centeredText("将 Serial Monitor 拖入右侧“应用程序”文件夹", top: 336,
             font: .systemFont(ofSize: 15, weight: .medium), color: primary)
centeredText("安装后从“应用程序”启动，并推出此安装磁盘", top: 366,
             font: .systemFont(ofSize: 12), color: secondary)

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法生成安装背景图")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
