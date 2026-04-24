import AppKit

struct IconSize {
    let filename: String
    let points: CGFloat
    let scale: CGFloat

    var pixels: Int { Int(points * scale) }
}

let sizes: [IconSize] = [
    .init(filename: "AppIcon-20@2x.png", points: 20, scale: 2),
    .init(filename: "AppIcon-20@3x.png", points: 20, scale: 3),
    .init(filename: "AppIcon-29@2x.png", points: 29, scale: 2),
    .init(filename: "AppIcon-29@3x.png", points: 29, scale: 3),
    .init(filename: "AppIcon-40@2x.png", points: 40, scale: 2),
    .init(filename: "AppIcon-40@3x.png", points: 40, scale: 3),
    .init(filename: "AppIcon-60@2x.png", points: 60, scale: 2),
    .init(filename: "AppIcon-60@3x.png", points: 60, scale: 3),
    .init(filename: "AppIcon-20.png", points: 1024, scale: 1),
    .init(filename: "AppIcon-20-ipad@1x.png", points: 20, scale: 1),
    .init(filename: "AppIcon-20-ipad@2x.png", points: 20, scale: 2),
    .init(filename: "AppIcon-29-ipad@1x.png", points: 29, scale: 1),
    .init(filename: "AppIcon-29-ipad@2x.png", points: 29, scale: 2),
    .init(filename: "AppIcon-40-ipad@1x.png", points: 40, scale: 1),
    .init(filename: "AppIcon-40-ipad@2x.png", points: 40, scale: 2),
    .init(filename: "AppIcon-76@1x.png", points: 76, scale: 1),
    .init(filename: "AppIcon-76@2x.png", points: 76, scale: 2),
    .init(filename: "AppIcon-83.5@2x.png", points: 83.5, scale: 2)
]

let fileManager = FileManager.default
let projectRoot = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : fileManager.currentDirectoryPath)
let outputDirectory = projectRoot
    .appendingPathComponent("Preferans/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func bezierPath(cgPath: CGPath) -> NSBezierPath {
    let path = NSBezierPath()
    var points = [CGPoint](repeating: .zero, count: 3)
    cgPath.applyWithBlock { elementPointer in
        let element = elementPointer.pointee
        switch element.type {
        case .moveToPoint:
            path.move(to: element.points[0])
        case .addLineToPoint:
            path.line(to: element.points[0])
        case .addQuadCurveToPoint:
            points[0] = element.points[0]
            points[1] = element.points[1]
            let current = path.currentPoint
            let converted1 = CGPoint(
                x: current.x + (2.0 / 3.0) * (points[0].x - current.x),
                y: current.y + (2.0 / 3.0) * (points[0].y - current.y)
            )
            let converted2 = CGPoint(
                x: points[1].x + (2.0 / 3.0) * (points[0].x - points[1].x),
                y: points[1].y + (2.0 / 3.0) * (points[0].y - points[1].y)
            )
            path.curve(to: points[1], controlPoint1: converted1, controlPoint2: converted2)
        case .addCurveToPoint:
            path.curve(to: element.points[2], controlPoint1: element.points[0], controlPoint2: element.points[1])
        case .closeSubpath:
            path.close()
        @unknown default:
            break
        }
    }
    return path
}

func drawInnerGlow(in rect: CGRect, color glowColor: NSColor, width: CGFloat) {
    let outer = NSBezierPath(rect: rect.insetBy(dx: -width * 1.8, dy: -width * 1.8))
    let inner = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.18, yRadius: rect.height * 0.18)
    outer.append(inner.reversed)
    glowColor.setFill()
    outer.fill()
}

func drawBadge(in rect: CGRect, context: CGContext) {
    let outerPath = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)
    context.saveGState()
    outerPath.addClip()

    let backgroundGradient = NSGradient(colors: [
        color(0x050807),
        color(0x0B1614),
        color(0x122724)
    ])!
    backgroundGradient.draw(in: outerPath, angle: -30)

    let radial = NSGradient(starting: color(0xB99643, alpha: 0.22), ending: color(0xB99643, alpha: 0.01))!
    radial.draw(
        fromCenter: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.1),
        radius: 0,
        toCenter: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.1),
        radius: rect.width * 0.6,
        options: []
    )

    for index in 0..<8 {
        let alpha = 0.01 + CGFloat(index) * 0.003
        let inset = rect.width * (0.085 + CGFloat(index) * 0.022)
        let ringRect = rect.insetBy(dx: inset, dy: inset)
        let ring = NSBezierPath(ovalIn: ringRect)
        color(0xE9D6A7, alpha: alpha).setStroke()
        ring.lineWidth = max(1, rect.width * 0.0025)
        ring.stroke()
    }

    let flareRect = CGRect(
        x: rect.minX + rect.width * 0.12,
        y: rect.maxY - rect.height * 0.3,
        width: rect.width * 0.42,
        height: rect.height * 0.14
    )
    let flare = NSBezierPath(ovalIn: flareRect)
    color(0xFFFFFF, alpha: 0.05).setFill()
    flare.fill()

    context.restoreGState()

    let frameRect = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
    let frame = NSBezierPath(roundedRect: frameRect, xRadius: frameRect.width * 0.18, yRadius: frameRect.height * 0.18)
    color(0xF0DEB2, alpha: 0.16).setStroke()
    frame.lineWidth = max(2, rect.width * 0.012)
    frame.stroke()

    let frameInner = frameRect.insetBy(dx: rect.width * 0.018, dy: rect.height * 0.018)
    let frameInnerPath = NSBezierPath(roundedRect: frameInner, xRadius: frameInner.width * 0.16, yRadius: frameInner.height * 0.16)
    color(0xFFF8EA, alpha: 0.06).setStroke()
    frameInnerPath.lineWidth = max(1.5, rect.width * 0.006)
    frameInnerPath.stroke()

    let medallionRect = CGRect(
        x: rect.midX - rect.width * 0.2,
        y: rect.midY - rect.height * 0.21,
        width: rect.width * 0.4,
        height: rect.width * 0.4
    )
    let medallion = NSBezierPath(ovalIn: medallionRect)
    let medallionGradient = NSGradient(colors: [
        color(0xE9D5A1),
        color(0xBC8E39),
        color(0x6E4C16)
    ])!
    medallionGradient.draw(in: medallion, relativeCenterPosition: .zero)

    let medallionInnerRect = medallionRect.insetBy(dx: rect.width * 0.02, dy: rect.width * 0.02)
    let medallionInner = NSBezierPath(ovalIn: medallionInnerRect)
    let innerGradient = NSGradient(colors: [
        color(0x0D1615),
        color(0x070B0A)
    ])!
    innerGradient.draw(in: medallionInner, relativeCenterPosition: .zero)
    color(0xFFF2CB, alpha: 0.16).setStroke()
    medallionInner.lineWidth = max(1.5, rect.width * 0.005)
    medallionInner.stroke()

    let spadeSize = rect.width * 0.15
    let spadeCenter = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.006)
    let spadePath = CGMutablePath()
    spadePath.move(to: CGPoint(x: spadeCenter.x, y: spadeCenter.y + spadeSize * 0.72))
    spadePath.addCurve(
        to: CGPoint(x: spadeCenter.x - spadeSize * 0.5, y: spadeCenter.y + spadeSize * 0.08),
        control1: CGPoint(x: spadeCenter.x - spadeSize * 0.56, y: spadeCenter.y + spadeSize * 0.52),
        control2: CGPoint(x: spadeCenter.x - spadeSize * 0.62, y: spadeCenter.y + spadeSize * 0.28)
    )
    spadePath.addCurve(
        to: CGPoint(x: spadeCenter.x, y: spadeCenter.y - spadeSize * 0.5),
        control1: CGPoint(x: spadeCenter.x - spadeSize * 0.44, y: spadeCenter.y - spadeSize * 0.1),
        control2: CGPoint(x: spadeCenter.x - spadeSize * 0.16, y: spadeCenter.y - spadeSize * 0.4)
    )
    spadePath.addCurve(
        to: CGPoint(x: spadeCenter.x + spadeSize * 0.5, y: spadeCenter.y + spadeSize * 0.08),
        control1: CGPoint(x: spadeCenter.x + spadeSize * 0.16, y: spadeCenter.y - spadeSize * 0.4),
        control2: CGPoint(x: spadeCenter.x + spadeSize * 0.44, y: spadeCenter.y - spadeSize * 0.1)
    )
    spadePath.addCurve(
        to: CGPoint(x: spadeCenter.x, y: spadeCenter.y + spadeSize * 0.72),
        control1: CGPoint(x: spadeCenter.x + spadeSize * 0.62, y: spadeCenter.y + spadeSize * 0.28),
        control2: CGPoint(x: spadeCenter.x + spadeSize * 0.56, y: spadeCenter.y + spadeSize * 0.52)
    )
    spadePath.closeSubpath()
    let spade = bezierPath(cgPath: spadePath)
    color(0xFBF3E2).setFill()
    spade.fill()

    let stemRect = CGRect(
        x: spadeCenter.x - spadeSize * 0.09,
        y: spadeCenter.y - spadeSize * 0.55,
        width: spadeSize * 0.18,
        height: spadeSize * 0.42
    )
    let stem = NSBezierPath(roundedRect: stemRect, xRadius: stemRect.width / 2, yRadius: stemRect.width / 2)
    color(0xFBF3E2).setFill()
    stem.fill()

    let base = NSBezierPath()
    base.move(to: CGPoint(x: spadeCenter.x - spadeSize * 0.34, y: spadeCenter.y - spadeSize * 0.36))
    base.curve(
        to: CGPoint(x: spadeCenter.x + spadeSize * 0.34, y: spadeCenter.y - spadeSize * 0.36),
        controlPoint1: CGPoint(x: spadeCenter.x - spadeSize * 0.22, y: spadeCenter.y - spadeSize * 0.63),
        controlPoint2: CGPoint(x: spadeCenter.x + spadeSize * 0.22, y: spadeCenter.y - spadeSize * 0.63)
    )
    base.line(to: CGPoint(x: spadeCenter.x + spadeSize * 0.14, y: spadeCenter.y - spadeSize * 0.16))
    base.line(to: CGPoint(x: spadeCenter.x - spadeSize * 0.14, y: spadeCenter.y - spadeSize * 0.16))
    base.close()
    color(0xFBF3E2).setFill()
    base.fill()

    let pinTop = CGRect(
        x: rect.midX - rect.width * 0.02,
        y: rect.midY + rect.height * 0.24,
        width: rect.width * 0.04,
        height: rect.height * 0.04
    )
    let pinBottom = CGRect(
        x: rect.midX - rect.width * 0.02,
        y: rect.midY - rect.height * 0.28,
        width: rect.width * 0.04,
        height: rect.height * 0.04
    )
    let pinLeft = CGRect(
        x: rect.midX - rect.width * 0.28,
        y: rect.midY - rect.height * 0.02,
        width: rect.width * 0.04,
        height: rect.height * 0.04
    )
    let pinRight = CGRect(
        x: rect.midX + rect.width * 0.24,
        y: rect.midY - rect.height * 0.02,
        width: rect.width * 0.04,
        height: rect.height * 0.04
    )
    for pinRect in [pinTop, pinBottom, pinLeft, pinRight] {
        let pin = NSBezierPath(ovalIn: pinRect)
        color(0xE8D4A0, alpha: 0.5).setFill()
        pin.fill()
    }

    let glowRect = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
    drawInnerGlow(in: glowRect, color: color(0xFFFFFF, alpha: 0.012), width: rect.width * 0.03)
}

func renderIcon(size: Int, to url: URL) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw NSError(domain: "IconGeneration", code: 1)
    }

    let rect = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    drawBadge(in: rect, context: context)
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 2)
    }

    try png.write(to: url)
}

for icon in sizes {
    try renderIcon(size: icon.pixels, to: outputDirectory.appendingPathComponent(icon.filename))
    print("Wrote \(icon.filename)")
}
