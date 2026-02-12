//
//  ControllerMonitor.swift
//  Whisky
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

import Foundation
import GameController
import os.log

/// The type of game controller based on its product category.
enum ControllerType: String, Sendable {
    case playStation
    case xbox
    case generic

    /// The SF Symbol name for this controller type.
    var sfSymbol: String {
        "gamecontroller"
    }

    /// A human-readable display name for the controller type.
    var displayName: String {
        switch self {
        case .playStation:
            "PlayStation"
        case .xbox:
            "Xbox"
        case .generic:
            "Generic"
        }
    }
}

/// The connection type for a game controller.
enum ConnectionType: String, Sendable {
    case usb = "USB"
    case bluetooth = "Bluetooth"

    /// The SF Symbol name for this connection type.
    var sfSymbol: String {
        switch self {
        case .usb:
            "cable.connector"
        case .bluetooth:
            "wave.3.right"
        }
    }
}

/// Information about a connected game controller.
///
/// Captures the name, type, connection method, and battery status
/// of a controller discovered via the GameController framework.
struct ControllerInfo: Identifiable, Sendable {
    /// Unique identifier for this controller snapshot.
    let id: UUID

    /// The vendor-provided name of the controller, or "Unknown Controller" if unavailable.
    let name: String

    /// The product category string from GCController (e.g. "DualSense", "Xbox Wireless Controller").
    let productCategory: String

    /// The current battery level as a value from 0.0 to 1.0, or nil if not available.
    let batteryLevel: Float?

    /// The battery state as a string (charging, discharging, full, unknown), or nil if not available.
    let batteryState: String?

    /// Whether the controller is physically attached (USB). False indicates wireless (Bluetooth).
    let isAttachedToDevice: Bool

    /// The classified controller type based on product category.
    var typeBadge: ControllerType {
        let category = productCategory.lowercased()
        if category.contains("dualshock") || category.contains("dualsense") {
            return .playStation
        } else if category.contains("xbox") {
            return .xbox
        } else {
            return .generic
        }
    }

    /// The connection type based on attachment status.
    var connectionType: ConnectionType {
        isAttachedToDevice ? .usb : .bluetooth
    }
}

/// A lightweight record of a previously-seen controller for diagnostics export.
struct ControllerHistoryEntry: Codable, Sendable {
    /// The name of the controller.
    let name: String

    /// The connection type when last seen (USB or Bluetooth).
    let connectionType: String

    /// The date when the controller was last observed.
    let lastSeen: Date
}

/// Monitors connected game controllers using Apple's GameController framework.
///
/// Provides real-time discovery and status updates for connected controllers,
/// including type classification (PlayStation/Xbox/Generic), connection method
/// (USB/Bluetooth), and battery information.
///
/// ## Usage
///
/// ```swift
/// let monitor = ControllerMonitor()
/// monitor.startMonitoring()
/// // monitor.controllers now contains connected controllers
/// ```
@MainActor
class ControllerMonitor: ObservableObject {
    /// The currently connected controllers.
    @Published var controllers: [ControllerInfo] = []

    /// The last time the controller list was refreshed.
    @Published var lastRefreshed: Date = .init()

    /// Recent controller history for diagnostics export (bounded to last 10 entries).
    var recentHistory: [ControllerHistoryEntry] = []

    private let logger = Logger(
        subsystem: "com.isaacmarovitz.Whisky",
        category: "ControllerMonitor"
    )

    /// Stored observer tokens for cleanup.
    /// Uses nonisolated(unsafe) to allow access from deinit (Swift 6 Sendable compliance).
    private nonisolated(unsafe) var connectObserver: NSObjectProtocol?
    private nonisolated(unsafe) var disconnectObserver: NSObjectProtocol?

    /// Maximum number of history entries to retain.
    private static let maxHistoryEntries = 10

    init() {}

    deinit {
        // Remove observers directly in deinit since we cannot call @MainActor methods.
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Starts monitoring for controller connect and disconnect events.
    ///
    /// Registers for ``NSNotification.Name.GCControllerDidConnect`` and
    /// ``NSNotification.Name.GCControllerDidDisconnect`` notifications,
    /// then performs an initial refresh to capture already-connected controllers.
    func startMonitoring() {
        // Register for notifications before querying controllers()
        // so that late-discovered controllers update the list.
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        refresh()
    }

    /// Stops monitoring for controller events and removes notification observers.
    func stopMonitoring() {
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
            connectObserver = nil
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
            disconnectObserver = nil
        }
    }

    /// Refreshes the list of connected controllers.
    ///
    /// Queries ``GCController.controllers()`` and maps each to a ``ControllerInfo``.
    /// Updates the ``controllers`` and ``lastRefreshed`` published properties,
    /// and appends new entries to ``recentHistory``.
    func refresh() {
        let gcControllers = GCController.controllers()
        controllers = gcControllers.map { mapController($0) }
        lastRefreshed = Date()

        logger.info("Controller refresh: \(self.controllers.count) controller(s) connected")

        updateHistory()
    }

    // MARK: - Private Helpers

    /// Maps a GCController to a ControllerInfo snapshot.
    private func mapController(_ controller: GCController) -> ControllerInfo {
        let batteryInfo = readBattery(controller)

        return ControllerInfo(
            id: UUID(),
            name: controller.vendorName ?? "Unknown Controller",
            productCategory: controller.productCategory,
            batteryLevel: batteryInfo?.level,
            batteryState: batteryInfo?.state,
            isAttachedToDevice: controller.isAttachedToDevice
        )
    }

    /// Reads battery information from a controller, if available.
    private func readBattery(_ controller: GCController) -> (level: Float, state: String)? {
        guard let battery = controller.battery else { return nil }

        let stateString = switch battery.batteryState {
        case .charging:
            "charging"
        case .discharging:
            "discharging"
        case .full:
            "full"
        case .unknown:
            "unknown"
        @unknown default:
            "unknown"
        }

        return (level: battery.batteryLevel, state: stateString)
    }

    /// Updates the recent history with currently connected controllers.
    ///
    /// Deduplicates by controller name and bounds the list to the most recent entries.
    private func updateHistory() {
        let now = Date()

        for controller in controllers {
            // Remove existing entry with the same name (dedup)
            recentHistory.removeAll { $0.name == controller.name }

            recentHistory.append(ControllerHistoryEntry(
                name: controller.name,
                connectionType: controller.connectionType.rawValue,
                lastSeen: now
            ))
        }

        // Bound to the most recent entries
        if recentHistory.count > Self.maxHistoryEntries {
            recentHistory = Array(recentHistory.suffix(Self.maxHistoryEntries))
        }
    }
}
