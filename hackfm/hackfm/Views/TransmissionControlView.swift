//
//  TransmissionControlView.swift
//  HackFM
//
//  Start/Stop transmission controls
//

import SwiftUI

struct TransmissionControlView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Start button
            Button(action: { viewModel.startTransmission() }) {
                Label("Start", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStart)

            // Stop button
            Button(action: { viewModel.stopTransmission() }) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canStop)
        }
    }
}
