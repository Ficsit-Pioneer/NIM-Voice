import SwiftUI

/// Color palette for a given voice state.
private struct OrbPalette {
    let core: Color
    let glow: Color
    let accents: [Color]

    static func palette(for state: VoiceState, muted: Bool) -> OrbPalette {
        if muted {
            return OrbPalette(core: .gray, glow: .gray.opacity(0.5),
                              accents: [.gray.opacity(0.6), .secondary])
        }
        switch state {
        case .listening:
            return OrbPalette(core: Color(red: 0.46, green: 0.73, blue: 0.0),   // NVIDIA green
                              glow: Color(red: 0.46, green: 0.73, blue: 0.0),
                              accents: [.green, .teal, Color(red: 0.6, green: 0.9, blue: 0.3)])
        case .thinking:
            return OrbPalette(core: .indigo, glow: .purple,
                              accents: [.indigo, .blue, .purple])
        case .speaking:
            return OrbPalette(core: .teal, glow: .cyan,
                              accents: [.cyan, .teal, .mint])
        case .error:
            return OrbPalette(core: .orange, glow: .red,
                              accents: [.orange, .red, .pink])
        case .idle:
            return OrbPalette(core: .gray, glow: .secondary,
                              accents: [.gray, .secondary, .gray.opacity(0.7)])
        }
    }
}

/// The animated, glowing focal orb. Reacts to `state` and `level` (0...1):
/// pulses with mic input while listening, shimmers/rotates while thinking, and
/// undulates with speech while speaking. Driven by `TimelineView(.animation)`
/// so motion is frame-synced and continuous.
struct OrbView: View {
    let state: VoiceState
    let level: Float
    var muted: Bool = false

    var body: some View {
        let palette = OrbPalette.palette(for: state, muted: muted)

        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathing = 1.0 + 0.04 * sin(t * 1.4)
            let reactive = 1.0 + Double(min(max(level, 0), 1)) * 0.4
            let scale = (state == .idle || muted) ? 0.92 : breathing * reactive
            let rotation = rotationAngle(at: t)

            ZStack {
                // Outer soft glow
                Circle()
                    .fill(palette.glow)
                    .blur(radius: 60)
                    .opacity(glowOpacity)
                    .frame(width: 300, height: 300)

                // Rotating organic accent blobs
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * blobSpeed + Double(i) * (.pi * 2 / 3)
                    Circle()
                        .fill(palette.accents[i % palette.accents.count])
                        .frame(width: 150, height: 150)
                        .offset(
                            x: cos(phase) * 42 * blobSpread,
                            y: sin(phase * 1.1) * 42 * blobSpread
                        )
                        .blur(radius: 28)
                        .blendMode(.screen)
                }

                // Glassy core
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.95), palette.core, palette.core.opacity(0.7)],
                            center: .init(x: 0.38, y: 0.34),
                            startRadius: 4,
                            endRadius: 130
                        )
                    )
                    .frame(width: 200, height: 200)
                    .overlay(
                        Circle().stroke(.white.opacity(0.25), lineWidth: 1).blur(radius: 0.5)
                    )

                // Thinking shimmer ring
                if state == .thinking {
                    Circle()
                        .trim(from: 0, to: 0.65)
                        .stroke(
                            AngularGradient(colors: [.white.opacity(0.0), .white.opacity(0.8), .white.opacity(0.0)],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 230, height: 230)
                        .rotationEffect(.radians(rotation))
                }
            }
            .scaleEffect(scale)
            .rotationEffect(state == .speaking ? .radians(sin(t * 2) * 0.05) : .zero)
            .opacity(muted ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: level)
        }
        .frame(width: 300, height: 300)
        .accessibilityHidden(true)
    }

    private var glowOpacity: Double {
        switch state {
        case .idle: return 0.25
        case .thinking: return 0.55
        case .speaking: return 0.65
        case .error: return 0.5
        case .listening: return 0.4 + Double(min(level, 1)) * 0.4
        }
    }

    private var blobSpeed: Double {
        switch state {
        case .thinking: return 0.9
        case .speaking: return 1.4
        case .listening: return 0.6
        default: return 0.25
        }
    }

    private var blobSpread: Double {
        switch state {
        case .speaking: return 1.0 + Double(level) * 0.4
        case .listening: return 0.8 + Double(level) * 0.6
        default: return 0.7
        }
    }

    private func rotationAngle(at t: TimeInterval) -> Double {
        t * 1.6
    }
}

/// Full-screen gradient backdrop whose tint subtly follows the voice state.
/// Adapts to light/dark mode while keeping the immersive, dim feel.
struct AnimatedBackground: View {
    let state: VoiceState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            RadialGradient(
                colors: gradientColors,
                center: UnitPoint(x: 0.5 + 0.08 * cos(t * 0.2),
                                  y: 0.38 + 0.06 * sin(t * 0.15)),
                startRadius: 5,
                endRadius: 650
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2), value: state)
        }
    }

    private var gradientColors: [Color] {
        let tint = OrbPaletteBridge.tint(for: state)
        if colorScheme == .dark {
            return [tint.opacity(0.35), Color.black.opacity(0.92), Color.black]
        } else {
            return [tint.opacity(0.18), Color(.systemGray6), Color(.systemBackground)]
        }
    }
}

/// Small bridge so the background can reuse the orb's state tint.
private enum OrbPaletteBridge {
    static func tint(for state: VoiceState) -> Color {
        switch state {
        case .listening: return Color(red: 0.46, green: 0.73, blue: 0.0)
        case .thinking: return .indigo
        case .speaking: return .teal
        case .error: return .orange
        case .idle: return .gray
        }
    }
}
