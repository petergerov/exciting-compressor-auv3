import SwiftUI

/// Excite-path gain reduction: one bar in a recessed slot, filling **right to
/// left** from rest. A bar that filled left-to-right would read as level, which
/// is the opposite of what this shows.
///
/// Position goes as `(dB / fullScale)^0.7`, so the first few dB take far more
/// of the track than the last few — the Motown setting lives at 10–20 dB, but
/// the threshold's first bite should still be visible.
struct GainReductionMeter: View {
    let reductionDB: Float

    private static let fullScale: Double = 30
    private static let scale: [(value: Double, text: String)] =
        [(0, "0"), (3, "3"), (6, "6"), (10, "10"), (20, "20"), (30, "30")]

    /// dB to a fraction of the track measured from the right edge.
    private static func fill(_ db: Double) -> Double {
        pow(min(max(db, 0), fullScale) / fullScale, 0.7)
    }

    var body: some View {
        let theme = GearTheme.current
        let db = Double(reductionDB)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                SilkscreenText(text: "Gain Reduction", size: 8)
                Spacer(minLength: 4)
                Text(db >= 0.15 ? String(format: "−%.1f dB", db) : "0.0 dB")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.ledText)
                    .shadow(color: theme.ledText.opacity(0.7), radius: 2)
            }

            // Labels placed by the same mapping as the fill, so they agree.
            BarScale(labels: Self.scale, fraction: { 1 - Self.fill($0) }, theme: theme)

            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    BarTrack(theme: theme)
                    // Amber through the working range, red past ~20 dB.
                    LinearGradient(colors: [theme.meterAmber, theme.meterAmber, theme.meterRed],
                                   startPoint: .trailing, endPoint: .leading)
                        .mask(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .frame(width: max(0, (geo.size.width - 3) * Self.fill(db)))
                        }
                        .padding(1.5)
                }
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gain reduction")
        .accessibilityValue(String(format: "%.0f decibels", reductionDB))
    }
}

/// The recessed slot a bar sits in.
private struct BarTrack: View {
    var theme: GearPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.ledBackground)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.7), lineWidth: 1))
            .overlay(
                // Light catching the lower lip, so the slot reads as cut in.
                RoundedRectangle(cornerRadius: 2)
                    .stroke(theme.panelEdgeLight.opacity(0.18), lineWidth: 0.6)
                    .padding(.top, 1.5)
            )
    }
}

/// Silkscreened tick labels above a bar.
private struct BarScale: View {
    var labels: [(value: Double, text: String)]
    var fraction: (Double) -> Double
    var theme: GearPalette

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(labels.enumerated()), id: \.offset) { _, entry in
                Text(entry.text)
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted.opacity(0.85))
                    .fixedSize()
                    // Nudged in at the ends so the outermost label stays on the plate.
                    .position(x: min(max(geo.size.width * fraction(entry.value), 6), geo.size.width - 6),
                              y: geo.size.height / 2)
            }
        }
        .frame(height: 9)
    }
}
