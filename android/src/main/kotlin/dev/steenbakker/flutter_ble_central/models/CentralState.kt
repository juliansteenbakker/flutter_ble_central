package dev.steenbakker.flutter_ble_central.models

/**
 * Represents the Bluetooth adapter state for the central manager.
 * These values must match the Dart CentralState enum ordinals.
 */
enum class CentralState {
    /** Status is not (yet) determined. */
    unknown,        // 0

    /** BLE is not supported on this device. */
    unsupported,    // 1

    /** BLE usage is not authorized for this app. */
    unauthorized,   // 2

    /** BLE is turned off. */
    poweredOff,     // 3

    /** BLE is fully operating for this app. */
    idle,           // 4

    /** BLE is advertising data. */
    advertising,    // 5

    /** BLE is connected to a device. */
    connected,      // 6
}
