import UIKit

struct ThemePalette {
    let pink: UIColor
    let pinkSoft: UIColor
    let yellow: UIColor
    let yellowSoft: UIColor
    let mint: UIColor
    let mintSoft: UIColor
    let sky: UIColor
    let skySoft: UIColor
    let lavender: UIColor
    let lavenderSoft: UIColor
    let orange: UIColor
    let orangeSoft: UIColor
    let coral: UIColor
    let coralSoft: UIColor
    let cream: UIColor
    let page: UIColor
    let line: UIColor
    let ink: UIColor
    let secondaryInk: UIColor
    let card: UIColor
    let field: UIColor
}

enum Theme {
    private static let key = "snow_king_theme"

    private static let palettes: [ThemePalette] = [
        ThemePalette(
            pink: .hex(0xFF6B9D), pinkSoft: .hex(0xFFD4E5),
            yellow: .hex(0xFFD93D), yellowSoft: .hex(0xFFF3C4),
            mint: .hex(0x6BCB77), mintSoft: .hex(0xC8F7D4),
            sky: .hex(0x4D96FF), skySoft: .hex(0xC5E0FF),
            lavender: .hex(0xC77DFF), lavenderSoft: .hex(0xEDD6FF),
            orange: .hex(0xFF8C42), orangeSoft: .hex(0xFFE0CC),
            coral: .hex(0xFF6B6B), coralSoft: .hex(0xFFD6D6),
            cream: .hex(0xFFF8F0), page: .hex(0xF5F7FB), line: .hex(0xE7EBF2),
            ink: .hex(0x2D3142), secondaryInk: .hex(0x4A4E69), card: .hex(0xFFFFFF), field: .hex(0xF7F8FC)
        ),
        ThemePalette(
            pink: .hex(0x8A5E49), pinkSoft: .hex(0xEAD8CA),
            yellow: .hex(0xB6925B), yellowSoft: .hex(0xF4E8D4),
            mint: .hex(0x788B6B), mintSoft: .hex(0xE1E9D9),
            sky: .hex(0x819290), skySoft: .hex(0xE1E9E6),
            lavender: .hex(0x98847A), lavenderSoft: .hex(0xE9DFD9),
            orange: .hex(0xB47650), orangeSoft: .hex(0xF0DDD0),
            coral: .hex(0xA56155), coralSoft: .hex(0xEFDAD5),
            cream: .hex(0xFBF6EC), page: .hex(0xF6F0E7), line: .hex(0xDDD2C6),
            ink: .hex(0x44352C), secondaryInk: .hex(0x725F52), card: .hex(0xFFFCF7), field: .hex(0xF1E9DF)
        ),
        ThemePalette(
            pink: .hex(0x4F735B), pinkSoft: .hex(0xD6E4D7),
            yellow: .hex(0xB58B4C), yellowSoft: .hex(0xF1E5C9),
            mint: .hex(0x6D9476), mintSoft: .hex(0xDCEBDD),
            sky: .hex(0x6C8F86), skySoft: .hex(0xDDEAE5),
            lavender: .hex(0x80927E), lavenderSoft: .hex(0xE2E9DE),
            orange: .hex(0xA97745), orangeSoft: .hex(0xECDCCB),
            coral: .hex(0xA15F52), coralSoft: .hex(0xEBD8D2),
            cream: .hex(0xF7F4E9), page: .hex(0xEEF3EA), line: .hex(0xCBD8C9),
            ink: .hex(0x2F4235), secondaryInk: .hex(0x5D7062), card: .hex(0xFBFCF7), field: .hex(0xE5EDE2)
        )
    ]

    static var index: Int {
        let stored = UserDefaults.standard.object(forKey: key) as? Int
        return min(max(stored ?? 2, 0), palettes.count - 1)
    }

    static var palette: ThemePalette { palettes[index] }
    static var names: [String] { ["马卡龙色", "奶油大地", "暖茶森绿"] }
    static var page: UIColor { palette.page }
    static var cream: UIColor { palette.cream }
    static var card: UIColor { palette.card }
    static var field: UIColor { palette.field }
    static var ink: UIColor { palette.ink }
    static var secondaryInk: UIColor { palette.secondaryInk }
    static var line: UIColor { palette.line }
    static var mint: UIColor { palette.mint }
    static var mintSoft: UIColor { palette.mintSoft }
    static var sky: UIColor { palette.sky }
    static var skySoft: UIColor { palette.skySoft }
    static var pink: UIColor { palette.pink }
    static var pinkSoft: UIColor { palette.pinkSoft }
    static var yellow: UIColor { palette.yellow }
    static var yellowSoft: UIColor { palette.yellowSoft }
    static var coral: UIColor { palette.coral }
    static var coralSoft: UIColor { palette.coralSoft }
    static var lavender: UIColor { palette.lavender }
    static var orange: UIColor { palette.orange }

    static var statusRunning: UIColor { [.hex(0x16A34A), .hex(0x617254), .hex(0x477557)][index] }
    static var statusClosed: UIColor { [.hex(0xEF4444), .hex(0x95564A), .hex(0x9B564A)][index] }
    static var statusIdle: UIColor { [.hex(0x0284C7), .hex(0x7C5D47), .hex(0x68744C)][index] }
    static var addAccent: UIColor { [.hex(0x267E44), .hex(0x617254), .hex(0x3F6C4E)][index] }
    static var sortAccent: UIColor { [.hex(0x2F914E), .hex(0x6C7B5D), .hex(0x527C5E)][index] }
    static var gameAccent: UIColor { [.hex(0x496953), .hex(0x5C4E42), .hex(0x435D4B)][index] }
    static var currentAccent: UIColor { [.hex(0x2B7D42), .hex(0x617254), .hex(0x477557)][index] }
    static var controlSoft: UIColor { [.hex(0xF2F4F8), .hex(0xF1E9DF), .hex(0xE0E8DD)][index] }
    static var gameBar: UIColor { [.hex(0xF8FCF9), .hex(0xF7F1E8), .hex(0xEDF3E9)][index] }

    static func selectNext() {
        UserDefaults.standard.set((index + 1) % palettes.count, forKey: key)
    }

    static func select(_ value: Int) {
        UserDefaults.standard.set(min(max(value, 0), palettes.count - 1), forKey: key)
    }

    static func symbol(_ name: String, size: CGFloat = 17, weight: UIImage.SymbolWeight = .medium) -> UIImage? {
        let androidNames: [String: String] = [
            "magnifyingglass": "search", "plus": "plus", "xmark": "close",
            "chevron.left": "back", "chevron.right": "chevron", "chevron.down": "chevron-down",
            "gearshape": "settings", "paintpalette": "palette", "checkmark": "check",
            "checkmark.circle": "check", "checkmark.circle.fill": "check",
            "checklist": "batch", "arrow.up.arrow.down": "sort", "folder": "folder",
            "person": "account", "person.crop.circle": "account",
            "rectangle.split.2x1": "horizontal", "rectangle.split.1x2": "vertical",
            "rectangle.3.group": "layout", "square.and.arrow.down": "save",
            "arrow.clockwise": "refresh", "lock": "lock", "lock.open": "lock-open",
            "scroll": "script", "bolt": "bolt", "speaker.slash": "volume-off",
            "eye.slash": "eye-off", "checkmark.shield": "shield",
            "externaldrive": "cache", "pause": "pause", "info.circle": "info",
            "doc": "file", "doc.badge.plus": "file", "pencil": "edit", "trash": "trash",
            "person.badge.plus": "account", "person.2": "group",
            "arrow.up.right.square": "launch", "arrow.down.to.line": "download",
            "stop": "stop", "script": "script", "group": "group"
        ]
        if let androidName = androidNames[name] {
            return lineIcon(androidName, size: size)
        }
        return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    static func lineIcon(_ name: String, size: CGFloat = 17) -> UIImage? {
        AndroidLineIcon.image(name: name, size: size)
    }
}

private enum AndroidLineIcon {
    static func image(name: String, size: CGFloat) -> UIImage? {
        guard size > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { renderer in
            let context = renderer.cgContext
            let scale = size / 24
            context.scaleBy(x: scale, y: scale)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setFillColor(UIColor.clear.cgColor)
            context.setLineWidth(1.9)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            func stroke(_ path: CGPath) { context.addPath(path); context.strokePath() }
            func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
                let path = CGMutablePath(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2)); stroke(path)
            }
            func poly(_ points: [CGPoint], close: Bool = false) {
                guard let first = points.first else { return }
                let path = CGMutablePath(); path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) }
                if close { path.closeSubpath() }; stroke(path)
            }
            func rect(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ radius: CGFloat) {
                stroke(CGPath(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
                context.strokeEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
            func arc(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ start: CGFloat, _ sweep: CGFloat) {
                let center = CGPoint(x: (x1 + x2) / 2, y: (y1 + y2) / 2)
                let radius = min(x2 - x1, y2 - y1) / 2
                context.addArc(center: center, radius: radius, startAngle: start * .pi / 180, endAngle: (start + sweep) * .pi / 180, clockwise: false)
                context.strokePath()
            }
            func bezier(_ build: (CGMutablePath) -> Void, close: Bool = false) {
                let path = CGMutablePath(); build(path); if close { path.closeSubpath() }; stroke(path)
            }

            switch name {
            case "search":
                circle(10.5, 10.5, 5.7); line(14.8, 14.8, 20, 20)
            case "plus":
                line(12, 5, 12, 19); line(5, 12, 19, 12)
            case "close":
                line(6, 6, 18, 18); line(18, 6, 6, 18)
            case "back":
                poly([.init(x: 15, y: 5), .init(x: 8, y: 12), .init(x: 15, y: 19)])
            case "chevron":
                poly([.init(x: 9, y: 5), .init(x: 16, y: 12), .init(x: 9, y: 19)])
            case "chevron-down":
                poly([.init(x: 5, y: 9), .init(x: 12, y: 16), .init(x: 19, y: 9)])
            case "settings":
                let path = CGMutablePath()
                let radii: [CGFloat] = [8.1, 8.1, 10, 10, 10, 10, 8.1, 8.1]
                for index in 0..<64 {
                    let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi * 2 / 64
                    let radius = radii[index % radii.count]
                    let point = CGPoint(x: 12 + cos(angle) * radius, y: 12 + sin(angle) * radius)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath(); stroke(path); circle(12, 12, 3.1)
            case "palette":
                bezier({ path in
                    path.move(to: .init(x: 12, y: 3))
                    path.addCurve(to: .init(x: 3, y: 12), control1: .init(x: 6.8, y: 3), control2: .init(x: 3, y: 6.8))
                    path.addCurve(to: .init(x: 12.2, y: 21), control1: .init(x: 3, y: 17.2), control2: .init(x: 7, y: 21))
                    path.addCurve(to: .init(x: 14.2, y: 17.8), control1: .init(x: 14.2, y: 21), control2: .init(x: 15.1, y: 19.2))
                    path.addCurve(to: .init(x: 16.2, y: 15), control1: .init(x: 13.4, y: 16.4), control2: .init(x: 14.4, y: 15))
                    path.addLine(to: .init(x: 18.4, y: 15))
                    path.addCurve(to: .init(x: 21, y: 12), control1: .init(x: 20.1, y: 15), control2: .init(x: 21, y: 13.7))
                    path.addCurve(to: .init(x: 12, y: 3), control1: .init(x: 21, y: 6.8), control2: .init(x: 17.2, y: 3))
                }, close: true)
                circle(8, 8.5, 1); circle(12, 6.7, 1); circle(16.2, 8.8, 1); circle(7.5, 13, 1)
            case "check":
                poly([.init(x: 5, y: 12.5), .init(x: 10, y: 17.5), .init(x: 19, y: 7)])
            case "batch":
                for row in 0..<3 {
                    let y = CGFloat(4 + row * 6)
                    rect(3, y, 8, y + 5, 1)
                    poly([.init(x: 4.2, y: y + 2.3), .init(x: 5.4, y: y + 3.5), .init(x: 7.2, y: y + 1.4)])
                    line(11, y + 2.5, CGFloat(21 - row * 2), y + 2.5)
                }
            case "sort":
                line(6, 4, 6, 20); poly([.init(x: 2.8, y: 16.8), .init(x: 6, y: 20), .init(x: 9.2, y: 16.8)])
                line(12, 6, 21, 6); line(12, 12, 18, 12); line(12, 18, 15, 18)
            case "group":
                circle(9, 8, 3); circle(17, 9, 2.3)
                bezier { path in path.move(to: .init(x: 3.8, y: 19)); path.addCurve(to: .init(x: 14.2, y: 19), control1: .init(x: 4.8, y: 13), control2: .init(x: 13.2, y: 13)) }
                bezier { path in path.move(to: .init(x: 13, y: 18.5)); path.addCurve(to: .init(x: 21, y: 18.5), control1: .init(x: 13.8, y: 14), control2: .init(x: 20.2, y: 14)) }
            case "account":
                circle(12, 8, 3.5)
                bezier { path in path.move(to: .init(x: 4.2, y: 20)); path.addCurve(to: .init(x: 19.8, y: 20), control1: .init(x: 5.5, y: 12.8), control2: .init(x: 18.5, y: 12.8)) }
            case "horizontal":
                rect(3, 5, 21, 19, 2); line(12, 5, 12, 19)
            case "vertical":
                rect(4, 3, 20, 21, 2); line(4, 12, 20, 12)
            case "layout":
                rect(3, 4, 21, 20, 2); line(10, 4, 10, 20); line(10, 11, 21, 11)
            case "save":
                rect(4, 3, 20, 21, 2); rect(7, 3, 16.5, 9, 0.8); rect(8, 14, 16, 21, 0.8)
            case "refresh":
                arc(4, 4, 20, 20, 200, 190); poly([.init(x: 16.7, y: 4.1), .init(x: 20.2, y: 4.4), .init(x: 19.8, y: 7.9)])
                arc(4, 4, 20, 20, 20, 190); poly([.init(x: 7.3, y: 19.9), .init(x: 3.8, y: 19.6), .init(x: 4.2, y: 16.1)])
            case "lock", "lock-open":
                bezier { path in
                    path.move(to: .init(x: name == "lock" ? 7 : 8, y: 11)); path.addLine(to: .init(x: name == "lock" ? 7 : 8, y: 8))
                    path.addCurve(to: .init(x: name == "lock" ? 12 : 13, y: 3), control1: .init(x: name == "lock" ? 7 : 8, y: 4.8), control2: .init(x: name == "lock" ? 9 : 10, y: 3))
                    path.addCurve(to: .init(x: 17, y: name == "lock" ? 8 : 7), control1: .init(x: name == "lock" ? 15 : 15.5, y: 3), control2: .init(x: 17, y: name == "lock" ? 4.8 : 4.6))
                    if name == "lock" { path.addLine(to: .init(x: 17, y: 11)) }
                }
                rect(5, 10, 19, 21, 2); circle(12, 15, 1.1); line(12, 16, 12, 18.5)
            case "script":
                rect(5, 3, 19, 21, 2); poly([.init(x: 14, y: 3), .init(x: 14, y: 8), .init(x: 19, y: 8)])
                poly([.init(x: 9.5, y: 11), .init(x: 7, y: 13.5), .init(x: 9.5, y: 16)])
                poly([.init(x: 14.5, y: 11), .init(x: 17, y: 13.5), .init(x: 14.5, y: 16)])
            case "bolt":
                poly([.init(x: 13.5, y: 2.5), .init(x: 6, y: 13), .init(x: 11, y: 13), .init(x: 9.8, y: 21.5), .init(x: 18, y: 10.5), .init(x: 13, y: 10.5)], close: true)
            case "volume-off":
                poly([.init(x: 4, y: 9), .init(x: 8, y: 9), .init(x: 13, y: 5), .init(x: 13, y: 19), .init(x: 8, y: 15), .init(x: 4, y: 15)], close: true)
                line(17, 9, 22, 14); line(22, 9, 17, 14)
            case "eye-off":
                bezier { path in path.move(to: .init(x: 3, y: 12)); path.addCurve(to: .init(x: 12, y: 6), control1: .init(x: 5.3, y: 7.8), control2: .init(x: 8.2, y: 6)); path.addCurve(to: .init(x: 21, y: 12), control1: .init(x: 15.8, y: 6), control2: .init(x: 18.7, y: 7.8)); path.addCurve(to: .init(x: 12, y: 18), control1: .init(x: 18.7, y: 16.2), control2: .init(x: 15.8, y: 18)); path.addCurve(to: .init(x: 3, y: 12), control1: .init(x: 8.2, y: 18), control2: .init(x: 5.3, y: 16.2)) }
                circle(12, 12, 3); line(4, 4, 20, 20)
            case "shield":
                bezier({ path in path.move(to: .init(x: 12, y: 3)); path.addLine(to: .init(x: 20, y: 6)); path.addLine(to: .init(x: 19, y: 14)); path.addCurve(to: .init(x: 12, y: 21.5), control1: .init(x: 18.5, y: 17.4), control2: .init(x: 16.2, y: 19.7)); path.addCurve(to: .init(x: 5, y: 14), control1: .init(x: 7.8, y: 19.7), control2: .init(x: 5.5, y: 17.4)); path.addLine(to: .init(x: 4, y: 6)) }, close: true)
                poly([.init(x: 8, y: 12), .init(x: 10.8, y: 14.8), .init(x: 16.5, y: 9)])
            case "folder":
                poly([.init(x: 3, y: 7), .init(x: 9, y: 7), .init(x: 11, y: 9), .init(x: 21, y: 9), .init(x: 19.5, y: 19), .init(x: 4.5, y: 19)], close: true)
            case "cache":
                context.strokeEllipse(in: .init(x: 5, y: 4, width: 14, height: 5)); line(5, 6.5, 5, 18); line(19, 6.5, 19, 18)
                bezier { path in path.move(to: .init(x: 5, y: 9)); path.addCurve(to: .init(x: 19, y: 9), control1: .init(x: 8, y: 12), control2: .init(x: 16, y: 12)) }
                bezier { path in path.move(to: .init(x: 5, y: 14)); path.addCurve(to: .init(x: 19, y: 14), control1: .init(x: 8, y: 17), control2: .init(x: 16, y: 17)) }
                bezier { path in path.move(to: .init(x: 5, y: 18)); path.addCurve(to: .init(x: 19, y: 18), control1: .init(x: 8, y: 21), control2: .init(x: 16, y: 21)) }
            case "pause":
                rect(6, 4, 10, 20, 1); rect(14, 4, 18, 20, 1)
            case "info":
                circle(12, 12, 9); line(12, 10.5, 12, 17); circle(12, 7, 0.7)
            case "file":
                rect(5, 3, 19, 21, 2); poly([.init(x: 14, y: 3), .init(x: 14, y: 8), .init(x: 19, y: 8)]); line(8, 13, 16, 13); line(8, 17, 14, 17)
            case "edit":
                poly([.init(x: 5, y: 19), .init(x: 8.5, y: 18.3), .init(x: 19.2, y: 7.6), .init(x: 16.4, y: 4.8), .init(x: 5.7, y: 15.5)], close: true); line(14.8, 6.4, 17.6, 9.2)
            case "download":
                line(12, 3, 12, 15); poly([.init(x: 7.5, y: 11), .init(x: 12, y: 15.5), .init(x: 16.5, y: 11)]); poly([.init(x: 5, y: 18), .init(x: 5, y: 21), .init(x: 19, y: 21), .init(x: 19, y: 18)])
            case "scan":
                poly([.init(x: 4, y: 9), .init(x: 4, y: 4), .init(x: 9, y: 4)]); poly([.init(x: 15, y: 4), .init(x: 20, y: 4), .init(x: 20, y: 9)]); poly([.init(x: 4, y: 15), .init(x: 4, y: 20), .init(x: 9, y: 20)]); poly([.init(x: 15, y: 20), .init(x: 20, y: 20), .init(x: 20, y: 15)]); line(7, 12, 17, 12)
            case "launch":
                poly([.init(x: 5, y: 13), .init(x: 12, y: 5), .init(x: 19, y: 13), .init(x: 15, y: 13), .init(x: 15, y: 20), .init(x: 9, y: 20), .init(x: 9, y: 13)], close: true)
            case "stop":
                rect(5, 5, 19, 19, 2)
            case "trash":
                rect(6, 7, 18, 21, 2); line(4.5, 7, 19.5, 7); line(9, 3.5, 15, 3.5); line(10, 11, 10, 17); line(14, 11, 14, 17)
            default:
                circle(12, 12, 7)
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

extension UIColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension UIView {
    func rounded(_ radius: CGFloat = 12, border: UIColor? = nil, width: CGFloat = 1) {
        layer.cornerRadius = radius
        layer.masksToBounds = true
        layer.borderColor = border?.cgColor
        layer.borderWidth = border == nil ? 0 : width
    }
}

extension UIButton {
    static func iconButton(systemName: String, tint: UIColor = Theme.ink, size: CGFloat = 42) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Theme.symbol(systemName, size: min(18, size * 0.43), weight: .semibold), for: .normal)
        button.tintColor = tint
        button.backgroundColor = Theme.card
        button.rounded(size / 2, border: Theme.line)
        button.imageView?.contentMode = .scaleAspectFit
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }
}

struct ThemedSheetAction {
    let title: String
    let icon: String
    let background: UIColor
    var destructive = false
    let handler: () -> Void
}

final class ThemedActionSheetController: UIViewController {
    private let sheetTitle: String
    private let sheetMessage: String?
    private let actions: [ThemedSheetAction]
    private let panel = UIView()

    init(title: String, message: String? = nil, actions: [ThemedSheetAction]) {
        self.sheetTitle = title
        self.sheetMessage = message
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let dim = UIButton(type: .custom)
        dim.backgroundColor = UIColor(red: 20 / 255, green: 32 / 255, blue: 24 / 255, alpha: 0.42)
        dim.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        panel.backgroundColor = Theme.card
        panel.layer.cornerRadius = 24
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.clipsToBounds = true
        panel.transform = CGAffineTransform(translationX: 0, y: 900)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let handleHolder = UIView()
        handleHolder.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let handle = UIView()
        handle.backgroundColor = Theme.ink
        handle.rounded(2.5)
        handle.translatesAutoresizingMaskIntoConstraints = false
        handleHolder.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: handleHolder.centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: handleHolder.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 46),
            handle.heightAnchor.constraint(equalToConstant: 5)
        ])
        stack.addArrangedSubview(handleHolder)

        let titleLabel = UILabel()
        titleLabel.text = sheetTitle
        titleLabel.textAlignment = .center
        titleLabel.textColor = Theme.ink
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(titleLabel)
        if let sheetMessage, !sheetMessage.isEmpty {
            let message = UILabel()
            message.text = sheetMessage
            message.numberOfLines = 0
            message.textAlignment = .center
            message.textColor = Theme.secondaryInk
            message.font = .systemFont(ofSize: 11, weight: .semibold)
            message.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
            stack.addArrangedSubview(message)
            stack.setCustomSpacing(8, after: message)
        }

        actions.enumerated().forEach { index, action in
            let row = actionRow(action)
            row.heightAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(row)
            if index < actions.count - 1 { stack.setCustomSpacing(5, after: row) }
        }
        let footer = UIView()
        footer.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(footer)

        let estimated = 80 + (sheetMessage == nil ? 0 : 40) + actions.count * 61
        let height = min(CGFloat(estimated), UIScreen.main.bounds.height * 0.82)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor), dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor), dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor), panel.heightAnchor.constraint(equalToConstant: height),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor), scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16), scroll.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.24, delay: 0, options: .curveEaseOut) { self.panel.transform = .identity }
    }

    private func actionRow(_ action: ThemedSheetAction) -> UIButton {
        var title = AttributedString(action.title)
        title.font = .systemFont(ofSize: 14, weight: .bold)
        title.foregroundColor = action.destructive ? Theme.statusClosed : Theme.ink
        var config = UIButton.Configuration.plain()
        config.attributedTitle = title
        config.image = Theme.symbol(action.icon, size: 19, weight: .semibold)
        config.imagePlacement = .leading
        config.imagePadding = 12
        config.baseForegroundColor = action.destructive ? Theme.statusClosed : Theme.ink
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 44)
        config.background.backgroundColor = action.background
        config.background.cornerRadius = 12
        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        let arrow = UIImageView(image: Theme.symbol("chevron.right", size: 15, weight: .bold))
        arrow.tintColor = action.destructive ? Theme.statusClosed : Theme.ink
        arrow.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(arrow)
        NSLayoutConstraint.activate([arrow.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14), arrow.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
        button.addAction(UIAction { [weak self] _ in self?.close(then: action.handler) }, for: .touchUpInside)
        return button
    }

    @objc private func cancel() { close() }

    private func close(then completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, animations: { self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.bounds.height) }) { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }
}

extension Notification.Name {
    static let snowKingCacheSettingChanged = Notification.Name("snowking.cache-setting-changed")
}

extension Notification.Name {
    static let snowKingGameCacheCleared = Notification.Name("snowking.game-cache-cleared")
}
