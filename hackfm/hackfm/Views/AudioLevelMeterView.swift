//
//  AudioLevelMeterView.swift
//  HackFM
//
//  Visual feedback for audio input levels
//

import SwiftUI

struct AudioLevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelGradient)
                    .frame(width: levelWidth(in: geometry.size.width))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [.green, .yellow, .red]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func levelWidth(in totalWidth: CGFloat) -> CGFloat {
        // Apply logarithmic scaling for better visual response
        let clampedLevel = min(max(level, 0), 1)
        let scaledLevel = clampedLevel > 0 ? (log10(clampedLevel * 9 + 1)) : 0
        return totalWidth * CGFloat(scaledLevel)
    }
}

// MARK: - Stereo Level Meter

struct StereoLevelMeterView: View {
    let leftLevel: Float
    let rightLevel: Float

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("L")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                AudioLevelMeterView(level: leftLevel)
            }
            HStack(spacing: 4) {
                Text("R")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                AudioLevelMeterView(level: rightLevel)
            }
        }
    }
}

// MARK: - Animated Level Meter

struct AnimatedLevelMeterView: View {
    let level: Float
    @State private var peakLevel: Float = 0
    @State private var peakHoldTimer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelGradient)
                    .frame(width: levelWidth(for: level, in: geometry.size.width))
                    .animation(.easeOut(duration: 0.05), value: level)

                // Peak indicator
                if peakLevel > 0.01 {
                    Rectangle()
                        .fill(peakColor)
                        .frame(width: 2)
                        .offset(x: levelWidth(for: peakLevel, in: geometry.size.width) - 1)
                        .animation(.easeOut(duration: 0.1), value: peakLevel)
                }
            }
        }
        .onChange(of: level) { newValue in
            updatePeak(newValue)
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var peakColor: Color {
        if peakLevel > 0.9 {
            return .red
        } else if peakLevel > 0.7 {
            return .orange
        } else {
            return .green
        }
    }

    private func levelWidth(for level: Float, in totalWidth: CGFloat) -> CGFloat {
        let clampedLevel = min(max(level, 0), 1)
        let scaledLevel = clampedLevel > 0 ? (log10(clampedLevel * 9 + 1)) : 0
        return totalWidth * CGFloat(scaledLevel)
    }

    private func updatePeak(_ newLevel: Float) {
        if newLevel > peakLevel {
            peakLevel = newLevel

            // Reset peak hold timer
            peakHoldTimer?.invalidate()
            peakHoldTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                withAnimation(.easeOut(duration: 0.5)) {
                    peakLevel = 0
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AudioLevelMeterView(level: 0.5)
            .frame(height: 8)

        AudioLevelMeterView(level: 0.8)
            .frame(height: 8)

        StereoLevelMeterView(leftLevel: 0.6, rightLevel: 0.4)
            .frame(height: 20)

        AnimatedLevelMeterView(level: 0.7)
            .frame(height: 12)
    }
    .padding()
    .frame(width: 300)
}
