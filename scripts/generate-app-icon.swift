import Foundation
import CoreGraphics
import ImageIO

// Original code-drawn branch-and-merge mark; no copied artwork and no alpha channel.
// Run: swift scripts/generate-app-icon.swift apple/Gitlabio/Assets.xcassets/AppIcon.appiconset/AppIcon.png
let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
    bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
// Diagonal brand gradient: orange → coral → purple (CoreGraphics origin is bottom-left).
let gradient = CGGradient(colorsSpace: space, colors: [color(0xFCA326), color(0xFC6D26), color(0xE24329), color(0x7B58CF)] as CFArray,
                          locations: [0, 0.32, 0.55, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Soft highlight for depth.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: size * 0.3, y: size * 0.78), startRadius: 0,
                           endCenter: CGPoint(x: size * 0.3, y: size * 0.78), endRadius: size * 0.65, options: [])
// Mark: same geometry as AppMark in OnboardingView (y flipped).
func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: size * x, y: size * (1 - y)) }
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(size * 0.075)
context.setLineCap(.round)
context.move(to: p(0.34, 0.24)); context.addLine(to: p(0.34, 0.76))
context.move(to: p(0.34, 0.56))
context.addCurve(to: p(0.68, 0.30), control1: p(0.34, 0.40), control2: p(0.68, 0.48))
context.strokePath()
for point in [p(0.34, 0.24), p(0.34, 0.76), p(0.68, 0.30)] {
    let r = size * 0.09
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
    let inner = r - size * 0.05
    context.setFillColor(color(0xE24329))
    context.fillEllipse(in: CGRect(x: point.x - inner, y: point.y - inner, width: inner * 2, height: inner * 2))
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not encode app icon") }
print("Wrote original 1024px RGB app icon")
