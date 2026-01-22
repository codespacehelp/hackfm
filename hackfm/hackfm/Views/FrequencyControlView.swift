//
//  FrequencyControlView.swift
//  HackFM
//
//  FM frequency selection control
//

import SwiftUI

struct FrequencyControlView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Frequency display
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", viewModel.frequencyMHz))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("MHz")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            // Slider with range labels
            VStack(spacing: 4) {
                Slider(
                    value: $viewModel.frequencyMHz,
                    in: TransmitterViewModel.minFrequencyMHz...TransmitterViewModel.maxFrequencyMHz,
                    step: TransmitterViewModel.frequencyStepMHz
                )
                .disabled(viewModel.state.isBusy)

                HStack {
                    Text("88")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("FM Band")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("108")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Fine-tune buttons
            HStack(spacing: 20) {
                Button(action: { viewModel.decrementFrequency() }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.frequencyMHz <= TransmitterViewModel.minFrequencyMHz || viewModel.state.isBusy)

                Text("-0.1 / +0.1 MHz")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: { viewModel.incrementFrequency() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.frequencyMHz >= TransmitterViewModel.maxFrequencyMHz || viewModel.state.isBusy)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
