package dev.steenbakker.flutter_ble_central

import android.Manifest
import android.bluetooth.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresPermission
import dev.steenbakker.flutter_ble_central.handlers.BondStateHandler
import dev.steenbakker.flutter_ble_central.handlers.ConnectionStateHandler
import dev.steenbakker.flutter_ble_central.handlers.CharacteristicValueHandler
import java.util.*
import java.util.concurrent.ConcurrentHashMap

/**
 * Manages GATT connections for multiple BLE devices.
 *
 * Handles:
 * - Connecting/disconnecting from devices
 * - Service discovery
 * - Characteristic read/write/notify operations
 * - Connection state tracking
 * - Operation queuing to avoid conflicts
 */
class GattConnectionManager(
    private val context: Context,
    private val connectionStateHandler: ConnectionStateHandler,
    private val characteristicValueHandler: CharacteristicValueHandler,
    private val bondStateHandler: BondStateHandler
) {
    companion object {
        private const val TAG = "GattConnectionManager"
        private const val CCCD_UUID = "00002902-0000-1000-8000-00805f9b34fb"
        private const val OPERATION_TIMEOUT_MS = 10000L // 10 seconds

        /**
         * Convert GATT status code to human-readable error message
         */
        private fun getGattStatusMessage(status: Int): String {
            return when (status) {
                BluetoothGatt.GATT_SUCCESS -> "Success"
                BluetoothGatt.GATT_READ_NOT_PERMITTED -> "Read not permitted"
                BluetoothGatt.GATT_WRITE_NOT_PERMITTED -> "Write not permitted"
                BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION -> "Insufficient authentication"
                BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED -> "Request not supported"
                BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION -> "Insufficient encryption"
                BluetoothGatt.GATT_INVALID_OFFSET -> "Invalid offset"
                BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH -> "Invalid attribute length"
                BluetoothGatt.GATT_CONNECTION_CONGESTED -> "Connection congested"
                BluetoothGatt.GATT_FAILURE -> "GATT failure"
                0x0085 -> "Connection terminated by peer"
                0x0016 -> "Connection terminated by local host"
                0x003E -> "Connection failed to establish"
                0x0022 -> "LMP response timeout"
                0x0100 -> "Device not found"
                else -> "GATT error ($status)"
            }
        }
    }

    // Store active GATT connections by device address
    private val gattConnections = ConcurrentHashMap<String, BluetoothGatt>()

    // Store discovered services by device address
    private val discoveredServices = ConcurrentHashMap<String, List<BluetoothGattService>>()

    // Store pending callbacks for async operations
    private val serviceDiscoveryCallbacks = ConcurrentHashMap<String, Pair<(List<Map<String, Any>>) -> Unit, (String) -> Unit>>()
    private val characteristicReadCallbacks = ConcurrentHashMap<String, Pair<(ByteArray) -> Unit, (String) -> Unit>>()
    private val descriptorReadCallbacks = ConcurrentHashMap<String, Pair<(ByteArray) -> Unit, (String) -> Unit>>()
    private val rssiCallbacks = ConcurrentHashMap<String, Pair<(Int) -> Unit, (String) -> Unit>>()
    private val mtuCallbacks = ConcurrentHashMap<String, Pair<(Int) -> Unit, (String) -> Unit>>()
    private val phyReadCallbacks = ConcurrentHashMap<String, Pair<(Int, Int) -> Unit, (String) -> Unit>>()
    private val reliableWriteCallbacks = ConcurrentHashMap<String, Pair<() -> Unit, (String) -> Unit>>()
    private val connectionTimeouts = ConcurrentHashMap<String, Runnable>()

    // Operation queue to serialize GATT operations
    private val operationQueue = LinkedList<GattOperation>()
    private var currentOperation: GattOperation? = null
    private var currentOperationTimeout: Runnable? = null
    private val handler = Handler(Looper.getMainLooper())
    private val queueLock = Any() // Lock for thread-safe queue operations

    // Bond state broadcast receiver
    private val bondStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothDevice.ACTION_BOND_STATE_CHANGED) {
                val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                }
                val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                device?.let {
                    Log.d(TAG, "Bond state changed: ${it.address}, state=$bondState")
                    bondStateHandler.publishBondState(it.address, bondState)
                }
            }
        }
    }

    init {
        // Register bond state receiver
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(bondStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(bondStateReceiver, filter)
        }
    }

    /**
     * Represents a GATT operation (read, write, etc.)
     */
    private data class GattOperation(
        val address: String,
        val operation: () -> Boolean,
        val onSuccess: (() -> Unit)? = null,
        val onError: ((String) -> Unit)? = null
    )

    /**
     * Connect to a BLE device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun connect(
        context: Context,
        address: String,
        autoConnect: Boolean,
        timeout: Int,
        onError: ((String) -> Unit)? = null
    ) {
        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter
            val device = adapter.getRemoteDevice(address)

            if (gattConnections.containsKey(address)) {
                onError?.invoke("Already connected to device")
                return
            }

            val gattCallback = createGattCallback(address)

            val gatt =
                device.connectGatt(context, autoConnect, gattCallback, BluetoothDevice.TRANSPORT_LE)

            gattConnections[address] = gatt

            // Set up timeout
            if (timeout > 0) {
                val timeoutRunnable = Runnable {
                    if (gattConnections.containsKey(address) &&
                        getConnectionState(address) != BluetoothProfile.STATE_CONNECTED) {
                        disconnect(address)
                        onError?.invoke("Connection timeout")
                    }
                }
                connectionTimeouts[address] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, (timeout * 1000).toLong())
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error connecting to device: ${e.message}")
            onError?.invoke(e.message ?: "Connection error")
        }
    }

    /**
     * Disconnect from a BLE device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun disconnect(address: String) {
        gattConnections[address]?.let { gatt ->
            try {
                // Closing here would unregister the client before the stack
                // reports the disconnect, so onConnectionStateChange would never
                // fire and nothing waiting on the connection state would hear
                // that it finished. The callback closes it and clears the rest.
                gatt.disconnect()
            } catch (e: Exception) {
                Log.e(TAG, "Error disconnecting: ${e.message}")
                // No callback is coming, so report it and clean up here.
                try {
                    gatt.close()
                } catch (closeError: Exception) {
                    Log.e(TAG, "Error closing: ${closeError.message}")
                }
                connectionStateHandler.publishConnectionState(
                    address,
                    BluetoothProfile.STATE_DISCONNECTED
                )
                forget(address)
            }
        }
    }

    /**
     * Drops everything held for a connection that is gone.
     */
    private fun forget(address: String) {
        gattConnections.remove(address)
        discoveredServices.remove(address)
        serviceDiscoveryCallbacks.remove(address)
        // Remove all characteristic and descriptor callbacks for this address (efficient pattern)
        characteristicReadCallbacks.entries.removeIf { it.key.startsWith("$address:") }
        descriptorReadCallbacks.entries.removeIf { it.key.startsWith("$address:") }
        rssiCallbacks.remove(address)
        mtuCallbacks.remove(address)
        phyReadCallbacks.remove(address)
        reliableWriteCallbacks.remove(address)
        connectionTimeouts[address]?.let { handler.removeCallbacks(it) }
        connectionTimeouts.remove(address)
    }

    /**
     * Get connection state for a device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun getConnectionState(address: String): Int {
        gattConnections[address] ?: return BluetoothProfile.STATE_DISCONNECTED
        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter
            val device = adapter.getRemoteDevice(address)
            return bluetoothManager.getConnectionState(device, BluetoothProfile.GATT)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting connection state: ${e.message}")
            return BluetoothProfile.STATE_DISCONNECTED
        }
    }

    /**
     * Discover services on a connected device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun discoverServices(address: String, onComplete: (List<Map<String, Any>>) -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        // Check if already discovered
        discoveredServices[address]?.let { services ->
            onComplete(serializeServices(services))
            return
        }

        // Store callbacks for later invocation
        serviceDiscoveryCallbacks[address] = Pair(onComplete, onError)

        // Trigger discovery
        if (!gatt.discoverServices()) {
            serviceDiscoveryCallbacks.remove(address)
            onError("Failed to start service discovery")
        }
        // Result will be delivered via BluetoothGattCallback.onServicesDiscovered
    }

    /**
     * Read a characteristic value
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun readCharacteristic(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        onComplete: (ByteArray) -> Unit,
        onError: (String) -> Unit
    ) {
        val characteristic = getCharacteristic(address, serviceUuid, characteristicUuid)
        if (characteristic == null) {
            onError("Characteristic not found")
            return
        }

        // Validate characteristic supports read
        if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_READ == 0) {
            onError("Characteristic does not support read")
            return
        }

        // Create unique key for this read operation
        val key = "$address:$serviceUuid:$characteristicUuid"

        enqueueOperation(GattOperation(
            address = address,
            operation = {
                // Store callbacks before initiating read
                characteristicReadCallbacks[key] = Pair(onComplete, onError)
                gattConnections[address]?.readCharacteristic(characteristic) ?: false
            },
            onSuccess = null, // Handled in callback
            onError = {
                characteristicReadCallbacks.remove(key)
                onError(it)
            }
        ))
    }

    /**
     * Write a characteristic value
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun writeCharacteristic(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray,
        withoutResponse: Boolean,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        val characteristic = getCharacteristic(address, serviceUuid, characteristicUuid)
        if (characteristic == null) {
            onError("Characteristic not found")
            return
        }

        // Validate characteristic supports write
        val requiresResponse = !withoutResponse
        val hasWriteProperty = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        val hasWriteNoResponseProperty = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0

        if (requiresResponse && !hasWriteProperty) {
            onError("Characteristic does not support write with response")
            return
        }

        if (!requiresResponse && !hasWriteNoResponseProperty) {
            onError("Characteristic does not support write without response")
            return
        }

        enqueueOperation(GattOperation(
            address = address,
            operation = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val writeType = if (withoutResponse) {
                            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                        } else {
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                        }
                        gattConnections[address]?.writeCharacteristic(
                            characteristic,
                            value,
                            writeType
                        ) == BluetoothStatusCodes.SUCCESS
                    } else {
                        @Suppress("DEPRECATION")
                        characteristic.value = value
                        @Suppress("DEPRECATION")
                        characteristic.writeType = if (withoutResponse) {
                            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                        } else {
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                        }
                        @Suppress("DEPRECATION")
                        gattConnections[address]?.writeCharacteristic(characteristic) ?: false
                    }
            },
            onSuccess = onComplete,
            onError = onError
        ))
    }

    /**
     * Enable or disable characteristic notifications
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun setCharacteristicNotification(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        enable: Boolean,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        val characteristic = getCharacteristic(address, serviceUuid, characteristicUuid)
        if (characteristic == null) {
            onError("Characteristic not found")
            return
        }

        // Validate characteristic supports notify or indicate
        val hasNotify = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0
        val hasIndicate = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0

        if (!hasNotify && !hasIndicate) {
            onError("Characteristic does not support notify or indicate")
            return
        }

        enqueueOperation(GattOperation(
            address = address,
            operation = {
                val gatt = gattConnections[address]
                if (gatt == null) {
                    onError("Device not connected")
                    return@GattOperation false
                }

                // Enable local notifications
                if (!gatt.setCharacteristicNotification(characteristic, enable)) {
                    onError("Failed to set characteristic notification")
                    return@GattOperation false
                }

                // Write to CCCD descriptor
                val descriptor = characteristic.getDescriptor(UUID.fromString(CCCD_UUID))
                if (descriptor == null) {
                    onError("CCCD descriptor not found")
                    return@GattOperation false
                }

                val value = if (enable) {
                    if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    } else {
                        BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    }
                } else {
                    BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = value
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
            },
            onSuccess = onComplete,
            onError = onError
        ))
    }

    /**
     * Read a descriptor value
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun readDescriptor(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        onComplete: (ByteArray) -> Unit,
        onError: (String) -> Unit
    ) {
        val descriptor = getDescriptor(address, serviceUuid, characteristicUuid, descriptorUuid)
        if (descriptor == null) {
            onError("Descriptor not found")
            return
        }

        // Create unique key for this read operation
        val key = "$address:$serviceUuid:$characteristicUuid:$descriptorUuid"

        enqueueOperation(GattOperation(
            address = address,
            operation = {
                // Store callbacks before initiating read
                descriptorReadCallbacks[key] = Pair(onComplete, onError)
                gattConnections[address]?.readDescriptor(descriptor) ?: false
            },
            onSuccess = null, // Handled in callback
            onError = {
                descriptorReadCallbacks.remove(key)
                onError(it)
            }
        ))
    }

    /**
     * Write a descriptor value
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun writeDescriptor(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        value: ByteArray,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        enqueueOperation(GattOperation(
            address = address,
            operation = {
                val descriptor = getDescriptor(address, serviceUuid, characteristicUuid, descriptorUuid)
                if (descriptor == null) {
                    onError("Descriptor not found")
                    false
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        gattConnections[address]?.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS
                    } else {
                        @Suppress("DEPRECATION")
                        descriptor.value = value
                        @Suppress("DEPRECATION")
                        gattConnections[address]?.writeDescriptor(descriptor) ?: false
                    }
                }
            },
            onSuccess = onComplete,
            onError = onError
        ))
    }

    /**
     * Read an RSSI value
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun readRssi(address: String, onComplete: (Int) -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        // Store callbacks for later invocation
        rssiCallbacks[address] = Pair(onComplete, onError)

        if (!gatt.readRemoteRssi()) {
            rssiCallbacks.remove(address)
            onError("Failed to read RSSI")
        }
        // Result will be delivered via BluetoothGattCallback.onReadRemoteRssi
    }

    /**
     * Request MTU size
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun requestMtu(address: String, mtu: Int, onComplete: (Int) -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        // Store callbacks for later invocation
        mtuCallbacks[address] = Pair(onComplete, onError)

        if (!gatt.requestMtu(mtu)) {
            mtuCallbacks.remove(address)
            onError("Failed to request MTU")
        }
        // Result will be delivered via BluetoothGattCallback.onMtuChanged
    }

    // Private helper methods

    private fun createGattCallback(address: String): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                Log.d(TAG, "Connection state changed: $address, status=$status, newState=$newState")

                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        // Cancel connection timeout
                        connectionTimeouts[address]?.let { handler.removeCallbacks(it) }
                        connectionTimeouts.remove(address)
                        connectionStateHandler.publishConnectionState(address, newState)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        connectionStateHandler.publishConnectionState(address, newState)
                        forget(address)
                        gatt.close()
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val callbacks = serviceDiscoveryCallbacks.remove(address)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    val services = gatt.services
                    discoveredServices[address] = services
                    Log.d(TAG, "Services discovered: ${services.size} services")
                    callbacks?.first?.invoke(serializeServices(services))
                } else {
                    val errorMsg = "Service discovery failed: ${getGattStatusMessage(status)}"
                    Log.e(TAG, errorMsg)
                    callbacks?.second?.invoke(errorMsg)
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                val key = "$address:${characteristic.service.uuid}:${characteristic.uuid}"
                val callbacks = characteristicReadCallbacks.remove(key)

                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callbacks?.first?.invoke(value)
                } else {
                    callbacks?.second?.invoke("Characteristic read failed: ${getGattStatusMessage(status)}")
                }
                completeCurrentOperation(status == BluetoothGatt.GATT_SUCCESS)
            }

            @Deprecated("Deprecated in API level 33")
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    onCharacteristicRead(gatt, characteristic, characteristic.value, status)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                completeCurrentOperation(status == BluetoothGatt.GATT_SUCCESS)
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray
            ) {
                characteristicValueHandler.publishCharacteristicValue(
                    address,
                    characteristic.service.uuid.toString(),
                    characteristic.uuid.toString(),
                    value
                )
            }

            @Deprecated("Deprecated in API level 33")
            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    onCharacteristicChanged(gatt, characteristic, characteristic.value)
                }
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
                value: ByteArray
            ) {
                val key = "$address:${descriptor.characteristic.service.uuid}:${descriptor.characteristic.uuid}:${descriptor.uuid}"
                val callbacks = descriptorReadCallbacks.remove(key)

                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callbacks?.first?.invoke(value)
                } else {
                    callbacks?.second?.invoke("Descriptor read failed: ${getGattStatusMessage(status)}")
                }
                completeCurrentOperation(status == BluetoothGatt.GATT_SUCCESS)
            }

            @Deprecated("Deprecated in API level 33")
            @Suppress("DEPRECATION")
            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                    onDescriptorRead(gatt, descriptor, status, descriptor.value)
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                completeCurrentOperation(status == BluetoothGatt.GATT_SUCCESS)
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                val callbacks = rssiCallbacks.remove(address)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callbacks?.first?.invoke(rssi)
                } else {
                    callbacks?.second?.invoke("Failed to read RSSI: ${getGattStatusMessage(status)}")
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                val callbacks = mtuCallbacks.remove(address)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callbacks?.first?.invoke(mtu)
                } else {
                    callbacks?.second?.invoke("Failed to change MTU: ${getGattStatusMessage(status)}")
                }
            }

            override fun onPhyRead(gatt: BluetoothGatt, txPhy: Int, rxPhy: Int, status: Int) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val callbacks = phyReadCallbacks.remove(address)
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        callbacks?.first?.invoke(txPhy, rxPhy)
                    } else {
                        callbacks?.second?.invoke("Failed to read PHY: ${getGattStatusMessage(status)}")
                    }
                }
            }

            override fun onPhyUpdate(gatt: BluetoothGatt, txPhy: Int, rxPhy: Int, status: Int) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        Log.d(TAG, "PHY updated: txPhy=$txPhy, rxPhy=$rxPhy")
                    } else {
                        Log.e(TAG, "PHY update failed: ${getGattStatusMessage(status)}")
                    }
                }
            }

            override fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {
                val callbacks = reliableWriteCallbacks.remove(address)
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callbacks?.first?.invoke()
                } else {
                    callbacks?.second?.invoke("Reliable write failed: ${getGattStatusMessage(status)}")
                }
            }

            @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
            override fun onServiceChanged(gatt: BluetoothGatt) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Log.d(TAG, "Service changed for device: $address")
                    // Clear cached services so they will be re-discovered
                    discoveredServices.remove(address)
                    // Automatically trigger service discovery
                    gatt.discoverServices()
                }
            }
        }
    }

    /**
     * Parses a uuid Dart sent into a [UUID].
     *
     * Accepts the 16 bit ("2A37"), 32 bit ("A1B2C3D4") and 128 bit forms, with or
     * without dashes, the way the Apple and Windows implementations do. Android
     * reports the expanded form for everything it discovers, so a short form has to
     * be expanded onto the Bluetooth Base UUID before it can match anything.
     *
     * @return The parsed uuid, or null when it is not one.
     */
    private fun parseUuid(value: String): UUID? {
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

    private fun getCharacteristic(
        address: String,
        serviceUuid: String,
        characteristicUuid: String
    ): BluetoothGattCharacteristic? {
        val services = discoveredServices[address] ?: return null
        val wantedService = parseUuid(serviceUuid) ?: return null
        val wantedCharacteristic = parseUuid(characteristicUuid) ?: return null
        val service = services.find { it.uuid == wantedService } ?: return null
        return service.characteristics.find { it.uuid == wantedCharacteristic }
    }

    private fun getDescriptor(
        address: String,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String
    ): BluetoothGattDescriptor? {
        val characteristic = getCharacteristic(address, serviceUuid, characteristicUuid) ?: return null
        val wanted = parseUuid(descriptorUuid) ?: return null
        return characteristic.descriptors.find { it.uuid == wanted }
    }

    private fun serializeServices(services: List<BluetoothGattService>): List<Map<String, Any>> {
        return services.map { service ->
            mapOf(
                "uuid" to service.uuid.toString(),
                "isPrimary" to (service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY),
                "characteristics" to service.characteristics.map { char ->
                    mapOf(
                        "uuid" to char.uuid.toString(),
                        "serviceUuid" to service.uuid.toString(),
                        "properties" to mapOf(
                            "broadcast" to (char.properties and BluetoothGattCharacteristic.PROPERTY_BROADCAST != 0),
                            "read" to (char.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0),
                            "writeWithoutResponse" to (char.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0),
                            "write" to (char.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0),
                            "notify" to (char.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0),
                            "indicate" to (char.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0),
                            "authenticatedSignedWrites" to (char.properties and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE != 0),
                            "extendedProperties" to (char.properties and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS != 0)
                        ),
                        "descriptors" to char.descriptors.map { desc ->
                            mapOf(
                                "uuid" to desc.uuid.toString(),
                                "characteristicUuid" to char.uuid.toString(),
                                "serviceUuid" to service.uuid.toString()
                            )
                        }
                    )
                }
            )
        }
    }

    private fun enqueueOperation(operation: GattOperation) {
        synchronized(queueLock) {
            operationQueue.add(operation)
            if (currentOperation == null) {
                executeNextOperation()
            }
        }
    }

    private fun executeNextOperation() {
        val op = synchronized(queueLock) {
            if (operationQueue.isEmpty()) {
                currentOperation = null
                currentOperationTimeout?.let { handler.removeCallbacks(it) }
                currentOperationTimeout = null
                return
            }

            operationQueue.poll().also { operation ->
                currentOperation = operation
            }
        }

        op?.let { operation ->
            // Set up operation timeout
            val timeoutRunnable = Runnable {
                synchronized(queueLock) {
                    // Only timeout if this is still the current operation
                    if (currentOperation == operation) {
                        Log.e(TAG, "Operation timeout for device: ${operation.address}")
                        operation.onError?.invoke("Operation timeout")
                        currentOperation = null
                        currentOperationTimeout = null
                    }
                }
                executeNextOperation()
            }

            synchronized(queueLock) {
                currentOperationTimeout = timeoutRunnable
            }
            handler.postDelayed(timeoutRunnable, OPERATION_TIMEOUT_MS)

            val success = try {
                operation.operation()
            } catch (e: Exception) {
                Log.e(TAG, "Operation error: ${e.message}")
                false
            }

            if (!success) {
                synchronized(queueLock) {
                    // Cancel timeout since operation failed immediately
                    currentOperationTimeout?.let { handler.removeCallbacks(it) }
                    currentOperationTimeout = null
                    currentOperation = null
                }
                operation.onError?.invoke("Operation failed")
                executeNextOperation()
            }
        }
    }

    private fun completeCurrentOperation(success: Boolean) {
        val op = synchronized(queueLock) {
            // Cancel the timeout
            currentOperationTimeout?.let { handler.removeCallbacks(it) }
            currentOperationTimeout = null

            val operation = currentOperation
            currentOperation = null
            operation
        }

        op?.let { operation ->
            if (success) {
                operation.onSuccess?.invoke()
            } else {
                operation.onError?.invoke("Operation failed")
            }
        }
        executeNextOperation()
    }

    /**
     * Create a bond (pair) with a device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun createBond(address: String, onError: (String) -> Unit) {
        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter
            val device = adapter.getRemoteDevice(address)

            if (device.bondState == BluetoothDevice.BOND_BONDED) {
                onError("Device is already bonded")
                return
            }

            if (device.bondState == BluetoothDevice.BOND_BONDING) {
                onError("Bonding is already in progress")
                return
            }

            val result = device.createBond()
            if (!result) {
                onError("Failed to start bonding process")
            }
            // Result will be delivered via BroadcastReceiver
        } catch (e: Exception) {
            Log.e(TAG, "Error creating bond: ${e.message}")
            onError(e.message ?: "Bond creation error")
        }
    }

    /**
     * Remove a bond (unpair) with a device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun removeBond(address: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter
            val device = adapter.getRemoteDevice(address)

            if (device.bondState == BluetoothDevice.BOND_NONE) {
                onError("Device is not bonded")
                return
            }

            // Use reflection to call the hidden removeBond method
            val method = device.javaClass.getMethod("removeBond")
            val result = method.invoke(device) as Boolean

            if (result) {
                onComplete()
            } else {
                onError("Failed to remove bond")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing bond: ${e.message}")
            onError(e.message ?: "Bond removal error")
        }
    }

    /**
     * Get bond state for a device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun getBondState(address: String): Int {
        return try {
            val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = bluetoothManager.adapter
            val device = adapter.getRemoteDevice(address)
            device.bondState
        } catch (e: Exception) {
            Log.e(TAG, "Error getting bond state: ${e.message}")
            BluetoothDevice.BOND_NONE
        }
    }

    /**
     * Set preferred PHY (Physical Layer) for a device (BLE 5.0+)
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun setPreferredPhy(
        address: String,
        txPhy: Int,
        rxPhy: Int,
        phyOptions: Int,
        onComplete: () -> Unit,
        onError: (String) -> Unit
    ) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Validate PHY values (LE_1M=1, LE_2M=2, LE_CODED=3)
            val validPhyValues = listOf(
                BluetoothDevice.PHY_LE_1M,
                BluetoothDevice.PHY_LE_2M,
                BluetoothDevice.PHY_LE_CODED
            )

            if (txPhy !in validPhyValues || rxPhy !in validPhyValues) {
                onError("Invalid PHY value. Must be 1 (LE_1M), 2 (LE_2M), or 3 (LE_CODED)")
                return
            }

            // Validate PHY options (NO_PREFERRED=0, S2=1, S8=2)
            val validPhyOptions = listOf(
                BluetoothDevice.PHY_OPTION_NO_PREFERRED,
                BluetoothDevice.PHY_OPTION_S2,
                BluetoothDevice.PHY_OPTION_S8
            )

            if (phyOptions !in validPhyOptions) {
                onError("Invalid PHY options. Must be 0 (NO_PREFERRED), 1 (S2), or 2 (S8)")
                return
            }

            gatt.setPreferredPhy(txPhy, rxPhy, phyOptions)
            // Result will be delivered via onPhyUpdate callback
            onComplete()
        } else {
            onError("PHY control not supported on this Android version (requires Android 8.0+)")
        }
    }

    /**
     * Read current PHY for a device (BLE 5.0+)
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun readPhy(address: String, onComplete: (Int, Int) -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Store callbacks for later invocation
            phyReadCallbacks[address] = Pair(onComplete, onError)
            gatt.readPhy()
            // Result will be delivered via onPhyRead callback
        } else {
            onError("PHY control not supported on this Android version (requires Android 8.0+)")
        }
    }

    /**
     * Begin a reliable write transaction
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun beginReliableWrite(address: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        val result = gatt.beginReliableWrite()
        if (result) {
            onComplete()
        } else {
            onError("Failed to begin reliable write")
        }
    }

    /**
     * Execute (commit) a reliable write transaction
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun executeReliableWrite(address: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        // Store callbacks for later invocation
        reliableWriteCallbacks[address] = Pair(onComplete, onError)

        if (!gatt.executeReliableWrite()) {
            reliableWriteCallbacks.remove(address)
            onError("Failed to execute reliable write")
        }
        // Result will be delivered via onReliableWriteCompleted callback
    }

    /**
     * Abort (rollback) a reliable write transaction
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun abortReliableWrite(address: String, onComplete: () -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        gatt.abortReliableWrite()
        onComplete()
    }

    /**
     * Request connection priority for a device
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun requestConnectionPriority(address: String, priority: Int, onComplete: () -> Unit, onError: (String) -> Unit) {
        val gatt = gattConnections[address]
        if (gatt == null) {
            onError("Device not connected")
            return
        }

        // Validate priority value
        val validPriorities = listOf(
            BluetoothGatt.CONNECTION_PRIORITY_HIGH,
            BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
            BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER
        )

        if (priority !in validPriorities) {
            onError("Invalid priority value. Must be 0 (HIGH), 1 (BALANCED), or 2 (LOW_POWER)")
            return
        }

        val result = gatt.requestConnectionPriority(priority)
        if (result) {
            onComplete()
        } else {
            onError("Failed to request connection priority")
        }
    }

    /**
     * Clean up all connections
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun cleanup() {
        // Disconnect all devices (snapshot keys to avoid ConcurrentModificationException).
        // The engine is going away, so no callback will arrive to close these for us.
        gattConnections.keys.toList().forEach { address ->
            try {
                gattConnections[address]?.let {
                    it.disconnect()
                    it.close()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error disconnecting: ${e.message}")
            }
            forget(address)
        }

        synchronized(queueLock) {
            // Cancel any pending operation timeout
            currentOperationTimeout?.let { handler.removeCallbacks(it) }
            currentOperationTimeout = null

            // Clear operation queue
            operationQueue.clear()
            currentOperation = null
        }

        // Unregister bond state receiver
        try {
            context.unregisterReceiver(bondStateReceiver)
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering bond receiver: ${e.message}")
        }
    }
}
