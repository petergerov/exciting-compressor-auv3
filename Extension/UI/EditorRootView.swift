import AudioToolbox
import SwiftUI

/// Root editor: the two console channels from the Motown setup, bolted into a
/// rack chassis with the jj-midnight hardware look.
struct EditorRootView: View {
    let viewModel: EditorViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ChassisBackground(theme: GearTheme.current)

                HStack(spacing: 0) {
                    RackEar(theme: GearTheme.current).frame(width: PanelMetrics.earWidth)
                    Spacer(minLength: 0)
                    RackEar(theme: GearTheme.current).frame(width: PanelMetrics.earWidth)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    // Centred when the host gives more height than needed;
                    // the spacers collapse and it scrolls when it's short.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        PanelContent(viewModel: viewModel)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)

                FooterRivetStrip(theme: GearTheme.current)
                    .frame(width: geo.size.width, height: PanelMetrics.footerHeight)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .dark)
        .tint(GearTheme.accent)
        .task { await viewModel.monitorMeters() }
    }
}

private struct PanelContent: View {
    let viewModel: EditorViewModel

    var body: some View {
        let inset = PanelMetrics.sideInset
        VStack(spacing: 0) {
            EditorHeader(viewModel: viewModel)
                .padding(.horizontal, inset)
                .padding(.top, 10)
                .padding(.bottom, 8)

            EngravedGroove()
                .padding(.horizontal, inset)

            ViewThatFits(in: .horizontal) {
                WideLayout(viewModel: viewModel)
                CompactLayout(viewModel: viewModel)
            }
            .padding(.horizontal, inset)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ModelPlate(text: "MODEL EC-63  ·  PARALLEL PRESENCE  ·  \(Self.versionString)")
                .padding(.horizontal, inset)
                .padding(.bottom, PanelMetrics.footerHeight + 6)
        }
    }

    private static let versionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }()
}

// MARK: - Layouts

private struct WideLayout: View {
    let viewModel: EditorViewModel

    var body: some View {
        // fixedSize resolves the row to the Excite plate's height and the
        // side plates stretch to it — modules cut to one height, as in a rack.
        HStack(alignment: .top, spacing: 14) {
            NaturalChannel(viewModel: viewModel).frame(width: 144)
            ExciteChannel(viewModel: viewModel)
            OutputSection(viewModel: viewModel).frame(width: 144)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 740)
    }
}

private struct CompactLayout: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                NaturalChannel(viewModel: viewModel)
                OutputSection(viewModel: viewModel)
            }
            .fixedSize(horizontal: false, vertical: true)
            ExciteChannel(viewModel: viewModel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Header

private struct EditorHeader: View {
    let viewModel: EditorViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            FinishSelector(theme: GearTheme.current)
                .frame(width: 26, height: 26)
            Wordmark()
            Spacer(minLength: 12)
            HeaderMeters(viewModel: viewModel)
            PresetMenu(viewModel: viewModel)
        }
    }
}

/// Its own view so the per-frame meter updates re-render only the ladder.
private struct HeaderMeters: View {
    let viewModel: EditorViewModel

    var body: some View {
        LevelLadder(input: viewModel.inputLevel, output: viewModel.outputLevel)
    }
}

private struct Wordmark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Exciting Compressor")
                .font(.custom("Georgia-BoldItalic", size: 18))
                .foregroundStyle(GearTheme.textLight)
                .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 1.5)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("PARALLEL PRESENCE · AFTER LAWRENCE HORN · MOTOWN 1963")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(GearTheme.textLight.opacity(0.88))
                .shadow(color: .black.opacity(0.75), radius: 0, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The preset selector, behind the same smoked-glass window as the readouts.
private struct PresetMenu: View {
    let viewModel: EditorViewModel

    var body: some View {
        Menu {
            ForEach(viewModel.presets, id: \.number) { preset in
                Button(preset.name) { viewModel.selectPreset(preset) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.presetName ?? "Presets")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GearTheme.ledText)
                    .shadow(color: GearTheme.ledText.opacity(0.7), radius: 3)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(GearTheme.ledText.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 160, alignment: .leading)
            .background(LedWindow(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Preset")
        .accessibilityValue(viewModel.presetName ?? "None")
    }
}

// MARK: - Channels

private struct NaturalChannel: View {
    let viewModel: EditorViewModel

    var body: some View {
        ChannelPanel(title: "Natural", subtitle: "Dry, full dynamics",
                     isLit: viewModel.isNaturalAudible) {
            VStack {
                Spacer(minLength: 0)
                ParameterKnob(spec: ParameterCatalog.naturalLevel, viewModel: viewModel, diameter: 76)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ExciteChannel: View {
    let viewModel: EditorViewModel

    var body: some View {
        ChannelPanel(title: "Excite", subtitle: "Compressed hard, EQ'd bright, tucked under",
                     isLit: viewModel.isExciteAudible) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    processing
                    EngravedGroove(axis: .vertical)
                    blend.frame(maxHeight: .infinity)
                }
                VStack(spacing: 14) {
                    processing
                    EngravedGroove()
                    blend
                }
            }
        }
    }

    private var processing: some View {
        VStack(spacing: 12) {
            CompressorSection(viewModel: viewModel)
            EQSection(viewModel: viewModel)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var blend: some View {
        VStack {
            Spacer(minLength: 0)
            ParameterKnob(spec: ParameterCatalog.exciteLevel, viewModel: viewModel, diameter: 76)
            Spacer(minLength: 0)
        }
    }
}

private struct CompressorSection: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 8) {
            SectionLabel(text: "Compressor")
            HStack(spacing: 10) {
                ParameterKnob(spec: ParameterCatalog.threshold, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.ratio, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.attack, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.release, viewModel: viewModel)
            }
            GainReductionMeter(reductionDB: viewModel.gainReductionDB)
        }
    }
}

private struct EQSection: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Shape rides in the label row, so the knob row keeps four slots
            // lined up under the compressor's.
            HStack(spacing: 8) {
                SectionLabel(text: "Presence EQ")
                ShapeSelector(spec: ParameterCatalog.eqShape, viewModel: viewModel)
            }
            HStack(alignment: .top, spacing: 10) {
                ParameterKnob(spec: ParameterCatalog.eqFrequency, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.eqGain, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.eqQ, viewModel: viewModel)
                ParameterKnob(spec: ParameterCatalog.warmth, viewModel: viewModel)
            }
        }
    }
}

private struct OutputSection: View {
    let viewModel: EditorViewModel

    var body: some View {
        ChannelPanel(title: "Output", subtitle: "Master") {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                ParameterKnob(spec: ParameterCatalog.outputLevel, viewModel: viewModel, diameter: 60)
                VStack(spacing: 10) {
                    SoloButton(spec: ParameterCatalog.exciteListen, viewModel: viewModel)
                    SoloButton(spec: ParameterCatalog.warmthListen, viewModel: viewModel)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Discrete controls

/// Bell/Shelf as a pair of lamp tabs — a two-position selector, one lamp lit.
private struct ShapeSelector: View {
    let spec: ParameterSpec
    let viewModel: EditorViewModel

    var body: some View {
        let selected = Int(viewModel.value(for: spec).rounded())
        HStack(spacing: 6) {
            ForEach(Array((spec.valueStrings ?? []).enumerated()), id: \.offset) { index, label in
                LampTab(title: label.uppercased(), isOn: index == selected) {
                    viewModel.select(index, for: spec)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spec.name)
    }
}

/// A monitoring solo — Excite Only or Warmth Only — as an illuminated push
/// button that lights while soloed, labelled with the parameter's short name.
private struct SoloButton: View {
    let spec: ParameterSpec
    let viewModel: EditorViewModel

    @State private var taps = 0

    var body: some View {
        let isOn = viewModel.isOn(spec)
        Button {
            viewModel.toggleSolo(spec)
            taps += 1
        } label: {
            Text(spec.shortName.uppercased())
        }
        .buttonStyle(IlluminatedButtonStyle(isOn: isOn, lampColor: GearTheme.lampRed,
                                            theme: GearTheme.current))
        .frame(width: 104, height: 28)
        .contentShape(Rectangle())
        .accessibilityLabel(spec.name)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }
}
