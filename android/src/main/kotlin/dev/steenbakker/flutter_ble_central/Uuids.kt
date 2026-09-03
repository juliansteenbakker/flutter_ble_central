package dev.steenbakker.flutter_ble_central

import java.util.UUID

/**
 * Parses a uuid Dart sent into a [UUID].
 *
 * Accepts the 16 bit ("2A37"), 32 bit ("A1B2C3D4") and 128 bit forms, with or
 * without dashes, the way the Apple and Windows implementations do. Android
 * reports the expanded form for everything it discovers and for everything it
 * filters on, so a short form has to be expanded onto the Bluetooth Base UUID
 * before it can match anything.
 *
 * @return The parsed uuid, or null when it is not one.
 */
internal fun parseUuid(value: String): UUID? {
    val hex = value.replace("-", "")
    if (!hex.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' }) return null
    val full = when (hex.length) {
        4 -> "0000$hex-0000-1000-8000-00805F9B34FB"
        8 -> "$hex-0000-1000-8000-00805F9B34FB"
        32 -> "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
                "${hex.substring(16, 20)}-${hex.substring(20)}"
        else -> return null
    }
    return try {
        UUID.fromString(full)
    } catch (e: IllegalArgumentException) {
        null
    }
}
