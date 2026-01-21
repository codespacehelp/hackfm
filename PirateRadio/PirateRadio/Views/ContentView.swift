//
//  ContentView.swift
//  PirateRadio
//
//  Main application view
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TransmitterViewModel()

    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerView

            // File selection
            FileSelectionView(viewModel: viewModel)

            // Frequency control
            FrequencyControlView(viewModel: viewModel)

            // Progress display
            ProgressDisplayView(viewModel: viewModel)

            // Transmission controls
            TransmissionControlView(viewModel: viewModel)

            // Status bar
            statusBar
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.connectDevice()
        }
    }

    private var headerView: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title)
                    .foregroundColor(.accentColor)

                Text("Pirate Radio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Text("FM Transmitter")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var statusBar: some View {
        HStack {
            // Connection status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(viewModel.state.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Reconnect button if disconnected
            if case .idle = viewModel.state {
                Button("Connect") {
                    viewModel.connectDevice()
                }
                .font(.caption)
                .buttonStyle(.link)
            } else if case .error = viewModel.state {
                Button("Retry") {
                    viewModel.reconnectDevice()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected:
            return .green
        case .transmitting:
            return .red
        case .loading, .modulating, .connecting, .stopping:
            return .orange
        case .error:
            return .red
        case .idle:
            return .gray
        }
    }
}

#Preview {
    ContentView()
}
