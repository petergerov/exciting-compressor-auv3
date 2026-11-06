import SwiftUI

/// A knob bound to one AU parameter: silkscreened caption, bakelite knob, LED
/// readout. Drag up/right to increase, double-click to reset.
struct ParameterKnob: View {
    let spec: ParameterSpec
    let viewModel: EditorViewModel
    var diameter: CGFloat = 54

    @State private var dragOrigin: Double?
    @State private var resets = 0

    /// Points of drag travel for the full range.
    private static let dragRange: CGFloat = 180

    var body: some View {
        let value = viewModel.value(for: spec)
        let normalized = spec.normalized(value)

        VStack(spacing: 5) {
            SilkscreenText(text: spec.shortName, size: 9.5)
                .frame(minHeight: 14)

            KnobView(normalized: normalized, theme: GearTheme.current)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .gesture(dragGesture(from: normalized))
                .onTapGesture(count: 2) {
                    viewModel.resetToDefault(spec)
                    resets += 1
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: resets)

            // Wide enough for the longest readout ("−∞ dB", "6.50 kHz") so the
            // window doesn't resize while the knob turns.
            LedReadout(text: spec.displayString(for: value), minWidth: max(diameter, 62))
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.name)
        .accessibilityValue(spec.displayString(for: value))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.02 : -0.02
            viewModel.setNormalized(normalized + step, for: spec)
        }
    }

    private func dragGesture(from normalized: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                if dragOrigin == nil {
                    dragOrigin = normalized
                    viewModel.beginEditing(spec)
                }
                let travel = gesture.translation.width - gesture.translation.height
                let target = (dragOrigin ?? normalized) + Double(travel / Self.dragRange)
                viewModel.setNormalized(target, for: spec)
            }
            .onEnded { _ in
                dragOrigin = nil
                viewModel.endEditing(spec)
            }
    }
}
