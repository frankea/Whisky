//
//  AudioDeviceMonitor.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import CoreAudio
import Foundation
import os.log

/// Wraps CoreAudio's C API for audio device enumeration, property queries,
/// and change listeners.
///
/// Uses `@unchecked Sendable` because CoreAudio callbacks are dispatched
/// on `DispatchQueue.main` as specified in the listener registration.
public final class AudioDeviceMonitor: @unchecked Sendable {
    /// Callback type for device change notifications.
    public typealias DeviceChangeHandler = @Sendable (AudioDeviceChangeEvent) -> Void

    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "AudioDeviceMonitor"
    )

    /// The registered listener block, stored for removal.
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    /// The property address used for listener registration, stored for removal.
    private var listenerAddress: AudioObjectPropertyAddress?

    /// The external change handler provided via ``startListening(onChange:)``.
    private var onChange: DeviceChangeHandler?

    public init() {}

    deinit {
        stopListening()
    }

    // MARK: - Public API

    /// Queries the system default output device.
    ///
    /// - Returns: Device info for the default output device, or `nil` if unavailable.
    public func defaultOutputDevice() -> AudioDeviceInfo? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        guard status == noErr else {
            logger.error("Failed to query default output device: \(status)")
            return nil
        }

        return queryDeviceInfo(deviceID, isDefault: true)
    }

    /// Queries all output devices on the system.
    ///
    /// Filters to devices with at least one output channel.
    ///
    /// - Returns: An array of output device information.
    public func allOutputDevices() -> [AudioDeviceInfo] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        )

        guard status == noErr else {
            logger.error("Failed to query audio device list size: \(status)")
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceIDs
        )

        guard status == noErr else {
            logger.error("Failed to query audio device list: \(status)")
            return []
        }

        // Determine the default device ID for marking
        let defaultID = queryDefaultOutputDeviceID()

        return deviceIDs.compactMap { deviceID in
            queryDeviceInfo(deviceID, isDefault: deviceID == defaultID)
        }.filter { $0.outputChannelCount > 0 }
    }

    /// Registers for default output device change notifications.
    ///
    /// The change handler is called on the main queue when the system default
    /// output device changes.
    ///
    /// - Parameter onChange: A closure invoked with a change event each time
    ///   the default output device changes.
    public func startListening(onChange: @escaping DeviceChangeHandler) {
        // Remove any existing listener first
        stopListening()

        self.onChange = onChange

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let device = self.defaultOutputDevice()
            let event = AudioDeviceChangeEvent(
                timestamp: Date(),
                eventType: .defaultOutputChanged,
                deviceName: device?.name ?? "Unknown",
                transportType: device?.transportType ?? .unknown
            )
            self.onChange?(event)
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        if status == noErr {
            listenerBlock = block
            listenerAddress = address
        } else {
            logger.error("Failed to register audio device listener: \(status)")
        }
    }

    /// Removes the registered property change listener.
    public func stopListening() {
        guard let block = listenerBlock, var address = listenerAddress else { return }

        let status = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        if status != noErr {
            logger.warning("Failed to remove audio device listener: \(status)")
        }

        listenerBlock = nil
        listenerAddress = nil
        onChange = nil
    }

    // MARK: - Internal Helpers

    /// Queries the AudioDeviceID of the system default output device.
    private func queryDefaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    /// Queries full device information for a given AudioDeviceID.
    private func queryDeviceInfo(_ deviceID: AudioDeviceID, isDefault: Bool) -> AudioDeviceInfo? {
        guard let name = queryDeviceName(deviceID) else { return nil }
        let transportType = queryTransportType(deviceID)
        let sampleRate = querySampleRate(deviceID) ?? 0
        let channelCount = queryOutputChannelCount(deviceID)

        return AudioDeviceInfo(
            name: name,
            transportType: transportType,
            sampleRate: sampleRate,
            outputChannelCount: channelCount,
            isDefault: isDefault
        )
    }

    /// Queries the display name of an audio device.
    private func queryDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)

        guard status == noErr else {
            logger.error("Failed to query device name for \(deviceID): \(status)")
            return nil
        }

        return name as String
    }

    /// Queries the transport type of an audio device.
    private func queryTransportType(_ deviceID: AudioDeviceID) -> AudioTransportType {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)

        guard status == noErr else {
            logger.error("Failed to query transport type for \(deviceID): \(status)")
            return .unknown
        }

        return AudioTransportType(coreAudioTransportType: transport)
    }

    /// Queries the nominal sample rate of an audio device.
    private func querySampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)

        guard status == noErr else {
            logger.error("Failed to query sample rate for \(deviceID): \(status)")
            return nil
        }

        return rate
    }

    /// Queries the output channel count of an audio device via stream configuration.
    private func queryOutputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)

        guard status == noErr, size > 0 else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)

        guard status == noErr else {
            logger.error("Failed to query output channels for \(deviceID): \(status)")
            return 0
        }

        let bufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        var channelCount = 0
        withUnsafePointer(to: &bufferList.pointee.mBuffers) { firstBufferPtr in
            let buffers = UnsafeBufferPointer(
                start: firstBufferPtr,
                count: Int(bufferList.pointee.mNumberBuffers)
            )
            for buffer in buffers {
                channelCount += Int(buffer.mNumberChannels)
            }
        }
        return channelCount
    }
}
