import AppKit

// Original vector artwork, rendered locally. No downloaded assets or user data.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ ink: NSColor) {
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink])
}
func render(_ size: NSSize, scale: Int, name: String, draw: () -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                              pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let bitmapContext = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = bitmapContext.cgContext
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    rep.size = size
    let type: NSBitmapImageRep.FileType = name.hasSuffix(".tiff") ? .tiff : .png
    try rep.representation(using: type, properties: [:])!.write(to: output.appendingPathComponent(name))
}
func icon() {
    let shadow = NSShadow(); shadow.shadowColor = color(0x153A67, 0.18); shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    rounded(NSRect(x: 80, y: 80, width: 864, height: 864), 192, color(0x153A67))
    NSGraphicsContext.restoreGraphicsState()
    let clip = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState(); clip.addClip()
    NSGradient(starting: color(0x257DA6), ending: color(0x10294D))!.draw(in: clip, angle: -45)
    color(0xFFFFFF, 0.06).setFill(); NSBezierPath(ovalIn: NSRect(x: 480, y: -240, width: 800, height: 800)).fill()
    NSGraphicsContext.restoreGraphicsState()
    // Four stepped radio bars and a small connected-status light.
    for (i, height) in [160.0, 260.0, 360.0, 460.0].enumerated() {
        rounded(NSRect(x: 236 + Double(i) * 144, y: 718 - height, width: 104, height: height), 35,
                i == 3 ? color(0x70E2D1) : color(0xF6FBFF))
    }
    rounded(NSRect(x: 236, y: 786, width: 536, height: 14), 7, color(0xB8D9E9, 0.35))
}
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "AppIcon.iconset/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(NSSize(width: size, height: size), scale: scale, name: name) {
            NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
            icon()
        }
    }
}
func background() {
    color(0xF4F7FB).setFill(); NSRect(x: 0, y: 0, width: 760, height: 500).fill()
    // Quiet decorative radio rings in the upper right.
    for radius in [90.0, 140.0, 190.0] {
        let ring = NSBezierPath(ovalIn: NSRect(x: 720 - radius, y: 34 - radius, width: radius * 2, height: radius * 2))
        color(0xDDE8F2).setStroke(); ring.lineWidth = 1; ring.stroke()
    }
    text("LTE / MAC", 40, 28, 11, .semibold, color(0x347FA0))
    text("LTEModemCompact", 38, 52, 31, .semibold, color(0x152D46))
    text("让 Mac 连接更多可能", 40, 98, 15, .regular, color(0x61758A))
    rounded(NSRect(x: 40, y: 155, width: 680, height: 183), 22, color(0xFFFFFF, 0.88))
    text("拖入右侧文件夹，即可安装", 274, 169, 13, .medium, color(0x61758A))
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 349, y: 251)); arrow.line(to: NSPoint(x: 411, y: 251))
    arrow.move(to: NSPoint(x: 399, y: 239)); arrow.line(to: NSPoint(x: 411, y: 251)); arrow.line(to: NSPoint(x: 399, y: 263))
    color(0x409CB0).setStroke(); arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    text("安装之后", 40, 369, 12, .semibold, color(0x347FA0))
    text("从“应用程序”打开，再点菜单栏天线图标。", 40, 393, 14, .medium, color(0x243F59))
    text("升级前请先退出旧版，已有短信会保留。", 40, 420, 12, .regular, color(0x61758A))
    text("APPLE SILICON  ·  macOS 13+", 40, 471, 10, .medium, color(0x8393A3))
}
try render(NSSize(width: 760, height: 500), scale: 2, name: "installer-background.tiff", draw: background)
try render(NSSize(width: 760, height: 500), scale: 2, name: "installer-preview.png", draw: background)
// Design preview only: Finder supplies these real file icons when the DMG opens.
try render(NSSize(width: 760, height: 500), scale: 2, name: "installer-layout-preview.png") {
    background()
    let appIcon = NSImage(contentsOf: output.appendingPathComponent("AppIcon.iconset/icon_128x128" + "@2x" + ".png"))!
    let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    let noteIcon = NSWorkspace.shared.icon(for: .plainText)
    for (image, x, y) in [(appIcon, 210.0, 250.0), (folderIcon, 550.0, 250.0), (noteIcon, 663.0, 407.0)] {
        image.draw(in: NSRect(x: x - 40, y: y - 40, width: 80, height: 80), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    for (label, x, y) in [("LTEModemCompact", 210.0, 298.0), ("Applications", 550.0, 298.0), ("安装说明.txt", 663.0, 455.0)] {
        let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        text(label, x - width / 2, y, 12, .regular, color(0x243F59))
    }
}
