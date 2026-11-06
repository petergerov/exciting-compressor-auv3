import SwiftUI

/// IN/OUT level as segmented LED ladders behind a glass window, the way
/// outboard gear showed level before screens: ten lamps over 48 dB, green
/// through amber into red. Each row shows the louder side.
struct LevelLadder: View {
    let input: StereoLevel
    let output: StereoLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LadderRow(label: "IN", level: input.loudest, theme: GearTheme.current)
            LadderRow(label: "OUT", level: output.loudest, theme: GearTheme.current)
        }
        .frame(width: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Levels")
        .accessibilityValue("In \(Self.decibels(input.loudest)), out \(Self.decibels(output.loudest))")
    }

    private static func decibels(_ linear: Float) -> String {
        linear > 0 ? String(format: "%.0f decibels", 20 * log10(linear)) : "silent"
    }
}

private struct LadderRow: View {
    let label: String
    let level: Float
    let theme: GearPalette

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(theme.textLight.opacity(0.85))
                .shadow(color: .black.opacity(0.6), radius: 0, y: 0.5)
                .frame(width: 18, alignment: .leading)

            LadderSegments(lit: LadderSegments.litCount(for: level), theme: theme)
                .frame(height: 7)
                .padding(.horizontal, 2.5)
                .padding(.vertical, 2)
                .background(LedWindow(cornerRadius: 2))
        }
    }
}

private struct LadderSegments: View {
    static let count = 10
    /// Bottom of the ladder; the top lamp is 0 dBFS.
    static let floorDB: Float = -48

    let lit: Int
    let theme: GearPalette

    static func litCount(for linear: Float) -> Int {
        let db = 20 * log10(max(linear, 1e-6))
        let fraction = min(1, max(0, (db - floorDB) / -floorDB))
        return Int((fraction * Float(count)).rounded(.down))
    }

    var body: some View {
        Canvas { context, size in
            let gap = size.width * 0.055 / CGFloat(Self.count - 1) * CGFloat(Self.count)
            let cellWidth = (size.width - gap * CGFloat(Self.count - 1)) / CGFloat(Self.count)

            for i in 0..<Self.count {
                let cell = CGRect(x: CGFloat(i) * (cellWidth + gap), y: 0,
                                  width: cellWidth, height: size.height)
                let path = Path(roundedRect: cell, cornerRadius: min(1.5, cellWidth * 0.35))
                if i < lit {
                    let colour = segmentColour(i)
                    context.fill(path.strokedPath(.init(lineWidth: 2.4)), with: .color(colour.opacity(0.35)))
                    context.fill(path, with: .color(colour))
                } else {
                    context.fill(path, with: .color(theme.meterOff))
                    context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
                }
            }
        }
    }

    private func segmentColour(_ index: Int) -> Color {
        switch index {
        case 0..<6: theme.meterGreen
        case 6..<8: theme.meterAmber
        default: theme.meterRed
        }
    }
}
