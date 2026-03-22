import SwiftUI

struct SplashScreenView: View {
    // Animation states
    @State private var phase: Int = 0
    @State private var logoScale: CGFloat = 0.1
    @State private var logoRotation: Double = -180
    @State private var logoOpacity: Double = 0
    @State private var ringScale1: CGFloat = 0.5
    @State private var ringScale2: CGFloat = 0.5
    @State private var ringScale3: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var ringRotation1: Double = 0
    @State private var ringRotation2: Double = 0
    @State private var ringRotation3: Double = 0
    @State private var glowRadius: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var titleOffset: CGFloat = 60
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var chartProgress: CGFloat = 0
    @State private var particleOpacity: Double = 0
    @State private var shockwaveScale: CGFloat = 0.3
    @State private var shockwaveOpacity: Double = 0
    @State private var bgHue: Double = 0.58
    @State private var scanLineOffset: CGFloat = -1
    @State private var pulseScale: CGFloat = 1.0
    @State private var trailOpacity: Double = 0
    @State private var planeOffset: CGFloat = 0
    @State private var planeRotation: Double = -15

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Animated background
                animatedBackground(size: geo.size)

                // Scan line effect
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(height: 120)
                    .offset(y: scanLineOffset * geo.size.height)
                    .ignoresSafeArea()

                // Floating particles
                particleField(size: geo.size)

                // Center content
                VStack(spacing: 0) {
                    Spacer()

                    // Logo assembly
                    ZStack {
                        // Shockwave burst
                        Circle()
                            .stroke(Color.cyan.opacity(0.4), lineWidth: 2)
                            .frame(width: 200, height: 200)
                            .scaleEffect(shockwaveScale)
                            .opacity(shockwaveOpacity)

                        // Outer glow pulse
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.1), .clear],
                                center: .center, startRadius: 30, endRadius: 120
                            ))
                            .frame(width: 240, height: 240)
                            .scaleEffect(pulseScale)
                            .opacity(glowOpacity)

                        // Orbital rings
                        orbitalRing(size: 160, dash: [6, 8], rotation: ringRotation1, scale: ringScale1)
                        orbitalRing(size: 130, dash: [4, 12], rotation: ringRotation2, scale: ringScale2)
                        orbitalRing(size: 190, dash: [3, 15], rotation: ringRotation3, scale: ringScale3)

                        // Main icon
                        ZStack {
                            // Glass card
                            RoundedRectangle(cornerRadius: 28)
                                .fill(.ultraThinMaterial)
                                .frame(width: 110, height: 110)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(LinearGradient(
                                            colors: [Color.cyan.opacity(0.5), Color.blue.opacity(0.7)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(LinearGradient(
                                            colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ), lineWidth: 1.5)
                                )
                                .shadow(color: .cyan.opacity(0.5), radius: glowRadius, x: 0, y: 0)

                            // Paper airplane with trail
                            ZStack {
                                // Trail
                                SplashChartLine(progress: chartProgress)
                                    .stroke(
                                        LinearGradient(colors: [.white.opacity(0.1), .white.opacity(0.5)],
                                                       startPoint: .leading, endPoint: .trailing),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                    )
                                    .frame(width: 50, height: 25)
                                    .offset(x: -8, y: 8)
                                    .opacity(trailOpacity)

                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .white.opacity(0.6), radius: 8)
                                    .rotationEffect(.degrees(planeRotation))
                                    .offset(x: planeOffset)
                            }
                        }
                    }
                    .scaleEffect(logoScale)
                    .rotationEffect(.degrees(logoRotation))
                    .opacity(logoOpacity)

                    Spacer().frame(height: 36)

                    // Title
                    VStack(spacing: 10) {
                        Text("PaperPilot")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color.cyan.opacity(0.85), .white],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .shadow(color: .cyan.opacity(0.4), radius: 12)

                        Text("AUTOMATED PAPER TRADING")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .tracking(4)
                            .foregroundStyle(.white.opacity(0.5))
                            .opacity(subtitleOpacity)
                    }
                    .offset(y: titleOffset)
                    .opacity(titleOpacity)

                    Spacer()

                    // Loading bar
                    loadingBar
                        .padding(.bottom, 70)
                        .opacity(subtitleOpacity)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { runAnimation() }
    }

    // MARK: - Animated Background
    private func animatedBackground(size: CGSize) -> some View {
        ZStack {
            // Deep gradient
            LinearGradient(
                colors: [
                    Color(hue: bgHue, saturation: 0.8, brightness: 0.08),
                    Color(hue: bgHue + 0.05, saturation: 0.6, brightness: 0.14),
                    Color(hue: bgHue - 0.02, saturation: 0.7, brightness: 0.06)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            // Grid overlay
            Canvas { context, canvasSize in
                let spacing: CGFloat = 50
                let color = Color.white.opacity(0.025)
                for x in stride(from: 0, to: canvasSize.width, by: spacing) {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    context.stroke(p, with: .color(color), lineWidth: 0.5)
                }
                for y in stride(from: 0, to: canvasSize.height, by: spacing) {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    context.stroke(p, with: .color(color), lineWidth: 0.5)
                }
            }

            // Radial glow behind logo
            RadialGradient(
                colors: [Color.cyan.opacity(0.08), .clear],
                center: .center, startRadius: 50, endRadius: 350
            )
        }
    }

    // MARK: - Orbital Ring
    private func orbitalRing(size: CGFloat, dash: [CGFloat], rotation: Double, scale: CGFloat) -> some View {
        Circle()
            .stroke(
                LinearGradient(colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.1)],
                               startPoint: .top, endPoint: .bottom),
                style: StrokeStyle(lineWidth: 1.5, dash: dash)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(ringOpacity)
    }

    // MARK: - Particle Field
    private func particleField(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let count = 40
            for i in 0..<count {
                let seed = Double(i)
                let x = (sin(seed * 1.3 + ringRotation1 * 0.01) * 0.5 + 0.5) * canvasSize.width
                let y = (cos(seed * 0.9 + ringRotation2 * 0.008) * 0.5 + 0.5) * canvasSize.height
                let r = 1.0 + sin(seed * 2.1) * 1.0
                let alpha = 0.15 + sin(seed * 3.0 + ringRotation1 * 0.02) * 0.15
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.cyan.opacity(alpha)))
            }
        }
        .opacity(particleOpacity)
        .allowsHitTesting(false)
    }

    // MARK: - Loading Bar
    private var loadingBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.cyan, Color.blue],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * chartProgress, height: 4)
                        .shadow(color: .cyan.opacity(0.6), radius: 6)
                }
            }
            .frame(height: 4)
            .frame(maxWidth: 200)

            Text("Initializing...")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Animation Sequence
    private func runAnimation() {
        // Continuous background hue shift
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
            bgHue = 0.65
        }

        // Scan line
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            scanLineOffset = 1
        }

        // Phase 1: Logo bursts in with rotation (0.0s)
        withAnimation(.spring(response: 0.9, dampingFraction: 0.55)) {
            logoScale = 1.0
            logoRotation = 0
            logoOpacity = 1.0
        }

        // Phase 2: Shockwave (0.3s)
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            shockwaveScale = 3.0
            shockwaveOpacity = 0.6
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
            shockwaveOpacity = 0
        }

        // Phase 3: Glow ignites (0.4s)
        withAnimation(.easeIn(duration: 0.6).delay(0.4)) {
            glowOpacity = 1.0
            glowRadius = 25
        }

        // Phase 4: Rings expand + start spinning (0.5s)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.5)) {
            ringScale1 = 1.0
            ringScale2 = 1.0
            ringScale3 = 1.0
            ringOpacity = 1.0
        }
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false).delay(0.5)) {
            ringRotation1 = 360
        }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false).delay(0.5)) {
            ringRotation2 = -360
        }
        withAnimation(.linear(duration: 25).repeatForever(autoreverses: false).delay(0.5)) {
            ringRotation3 = 360
        }

        // Phase 5: Particles fade in (0.7s)
        withAnimation(.easeIn(duration: 0.8).delay(0.7)) {
            particleOpacity = 1.0
        }

        // Phase 6: Plane swoops + trail draws (0.8s)
        withAnimation(.easeOut(duration: 0.6).delay(0.8)) {
            planeOffset = 4
            planeRotation = -8
            trailOpacity = 1.0
        }
        withAnimation(.easeInOut(duration: 1.0).delay(0.8)) {
            chartProgress = 1.0
        }

        // Phase 7: Title slides up (1.0s)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.65).delay(1.0)) {
            titleOffset = 0
            titleOpacity = 1.0
        }

        // Phase 8: Subtitle + loading bar (1.4s)
        withAnimation(.easeIn(duration: 0.5).delay(1.4)) {
            subtitleOpacity = 1.0
        }

        // Phase 9: Pulse loop (1.6s)
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(1.6)) {
            pulseScale = 1.15
        }
    }
}

// MARK: - Chart Trail Shape
struct SplashChartLine: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.maxY * 0.8),
            CGPoint(x: rect.width * 0.2, y: rect.maxY * 0.45),
            CGPoint(x: rect.width * 0.4, y: rect.maxY * 0.6),
            CGPoint(x: rect.width * 0.6, y: rect.maxY * 0.25),
            CGPoint(x: rect.width * 0.8, y: rect.maxY * 0.35),
            CGPoint(x: rect.maxX, y: rect.minY * 0.1)
        ]
        guard progress > 0 else { return path }
        path.move(to: points[0])
        let total = Int(ceil(progress * CGFloat(points.count - 1)))
        for i in 1..<min(total + 1, points.count) {
            path.addLine(to: points[i])
        }
        return path
    }
}
