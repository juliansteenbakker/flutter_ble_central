//
//  ScanResultHandler.swift
//  flutter_ble_central
//
//  Created by Julian Steenbakker on 28/03/2022.
//

import Foundation
#if os(iOS)
import Flutter
import UIKit
#else
import FlutterMacOS
#endif
import CoreBluetooth

/**
 Handles streaming Bluetooth LE scan results from CoreBluetooth
 to the Flutter layer via an `EventChannel`.

 **Responsibilities:**
 - Convert `AdvertisementData` into a Flutter-serializable dictionary.
 - Stream results through `"dev.steenbakker.flutter_ble_central/scan_result"`.
 - Benchmark time spent per publish and log average publish latency.
 */
public class ScanResultHandler: NSObject, FlutterStreamHandler {

    /// The current Flutter event sink for sending data to Dart.
    private var eventSink: FlutterEventSink?

    /// The event channel used for publishing scan results.
    private let eventChannel: FlutterEventChannel

    // MARK: - Init

    init(registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let messenger = registrar.messenger()
#else
        let messenger = registrar.messenger
#endif
        eventChannel = FlutterEventChannel(
            name: "dev.steenbakker.flutter_ble_central/scan_result",
            binaryMessenger: messenger
        )
        super.init()
        eventChannel.setStreamHandler(self)
    }

    // MARK: - Public API

    /**
     Publishes a single BLE scan result to Flutter and benchmarks the time.

     - Parameters:
       - advertiseData: Advertisement data dictionary from CoreBluetooth.
       - rssi: The received signal strength in dBm.
       - peripheral: The discovered peripheral.
     */
    func publishScanResult(advertiseData: AdvertisementData, rssi: Int, peripheral: CBPeripheral) {
        guard let eventSink = eventSink else {
#if DEBUG
            print("[ScanResultHandler] Warning: Event sink is nil, dropping scan result.")
#endif
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let message = parseAdvertisementData(advertiseData, rssi: rssi, peripheral: peripheral)

        DispatchQueue.main.async {
            eventSink(message)
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            PublishTimingStats.logTime(durationMs)
        }
    }

    // MARK: - Data Parsing

    private func parseAdvertisementData(
        _ advertiseData: AdvertisementData,
        rssi: Int,
        peripheral: CBPeripheral
    ) -> [String: Any] {
        var result: [String: Any] = [
            "address": peripheral.identifier.uuidString,
            "rssi": Int32(rssi)
        ]

        if let localName = advertiseData[CBAdvertisementDataLocalNameKey] as? String {
            result["deviceName"] = localName
        }

        if let manufacturerData = advertiseData[CBAdvertisementDataManufacturerDataKey] as? Data {
            result["manufacturerSpecificData"] = [UInt8](manufacturerData)
        }

        if let txPowerLevel = advertiseData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            result["txPower"] = txPowerLevel
        }

        if let isConnectable = advertiseData[CBAdvertisementDataIsConnectable] as? Bool {
            result["connectable"] = isConnectable
        }

        if let serviceUUIDs = advertiseData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            result["serviceUuids"] = serviceUUIDs.map { $0.uuidString }
        }

        if let overflowUUIDs = advertiseData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            result["overflowServiceUUIDs"] = overflowUUIDs.map { $0.uuidString }
        }

        if let solicitedUUIDs = advertiseData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] {
            result["serviceSolicitationUuids"] = solicitedUUIDs.map { $0.uuidString }
        }

        if let serviceData = advertiseData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            var mapped: [String: [UInt8]] = [:]
            for (key, value) in serviceData {
                mapped[key.uuidString] = [UInt8](value)
            }
            result["serviceData"] = mapped
        }

        return result
    }

    // MARK: - Benchmark Utility

    /**
     Tracks and logs BLE publish performance on iOS.

     Mirrors Android `PublishTimingStats` behavior for parity.
     */
    private enum PublishTimingStats {
        private static var totalTime: Double = 0
        private static var callCount: Int = 0

        static func logTime(_ durationMs: Double) {
            totalTime += durationMs
            callCount += 1
            let average = totalTime / Double(callCount)
#if DEBUG
            print("[PublishTiming] This call: \(String(format: "%.2f", durationMs)) ms, Average: \(String(format: "%.2f", average)) ms over \(callCount) calls")
#endif
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
