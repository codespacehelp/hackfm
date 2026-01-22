//
//  ProgressDisplayView.swift
//  HackFM
//
//  Progress bar and time display for transmission
//

import SwiftUI

struct ProgressDisplayView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    // Processing progress (darker shade)
                    if viewModel.processingProgress > 0 && viewModel.processingProgress < 1 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: geometry.size.width * viewModel.processingProgress)
                    }

                    // Transmission progress (accent color)
                    if viewModel.transmissionProgress > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * viewModel.transmissionProgress)
                    }
                }
            }
            .frame(height: 8)

            // Time display
            HStack {
                Text(viewModel.currentTimeString)
                    .font(.caption)
                    .monospacedDigit()

                Spacer()

                // Status indicator
                statusIndicator

                Spacer()

                Text(viewModel.durationString)
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch viewModel.state {
        case .transmitting:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("ON AIR")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }

        case .modulating, .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Processing")
                    .font(.caption)
            }

        default:
            EmptyView()
        }
    }
}
