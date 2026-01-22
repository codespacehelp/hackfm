//
//  HackRFError.swift
//  HackFM
//
//  Error types for HackRF operations
//

import Foundation

enum HackRFError: Error, LocalizedError {
    case initializationFailed(code: Int32)
    case deviceNotFound
    case openFailed(code: Int32)
    case alreadyOpen
    case notOpen
    case configurationFailed(parameter: String, code: Int32)
    case transmissionFailed(code: Int32)
    case transmissionInProgress
    case noDataToTransmit
    case deviceDisconnected

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let code):
            return "Failed to initialize HackRF library (error code: \(code))"
        case .deviceNotFound:
            return "No HackRF device found. Please connect a HackRF One."
        case .openFailed(let code):
            return "Failed to open HackRF device (error code: \(code))"
        case .alreadyOpen:
            return "HackRF device is already open"
        case .notOpen:
            return "HackRF device is not open"
        case .configurationFailed(let parameter, let code):
            return "Failed to configure \(parameter) (error code: \(code))"
        case .transmissionFailed(let code):
            return "Transmission failed (error code: \(code))"
        case .transmissionInProgress:
            return "A transmission is already in progress"
        case .noDataToTransmit:
            return "No IQ data available for transmission"
        case .deviceDisconnected:
            return "HackRF device was disconnected"
        }
    }
}
