# Exciting Compressor (AUv3)

An AUv3 effect for iOS and macOS. It recreates the Motown "Exciting Compressor" that Lawrence Horn
devised in 1963, as Bob Dennis described it in *Motown Engineering Series No. 2*.

```
input ──┬───────────────────────────────────── × Natural ──┐
        │                                                  ├─(+)── × Output ──▶
        └─▶ compressor (hard) ─┬▶ presence EQ (big) ─(+)─ × Excite ──┘
                               └▶ warmth harmonics ─┘
```

- **Natural path:** the dry vocal at full level. It keeps the vocal's natural dynamics.
- **Excite path:** compressed "the h**l out of it", given "a ton" of high-frequency EQ, then
  "brought up just enough to add excitement and presence". Auto makeup gain restores a −18 dBFS
  signal to unity, so the Excite level acts as a true blend control.
- **Warmth:** makes the vocal rounder. It adds low-order harmonics (mostly the 2nd) to the excite
  path. They are generated from the body of the voice, so they don't add fizz or sibilance.
- **Excite Only / Warmth Only:** monitoring solos, both before the Blend control. Excite Only plays
  the whole excite path, so you can set the compressor and EQ. Warmth Only plays just the harmonics
  that Warmth adds.

Reverb is left out on purpose. The article puts it on the natural channel, so add it in your DAW.

## Controls

| Control | Parameter | Range | Default |
|---|---|---|---|
| **Natural › Level** | Natural Level | −60 dB (mute) to +6 dB | 0 dB |
| **Excite › Threshold** | Excite Threshold | −60 to 0 dB | −35 dB |
| **Excite › Ratio** | Excite Ratio | 1:1 to 30:1 | 20:1 |
| **Excite › Attack** | Excite Attack | 0.1 to 100 ms | 2 ms |
| **Excite › Release** | Excite Release | 10 to 2000 ms | 150 ms |
| **Excite › Freq** | Excite EQ Frequency | 400 Hz to 16 kHz | 6.5 kHz |
| **Excite › Boost** | Excite EQ Boost | 0 to +24 dB | +15 dB |
| **Excite › Q** | Excite EQ Q | 0.3 to 4 | 0.7 |
| **Excite › Bell / Shelf** | Excite EQ Shape | Bell or high shelf | Bell |
| **Excite › Warmth** | Excite Warmth | 0 to 100 % | 0 % (off) |
| **Excite › Blend** | Excite Level | −60 dB (mute) to +6 dB | −12 dB |
| **Output › Output** | Output Level | −24 to +12 dB | 0 dB |
| **Output › Excite Only** | Excite Listen | Off or On | Off |
| **Output › Warmth Only** | Warmth Listen | Off or On | Off |

The compressor has a 6 dB soft knee and a stereo-linked detector, so the stereo image doesn't
wander. Ratio, Attack, Release, Freq and Q use logarithmic knobs. Level, EQ and Warmth changes are
smoothed, so automating them doesn't click.

### Warmth

Warmth takes the compressed signal, keeps only the body of the voice (90–500 Hz) and generates its
2nd harmonic, one octave up. It keeps only what lands between 90 Hz and 2 kHz and mixes that into
the excite path alongside the presence EQ. Harmonics an octave above the note blend in as thickness
rather than distortion. They also help a voice sound full on small speakers that can't reproduce
its fundamentals.

- **Consistent amount:** Warmth works on the compressed signal, so it sounds the same whether the
  singer is quiet or loud.
- **Range:** at 100 % the harmonics are as loud as the band they come from. Blend then sets how
  much of the whole excite path reaches the mix.
- **No added latency:** everything Warmth generates stays below 2 kHz, far below where aliasing
  starts. It needs no oversampling, so it doesn't shift the excite path against the natural path.

**Setting it:** Warmth is meant to blend in, so in the full mix it's easier to feel than to hear.

1. Turn on **Warmth Only** to hear just the harmonics at the current Warmth setting. It is silent at
   0 %. This shows you what Warmth adds and whether the recording has enough low-mid content to
   work with.
2. Switch to **Excite Only** and raise Warmth until the voice sounds thicker but not fuzzy, often
   30–60 %. Setting Boost to 0 dB for a moment makes the change easier to hear.
3. Switch both off and set Blend.

Warmth adds density but can't create low end the recording doesn't have. If the track was already
high-passed above about 150 Hz, or the recording is thin, Warmth has little to work with. Combine it
with a low-mid EQ boost in your DAW.

## Presets

The presets follow the article's frequency guidance: vocals 5–8 kHz, guitars 3–5 kHz and bass
800 Hz–1.5 kHz. Anything a preset doesn't list stays at its default.

| # | Preset | Changes from the defaults |
|---|---|---|
| 0 | Motown Lead Vocal | none: the article's vocal setup |
| 1 | Vocal Air | 8 kHz high shelf, +12 dB, Blend −14 dB |
| 2 | Backing Vocals | Threshold −30 dB, 12:1, 5.5 kHz +12 dB, Blend −9 dB |
| 3 | Guitar Bite | Attack 5 ms, Release 120 ms, 4 kHz +12 dB, Q 0.9 |
| 4 | Bass Growl | Attack 10 ms, Release 200 ms, 1.1 kHz +12 dB, Q 1.0, Blend −10 dB |
| 5 | Subtle Presence | Threshold −30 dB, 8:1, 6 kHz +10 dB, Blend −20 dB |
| 6 | Round Lead Vocal | Warmth 45 %, Boost +12 dB, Blend −10 dB |

Loading a preset always switches Excite Only and Warmth Only off. User presets work in hosts that support them.

## Editor

The editor looks like a piece of rack hardware. Each channel sits on its own plate, and the layout
stacks into a single column on narrow screens.

- **Knobs:** drag up or right to increase, down or left to decrease. Double-click (double-tap on
  iOS) resets to the default. VoiceOver can adjust every knob.
- **Channel lamps:** a lamp shows whether that path reaches the output. Natural goes dark when its
  level is at the bottom or a solo button is on. Excite goes dark when Blend is at the bottom and
  neither solo button is on.
- **Solo buttons:** Excite Only and Warmth Only are illuminated push buttons that light red while
  on. They work like solo buttons on a console: switching one on switches the other off. If a
  host's automation turns both on, Warmth Only wins.
- **Gain Reduction:** a bar under the compressor knobs that fills from right to left, scaled
  0–30 dB. The scale is stretched so the first few dB take up more of the bar than the last few.
- **IN / OUT meters:** LED ladders in the header showing peak level, ten segments over
  −48 to 0 dBFS. The top two segments are red. Each row shows the louder side.
- **Panel finish:** the small rotary switch left of the name cycles through Tweed, Field Green and
  Slate. It only changes the editor's colours, and the app and the plug-in each remember their own
  choice.

## Build

```sh
xcodegen generate                 # project.yml is the source of truth
open ExcitingCompressor.xcodeproj # run ExcitingCompressor_macOS or ExcitingCompressor_iOS
```

Run the container app once to register the extension. It also includes a test rig: open an audio
file, press Play, and adjust the plugin. Validate on macOS with:

```sh
auval -strict -v aufx ExCp Grov
```

If a copy is already installed in `/Applications`, macOS may keep loading that one instead of your
build. Remove it, or reinstall from a fresh package, to test your changes in a host.

### App icon

```sh
swift icon/make-icon.swift        # -> App/Assets.xcassets/AppIcon.appiconset/
```

`make-icon.swift` draws the same layout as the jj-breeze, jj-midnight and jj-moon icons: panel,
corner screws, meter arc, serif wordmark and jewel lamps. This one uses the Tweed sand lacquer, so
the four icons look like one family. It writes the opaque 1024 px iOS icon and the macOS sizes,
which have their own rounded body and shadow. The colours are the hex values from
`GearPalette.tweed`, so if that palette changes, update the script to match.

## Installer (macOS)

```sh
scripts/make-installer.sh                                    # signed .pkg → build/installer/
NOTARY_PROFILE=exciting-notary scripts/make-installer.sh     # + notarize & staple
```

The script builds a universal Release archive, signs it with Developer ID Application, and wraps it
in a `.pkg` signed with Developer ID Installer. The package installs to `/Applications` and its
postinstall step registers the AU. Set up notarization once with
`xcrun notarytool store-credentials exciting-notary --apple-id <id> --team-id C9LBGZNZ6P`.

Gatekeeper warns about packages that aren't notarized when they're opened on other Macs. Raise
`MARKETING_VERSION` in `project.yml` before building a release, so each package has its own version.

## Layout

| Path | Layer |
|---|---|
| `Extension/DSP/` | Real-time C++ kernel (`ExcitingCompressorDSP.hpp`, `Compressor.hpp`, `Biquad.hpp`, `Warmth.hpp`) plus an ObjC++ adapter that provides the render block |
| `Extension/AudioUnit/` | `AUAudioUnit` subclass, parameter catalog, and view controller (`AUAudioUnitFactory`) |
| `Extension/Domain/` | Factory presets |
| `Extension/UI/` | SwiftUI editor with an `@Observable` `EditorViewModel` bound to the parameter tree |
| `Extension/UI/Components/` | Editor parts: panel finishes (`GearTheme`), procedurally drawn hardware, knobs, switches and meters |
| `App/` | Container app and AVAudioEngine test host |
| `Extension/Support/ECParameterAddress.h` | Parameter addresses shared by C++ and Swift |

## Developer notes

- **Adding a parameter:** give it the next free address in `ECParameterAddress.h` and never
  renumber existing ones, because hosts store automation and saved state by address. Raise
  `EC_PARAMETER_COUNT`, set its default in the kernel's constructor, and add a `ParameterSpec` to
  `ParameterCatalog.all` and to the parameter tree. Sessions saved before the parameter existed load
  with its default value.
- **Adding a preset:** append it with the next number. Hosts remember factory presets by number, so
  inserting one would change what existing sessions load.
- **Metering:** the kernel holds the highest input and output peak per side until something reads
  it. `ExcitingCompressorAudioUnit.takePeakLevels()` returns those peaks and clears them, so a
  transient between two reads is never lost. Because reading clears them, only one reader should
  poll; two would split the peaks between them. The editor polls about 30 times a second and
  applies the meter fall-off itself. Gain reduction is available as `gainReductionDB`.
- **Real-time safety:** nothing on the render path allocates, locks or calls into Objective-C. The
  meters use lock-free atomics.
