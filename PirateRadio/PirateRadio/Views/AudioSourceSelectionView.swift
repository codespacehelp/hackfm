//
//  AudioSourceSelectionView.swift
//  PirateRadio
//
//  Tab/segment control for selecting between file and live input modes
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioSourceSelectionView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Mode selector
            Picker("Audio Source", selection: $viewModel.transmissionMode) {
                Label("File", systemImage: "doc.fill")
                    .tag(TransmissionMode.file)
                Label("Live Input", systemImage: "mic.fill")
                    .tag(TransmissionMode.liveInput)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.state.isBusy)

            // Mode-specific content
            switch viewModel.transmissionMode {
            case .file:
                FileSourceView(viewModel: viewModel)
            case .liveInput:
                LiveInputSourceView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - File Source View

private struct FileSourceView: View {
    @ObservedObject var viewModel: TransmitterViewModel
    @State private var isDragging = false

    private let supportedTypes: [UTType] = [.wav, .mp3, .aiff, .audio]

    var body: some View {
        VStack(spacing: 12) {
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
                    )

                VStack(spacing: 8) {
                    if viewModel.selectedFileURL != nil {
                        // File selected state
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(.accentColor)

                        Text(viewModel.fileName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !viewModel.audioFormat.isEmpty {
                            Text("\(viewModel.audioFormat) - \(viewModel.durationString)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if viewModel.useStreamingMode {
                            Text("Streaming mode (low memory)")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else if !viewModel.estimatedMemory.isEmpty {
                            Text("Memory: ~\(viewModel.estimatedMemory)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Button("Clear") {
                            viewModel.clearFile()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else {
                        // Empty state
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)

                        Text("Drop audio file here")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("WAV, MP3, or AIFF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 140)
            .onDrop(of: supportedTypes, isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
            }

            // Browse button
            Button(action: openFilePicker) {
                Label("Browse Files", systemImage: "folder")
            }
            .disabled(viewModel.state.isBusy)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        for type in supportedTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            viewModel.selectFile(url)
                        }
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            viewModel.selectFile(url)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = supportedTypes

        panel.begin { response in
            if response == .OK, let url = panel.url {
                viewModel.selectFile(url)
            }
        }
    }
}

// MARK: - Live Input Source View

private struct LiveInputSourceView: View {
    @ObservedObject var viewModel: TransmitterViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Device info area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        viewModel.selectedInputDevice != nil ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.clear)
                    )

                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(viewModel.selectedInputDevice != nil ? .accentColor : .secondary)

                    if let device = viewModel.selectedInputDevice {
                        Text(device.displayName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("\(device.inputChannels) ch @ \(Int(device.currentSampleRate))Hz")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Audio level meter
                        AudioLevelMeterView(level: viewModel.audioInputLevel)
                            .frame(height: 8)
                            .padding(.horizontal, 40)
                    } else {
                        Text("No input device selected")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Select a device below")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(height: 140)

            // Device picker
            AudioInputDevicePickerView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refreshInputDevices()
        }
    }
}

#Preview {
    AudioSourceSelectionView(viewModel: TransmitterViewModel())
        .padding()
        .frame(width: 400)
}
