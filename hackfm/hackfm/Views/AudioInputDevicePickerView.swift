//
//  AudioInputDevicePickerView.swift
//  HackFM
//
//  Dropdown picker for selecting audio input devices
//

import SwiftUI

struct AudioInputDevicePickerView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        HStack {
            Picker("Input Device", selection: deviceBinding) {
                if viewModel.availableInputDevices.isEmpty {
                    Text("No devices found")
                        .tag(nil as AudioInputDevice?)
                } else {
                    ForEach(viewModel.availableInputDevices) { device in
                        HStack {
                            Text(device.displayName)
                            if device.isDefault {
                                Text("(Default)")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(device as AudioInputDevice?)
                    }
                }
            }
            .labelsHidden()
            .disabled(viewModel.state.isBusy || viewModel.availableInputDevices.isEmpty)

            Button(action: {
                viewModel.refreshInputDevices()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh device list")
            .disabled(viewModel.state.isBusy)
        }
    }

    private var deviceBinding: Binding<AudioInputDevice?> {
        Binding(
            get: { viewModel.selectedInputDevice },
            set: { device in
                if let device = device {
                    viewModel.selectInputDevice(device)
                }
            }
        )
    }
}

#Preview {
    AudioInputDevicePickerView(viewModel: TransmitterViewModel())
        .padding()
        .frame(width: 400)
}
