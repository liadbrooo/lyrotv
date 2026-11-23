import AppKit
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let r = rect.insetBy(dx: 70, dy: 70)
    let shape = NSBezierPath(roundedRect: r, xRadius: 205, yRadius: 205)
    let gradient = NSGradient(starting: NSColor(srgbRed: 0.17, green: 0.23, blue: 0.36, alpha: 1), ending: NSColor(srgbRed: 0.035, green: 0.055, blue: 0.10, alpha: 1))!
    gradient.draw(in: shape, angle: 270)
    NSColor(srgbRed: 0.42, green: 0.76, blue: 1, alpha: 0.32).setStroke()
    shape.lineWidth = 8; shape.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 255, y: 255, width: 514, height: 514))
    NSColor(srgbRed: 0.42, green: 0.76, blue: 1, alpha: 0.13).setFill(); ring.fill()
    NSColor(srgbRed: 0.42, green: 0.76, blue: 1, alpha: 0.7).setStroke(); ring.lineWidth = 13; ring.stroke()
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 452, y: 683)); triangle.line(to: NSPoint(x: 666, y: 512)); triangle.line(to: NSPoint(x: 452, y: 341)); triangle.close()
    NSColor(srgbRed: 0.59, green: 0.84, blue: 1, alpha: 1).setFill(); triangle.fill()
    return true
}
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
