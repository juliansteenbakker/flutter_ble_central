//// Copyright 2017, Paul DeMarco.
//// All rights reserved. Use of this source code is governed by a
//// BSD-style license that can be found in the LICENSE file.
//package com.boskokg.flutter_blue_plus
//
//import android.Manifest
//import android.annotation.TargetApi
//import android.app.Application
//import android.bluetooth.*
//import android.bluetooth.BluetoothAdapter.LeScanCallback
//import android.bluetooth.le.*
//import android.content.BroadcastReceiver
//import android.content.Context
//import android.content.Intent
//import android.content.IntentFilter
//import android.content.pm.PackageManager
//import android.os.Build
//import android.os.Handler
//import android.os.Looper
//import android.os.ParcelUuid
//import android.util.Log
//import androidx.core.app.ActivityCompat
//import androidx.core.content.ContextCompat
//import com.google.protobuf.ByteString
//import com.google.protobuf.InvalidProtocolBufferException
//import io.flutter.embedding.engine.plugins.FlutterPlugin
//import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
//import io.flutter.embedding.engine.plugins.activity.ActivityAware
//import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
//import io.flutter.plugin.common.BinaryMessenger
//import io.flutter.plugin.common.EventChannel
//import io.flutter.plugin.common.EventChannel.EventSink
//import io.flutter.plugin.common.MethodCall
//import io.flutter.plugin.common.MethodChannel
//import io.flutter.plugin.common.MethodChannel.MethodCallHandler
//import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
//import java.util.*
//
//class FlutterBluePlusPlugin : FlutterPlugin, MethodCallHandler, RequestPermissionsResultListener, ActivityAware {
//  private val initializationLock = Any()
//  private val tearDownLock = Any()
//  private var context: Context? = null
//  private var channel: MethodChannel? = null
//  private var stateChannel: EventChannel? = null
//  private var mBluetoothManager: BluetoothManager? = null
//  private var mBluetoothAdapter: BluetoothAdapter? = null
//  private var pluginBinding: FlutterPluginBinding? = null
//  private var activityBinding: ActivityPluginBinding? = null
//  private val mDevices: MutableMap<String, BluetoothDeviceCache> = HashMap()
//  private var logLevel = LogLevel.EMERGENCY
//
//  private interface OperationOnPermission {
//    fun op(granted: Boolean, permission: String?)
//  }
//
//  private var lastEventId = 1452
//  private val operationsOnPermission: MutableMap<Int, OperationOnPermission> = HashMap()
//  private val macDeviceScanned = ArrayList<String>()
//  private var allowDuplicates = false
//  override fun onAttachedToEngine(flutterPluginBinding: FlutterPluginBinding) {
//    Log.d(TAG, "onAttachedToEngine")
//    pluginBinding = flutterPluginBinding
//    setup(pluginBinding!!.binaryMessenger,
//            pluginBinding!!.applicationContext as Application)
//  }
//
//  override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
//    Log.d(TAG, "onDetachedFromEngine")
//    pluginBinding = null
//    tearDown()
//  }
//
//  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
//    Log.d(TAG, "onAttachedToActivity")
//    activityBinding = binding
//    activityBinding!!.addRequestPermissionsResultListener(this)
//  }
//
//  override fun onDetachedFromActivityForConfigChanges() {
//    Log.d(TAG, "onDetachedFromActivityForConfigChanges")
//    onDetachedFromActivity()
//  }
//
//  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
//    Log.d(TAG, "onReattachedToActivityForConfigChanges")
//    onAttachedToActivity(binding)
//  }
//
//  override fun onDetachedFromActivity() {
//    Log.d(TAG, "onDetachedFromActivity")
//    activityBinding!!.removeRequestPermissionsResultListener(this)
//    activityBinding = null
//  }
//
//  private fun setup(
//          messenger: BinaryMessenger,
//          application: Application) {
//    synchronized(initializationLock) {
//      Log.d(TAG, "setup")
//      context = application
//      channel = MethodChannel(messenger, NAMESPACE + "/methods")
//      channel!!.setMethodCallHandler(this)
//      stateChannel = EventChannel(messenger, NAMESPACE + "/state")
//      stateChannel!!.setStreamHandler(stateHandler)
//      mBluetoothManager = application.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
//      mBluetoothAdapter = mBluetoothManager!!.adapter
//    }
//  }
//
//  private fun tearDown() {
//    synchronized(tearDownLock) {
//      Log.d(TAG, "teardown")
//      context = null
//      channel!!.setMethodCallHandler(null)
//      channel = null
//      stateChannel!!.setStreamHandler(null)
//      stateChannel = null
//      mBluetoothAdapter = null
//      mBluetoothManager = null
//    }
//  }
//
//  override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray): Boolean {
//    val operation = operationsOnPermission[requestCode]
//    if (operation != null && grantResults.size > 0) {
//      operation.op(grantResults[0] == PackageManager.PERMISSION_GRANTED, permissions[0])
//      return true
//    }
//    return false
//  }
//
//  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
//    if (mBluetoothAdapter == null && "isAvailable" != call.method) {
//      result.error("bluetooth_unavailable", "the device does not have bluetooth", null)
//      return
//    }
//    when (call.method) {
//      "setLogLevel" -> {
//        val logLevelIndex = call.arguments as Int
//        logLevel = LogLevel.values()[logLevelIndex]
//        result.success(null)
//      }
//      "state" -> {
//        val p: Protos.BluetoothState.Builder = Protos.BluetoothState.newBuilder()
//        try {
//          when (mBluetoothAdapter!!.state) {
//            BluetoothAdapter.STATE_OFF -> p.setState(Protos.BluetoothState.State.OFF)
//            BluetoothAdapter.STATE_ON -> p.setState(Protos.BluetoothState.State.ON)
//            BluetoothAdapter.STATE_TURNING_OFF -> p.setState(Protos.BluetoothState.State.TURNING_OFF)
//            BluetoothAdapter.STATE_TURNING_ON -> p.setState(Protos.BluetoothState.State.TURNING_ON)
//            else -> p.setState(Protos.BluetoothState.State.UNKNOWN)
//          }
//        } catch (e: SecurityException) {
//          p.setState(Protos.BluetoothState.State.UNAUTHORIZED)
//        }
//        result.success(p.build().toByteArray())
//      }
//      "isAvailable" -> {
//        result.success(mBluetoothAdapter != null)
//      }
//      "isOn" -> {
//        result.success(mBluetoothAdapter!!.isEnabled)
//      }
//      "turnOn" -> {
//        if (!mBluetoothAdapter!!.isEnabled) {
//          result.success(mBluetoothAdapter!!.enable())
//        }
//      }
//      "turnOff" -> {
//        if (mBluetoothAdapter!!.isEnabled) {
//          result.success(mBluetoothAdapter!!.disable())
//        }
//      }
//      "startScan" -> {
//        ensurePermissionBeforeAction(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Manifest.permission.BLUETOOTH_SCAN else Manifest.permission.ACCESS_FINE_LOCATION, OperationOnPermission { granted: Boolean, permission: String? ->
//          if (granted) startScan(call, result) else result.error(
//                  "no_permissions", String.format("flutter_blue plugin requires %s for scanning", permission), null)
//        })
//      }
//      "stopScan" -> {
//        stopScan()
//        result.success(null)
//      }
//      "getConnectedDevices" -> {
//        ensurePermissionBeforeAction(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Manifest.permission.BLUETOOTH_CONNECT else null, OperationOnPermission { granted: Boolean, permission: String? ->
//          if (!granted) {
//            result.error(
//                    "no_permissions", String.format("flutter_blue plugin requires %s for obtaining connected devices", permission), null)
//            return@ensurePermissionBeforeAction
//          }
//          val devices = mBluetoothManager!!.getConnectedDevices(BluetoothProfile.GATT)
//          val p: Protos.ConnectedDevicesResponse.Builder = Protos.ConnectedDevicesResponse.newBuilder()
//          for (d in devices) {
//            p.addDevices(ProtoMaker.from(d))
//          }
//          result.success(p.build().toByteArray())
//          log(LogLevel.EMERGENCY, "mDevices size: " + mDevices.size)
//        })
//      }
//      "getBondedDevices" -> {
//        val bondedDevices = mBluetoothAdapter!!.bondedDevices
//        val p: Protos.ConnectedDevicesResponse.Builder = Protos.ConnectedDevicesResponse.newBuilder()
//        for (d in bondedDevices) {
//          p.addDevices(ProtoMaker.from(d))
//        }
//        result.success(p.build().toByteArray())
//        log(LogLevel.EMERGENCY, "mDevices size: " + mDevices.size)
//      }
//      "connect" -> {
//        ensurePermissionBeforeAction(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Manifest.permission.BLUETOOTH_CONNECT else null, OperationOnPermission { granted: Boolean, permission: String? ->
//          if (!granted) {
//            result.error(
//                    "no_permissions", String.format("flutter_blue plugin requires %s for new connection", permission), null)
//            return@ensurePermissionBeforeAction
//          }
//          val data = call.arguments<ByteArray>()
//          val options: Protos.ConnectRequest
//          options = try {
//            Protos.ConnectRequest.newBuilder().mergeFrom(data).build()
//          } catch (e: InvalidProtocolBufferException) {
//            result.error("RuntimeException", e.getMessage(), e)
//            return@ensurePermissionBeforeAction
//          }
//          val deviceId: String = options.getRemoteId()
//          val device = mBluetoothAdapter!!.getRemoteDevice(deviceId)
//          val isConnected = mBluetoothManager!!.getConnectedDevices(BluetoothProfile.GATT).contains(device)
//
//          // If device is already connected, return error
//          if (mDevices.containsKey(deviceId) && isConnected) {
//            result.error("already_connected", "connection with device already exists", null)
//            return@ensurePermissionBeforeAction
//          }
//
//          // If device was connected to previously but is now disconnected, attempt a reconnect
//          val bluetoothDeviceCache = mDevices[deviceId]
//          if (bluetoothDeviceCache != null && !isConnected) {
//            if (bluetoothDeviceCache.gatt!!.connect()) {
//              result.success(null)
//            } else {
//              result.error("reconnect_error", "error when reconnecting to device", null)
//            }
//            return@ensurePermissionBeforeAction
//          }
//
//          // New request, connect and add gattServer to Map
//          val gattServer: BluetoothGatt
//          gattServer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
//            device.connectGatt(context, options.getAndroidAutoConnect(), mGattCallback, BluetoothDevice.TRANSPORT_LE)
//          } else {
//            device.connectGatt(context, options.getAndroidAutoConnect(), mGattCallback)
//          }
//          mDevices[deviceId] = BluetoothDeviceCache(gattServer)
//          result.success(null)
//        })
//      }
//      "disconnect" -> {
//        val deviceId = call.arguments as String
//        val device = mBluetoothAdapter!!.getRemoteDevice(deviceId)
//        val state = mBluetoothManager!!.getConnectionState(device, BluetoothProfile.GATT)
//        val cache = mDevices.remove(deviceId)
//        if (cache != null) {
//          val gattServer = cache.gatt
//          gattServer!!.disconnect()
//          if (state == BluetoothProfile.STATE_DISCONNECTED) {
//            gattServer.close()
//          }
//        }
//        result.success(null)
//      }
//      "deviceState" -> {
//        val deviceId = call.arguments as String
//        val device = mBluetoothAdapter!!.getRemoteDevice(deviceId)
//        val state = mBluetoothManager!!.getConnectionState(device, BluetoothProfile.GATT)
//        try {
//          result.success(ProtoMaker.from(device, state).toByteArray())
//        } catch (e: Exception) {
//          result.error("device_state_error", e.message, e)
//        }
//      }
//      "discoverServices" -> {
//        val deviceId = call.arguments as String
//        try {
//          val gatt = locateGatt(deviceId)
//          if (gatt!!.discoverServices()) {
//            result.success(null)
//          } else {
//            result.error("discover_services_error", "unknown reason", null)
//          }
//        } catch (e: Exception) {
//          result.error("discover_services_error", e.message, e)
//        }
//      }
//      "services" -> {
//        val deviceId = call.arguments as String
//        try {
//          val gatt = locateGatt(deviceId)
//          val p: Protos.DiscoverServicesResult.Builder = Protos.DiscoverServicesResult.newBuilder()
//          p.setRemoteId(deviceId)
//          for (s in gatt!!.services) {
//            p.addServices(ProtoMaker.from(gatt.device, s, gatt))
//          }
//          result.success(p.build().toByteArray())
//        } catch (e: Exception) {
//          result.error("get_services_error", e.message, e)
//        }
//      }
//      "readCharacteristic" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.ReadCharacteristicRequest
//        request = try {
//          Protos.ReadCharacteristicRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gattServer: BluetoothGatt?
//        val characteristic: BluetoothGattCharacteristic
//        try {
//          gattServer = locateGatt(request.getRemoteId())
//          characteristic = locateCharacteristic(gattServer, request.getServiceUuid(), request.getSecondaryServiceUuid(), request.getCharacteristicUuid())
//        } catch (e: Exception) {
//          result.error("read_characteristic_error", e.message, null)
//          return
//        }
//        if (gattServer!!.readCharacteristic(characteristic)) {
//          result.success(null)
//        } else {
//          result.error("read_characteristic_error", "unknown reason, may occur if readCharacteristic was called before last read finished.", null)
//        }
//      }
//      "readDescriptor" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.ReadDescriptorRequest
//        request = try {
//          Protos.ReadDescriptorRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gattServer: BluetoothGatt?
//        val characteristic: BluetoothGattCharacteristic
//        val descriptor: BluetoothGattDescriptor
//        try {
//          gattServer = locateGatt(request.getRemoteId())
//          characteristic = locateCharacteristic(gattServer, request.getServiceUuid(), request.getSecondaryServiceUuid(), request.getCharacteristicUuid())
//          descriptor = locateDescriptor(characteristic, request.getDescriptorUuid())
//        } catch (e: Exception) {
//          result.error("read_descriptor_error", e.message, null)
//          return
//        }
//        if (gattServer!!.readDescriptor(descriptor)) {
//          result.success(null)
//        } else {
//          result.error("read_descriptor_error", "unknown reason, may occur if readDescriptor was called before last read finished.", null)
//        }
//      }
//      "writeCharacteristic" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.WriteCharacteristicRequest
//        request = try {
//          Protos.WriteCharacteristicRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gattServer: BluetoothGatt?
//        val characteristic: BluetoothGattCharacteristic
//        try {
//          gattServer = locateGatt(request.getRemoteId())
//          characteristic = locateCharacteristic(gattServer, request.getServiceUuid(), request.getSecondaryServiceUuid(), request.getCharacteristicUuid())
//        } catch (e: Exception) {
//          result.error("write_characteristic_error", e.message, null)
//          return
//        }
//
//        // Set characteristic to new value
//        if (!characteristic.setValue(request.getValue().toByteArray())) {
//          result.error("write_characteristic_error", "could not set the local value of characteristic", null)
//        }
//
//        // Apply the correct write type
//        if (request.getWriteType() === Protos.WriteCharacteristicRequest.WriteType.WITHOUT_RESPONSE) {
//          characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
//        } else {
//          characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
//        }
//        if (!gattServer!!.writeCharacteristic(characteristic)) {
//          result.error("write_characteristic_error", "writeCharacteristic failed", null)
//          return
//        }
//        result.success(null)
//      }
//      "writeDescriptor" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.WriteDescriptorRequest
//        request = try {
//          Protos.WriteDescriptorRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gattServer: BluetoothGatt?
//        val characteristic: BluetoothGattCharacteristic
//        val descriptor: BluetoothGattDescriptor
//        try {
//          gattServer = locateGatt(request.getRemoteId())
//          characteristic = locateCharacteristic(gattServer, request.getServiceUuid(), request.getSecondaryServiceUuid(), request.getCharacteristicUuid())
//          descriptor = locateDescriptor(characteristic, request.getDescriptorUuid())
//        } catch (e: Exception) {
//          result.error("write_descriptor_error", e.message, null)
//          return
//        }
//
//        // Set descriptor to new value
//        if (!descriptor.setValue(request.getValue().toByteArray())) {
//          result.error("write_descriptor_error", "could not set the local value for descriptor", null)
//        }
//        if (!gattServer!!.writeDescriptor(descriptor)) {
//          result.error("write_descriptor_error", "writeCharacteristic failed", null)
//          return
//        }
//        result.success(null)
//      }
//      "setNotification" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.SetNotificationRequest
//        request = try {
//          Protos.SetNotificationRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gattServer: BluetoothGatt?
//        val characteristic: BluetoothGattCharacteristic
//        val cccDescriptor: BluetoothGattDescriptor?
//        try {
//          gattServer = locateGatt(request.getRemoteId())
//          characteristic = locateCharacteristic(gattServer, request.getServiceUuid(), request.getSecondaryServiceUuid(), request.getCharacteristicUuid())
//          cccDescriptor = characteristic.getDescriptor(CCCD_ID)
//          if (cccDescriptor == null) {
//            //Some devices - including the widely used Bluno do not actually set the CCCD_ID.
//            //thus setNotifications works perfectly (tested on Bluno) without cccDescriptor
//            log(LogLevel.INFO, "could not locate CCCD descriptor for characteristic: " + characteristic.uuid.toString())
//          }
//        } catch (e: Exception) {
//          result.error("set_notification_error", e.message, null)
//          return
//        }
//        var value: ByteArray? = null
//        if (request.getEnable()) {
//          val canNotify = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY > 0
//          val canIndicate = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE > 0
//          if (!canIndicate && !canNotify) {
//            result.error("set_notification_error", "the characteristic cannot notify or indicate", null)
//            return
//          }
//          if (canIndicate) {
//            value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
//          }
//          if (canNotify) {
//            value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
//          }
//        } else {
//          value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
//        }
//        if (!gattServer!!.setCharacteristicNotification(characteristic, request.getEnable())) {
//          result.error("set_notification_error", "could not set characteristic notifications to :" + request.getEnable(), null)
//          return
//        }
//        if (cccDescriptor != null) {
//          if (!cccDescriptor.setValue(value)) {
//            result.error("set_notification_error", "error when setting the descriptor value to: " + Arrays.toString(value), null)
//            return
//          }
//          if (!gattServer.writeDescriptor(cccDescriptor)) {
//            result.error("set_notification_error", "error when writing the descriptor", null)
//            return
//          }
//        }
//        result.success(null)
//      }
//      "mtu" -> {
//        val deviceId = call.arguments as String
//        val cache = mDevices[deviceId]
//        if (cache != null) {
//          val p: Protos.MtuSizeResponse.Builder = Protos.MtuSizeResponse.newBuilder()
//          p.setRemoteId(deviceId)
//          p.setMtu(cache.mtu)
//          result.success(p.build().toByteArray())
//        } else {
//          result.error("mtu", "no instance of BluetoothGatt, have you connected first?", null)
//        }
//      }
//      "requestMtu" -> {
//        val data = call.arguments<ByteArray>()
//        val request: Protos.MtuSizeRequest
//        request = try {
//          Protos.MtuSizeRequest.newBuilder().mergeFrom(data).build()
//        } catch (e: InvalidProtocolBufferException) {
//          result.error("RuntimeException", e.getMessage(), e)
//          break
//        }
//        val gatt: BluetoothGatt?
//        try {
//          gatt = locateGatt(request.getRemoteId())
//          val mtu: Int = request.getMtu()
//          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
//            if (gatt!!.requestMtu(mtu)) {
//              result.success(null)
//            } else {
//              result.error("requestMtu", "gatt.requestMtu returned false", null)
//            }
//          } else {
//            result.error("requestMtu", "Only supported on devices >= API 21 (Lollipop). This device == " + Build.VERSION.SDK_INT, null)
//          }
//        } catch (e: Exception) {
//          result.error("requestMtu", e.message, e)
//        }
//      }
//      else -> {
//        result.notImplemented()
//      }
//    }
//  }
//
//  private fun ensurePermissionBeforeAction(permission: String?, operation: OperationOnPermission) {
//    if (permission != null &&
//            ContextCompat.checkSelfPermission(context!!, permission) != PackageManager.PERMISSION_GRANTED) {
//      operationsOnPermission[lastEventId] = OperationOnPermission { granted: Boolean, perm: String? ->
//        operationsOnPermission.remove(lastEventId)
//        operation.op(granted, perm)
//      }
//      ActivityCompat.requestPermissions(
//              activityBinding!!.activity, arrayOf(permission),
//              lastEventId)
//      lastEventId++
//    } else {
//      operation.op(true, permission)
//    }
//  }
//
//  @Throws(Exception::class)
//  private fun locateGatt(remoteId: String): BluetoothGatt? {
//    val cache = mDevices[remoteId]
//    return if (cache == null || cache.gatt == null) {
//      throw Exception("no instance of BluetoothGatt, have you connected first?")
//    } else {
//      cache.gatt
//    }
//  }
//
//  @Throws(Exception::class)
//  private fun locateCharacteristic(gattServer: BluetoothGatt?, serviceId: String, secondaryServiceId: String, characteristicId: String): BluetoothGattCharacteristic {
//    val primaryService = gattServer!!.getService(UUID.fromString(serviceId))
//            ?: throw Exception("service ($serviceId) could not be located on the device")
//    var secondaryService: BluetoothGattService? = null
//    if (secondaryServiceId.length > 0) {
//      for (s in primaryService.includedServices) {
//        if (s.uuid == UUID.fromString(secondaryServiceId)) {
//          secondaryService = s
//        }
//      }
//      if (secondaryService == null) {
//        throw Exception("secondary service ($secondaryServiceId) could not be located on the device")
//      }
//    }
//    val service = secondaryService ?: primaryService
//    return service.getCharacteristic(UUID.fromString(characteristicId))
//            ?: throw Exception("characteristic (" + characteristicId + ") could not be located in the service (" + service.uuid.toString() + ")")
//  }
//
//  @Throws(Exception::class)
//  private fun locateDescriptor(characteristic: BluetoothGattCharacteristic, descriptorId: String): BluetoothGattDescriptor {
//    return characteristic.getDescriptor(UUID.fromString(descriptorId))
//            ?: throw Exception("descriptor (" + descriptorId + ") could not be located in the characteristic (" + characteristic.uuid.toString() + ")")
//  }
//
//  private val stateHandler: EventChannel.StreamHandler = object : EventChannel.StreamHandler {
//    private var sink: EventSink? = null
//    private val mReceiver: BroadcastReceiver = object : BroadcastReceiver() {
//      override fun onReceive(context: Context, intent: Intent) {
//        val action = intent.action
//        if (BluetoothAdapter.ACTION_STATE_CHANGED == action) {
//          val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE,
//                  BluetoothAdapter.ERROR)
//          when (state) {
//            BluetoothAdapter.STATE_OFF -> sink!!.success(Protos.BluetoothState.newBuilder().setState(Protos.BluetoothState.State.OFF).build().toByteArray())
//            BluetoothAdapter.STATE_TURNING_OFF -> sink!!.success(Protos.BluetoothState.newBuilder().setState(Protos.BluetoothState.State.TURNING_OFF).build().toByteArray())
//            BluetoothAdapter.STATE_ON -> sink!!.success(Protos.BluetoothState.newBuilder().setState(Protos.BluetoothState.State.ON).build().toByteArray())
//            BluetoothAdapter.STATE_TURNING_ON -> sink!!.success(Protos.BluetoothState.newBuilder().setState(Protos.BluetoothState.State.TURNING_ON).build().toByteArray())
//          }
//        }
//      }
//    }
//
//    override fun onListen(o: Any, eventSink: EventSink) {
//      sink = eventSink
//      val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
//      context!!.registerReceiver(mReceiver, filter)
//    }
//
//    override fun onCancel(o: Any) {
//      sink = null
//      context!!.unregisterReceiver(mReceiver)
//    }
//  }
//
//  private fun startScan(call: MethodCall, result: MethodChannel.Result) {
//    val data = call.arguments<ByteArray>()
//    val settings: ScanSettings
//    try {
//      settings = Protos.ScanSettings.newBuilder().mergeFrom(data).build()
//      allowDuplicates = settings.getAllowDuplicates()
//      macDeviceScanned.clear()
//      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
//        startScan21(settings)
//      } else {
//        startScan18(settings)
//      }
//      result.success(null)
//    } catch (e: Exception) {
//      result.error("startScan", e.message, e)
//    }
//  }
//
//  private fun stopScan() {
//    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
//      stopScan21()
//    } else {
//      stopScan18()
//    }
//  }
//
//  @get:TargetApi(21)
//  private var scanCallback21: ScanCallback? = null
//    private get() {
//      if (field == null) {
//        field = object : ScanCallback() {
//          override fun onScanResult(callbackType: Int, result: ScanResult) {
//            super.onScanResult(callbackType, result)
//            if (result != null) {
//              if (!allowDuplicates && result.device != null && result.device.address != null) {
//                if (macDeviceScanned.contains(result.device.address)) {
//                  return
//                }
//                macDeviceScanned.add(result.device.address)
//              }
//              val scanResult: Protos.ScanResult = ProtoMaker.from(result.device, result)
//              invokeMethodUIThread("ScanResult", scanResult.toByteArray())
//            }
//          }
//
//          override fun onBatchScanResults(results: List<ScanResult>) {
//            super.onBatchScanResults(results)
//          }
//
//          override fun onScanFailed(errorCode: Int) {
//            super.onScanFailed(errorCode)
//          }
//        }
//      }
//      return field
//    }
//
//  @TargetApi(21)
//  @Throws(IllegalStateException::class)
//  private fun startScan21(proto: ScanSettings) {
//    val scanner = mBluetoothAdapter!!.bluetoothLeScanner
//            ?: throw IllegalStateException("getBluetoothLeScanner() is null. Is the Adapter on?")
//    val scanMode: Int = proto.getAndroidScanMode()
//    val count: Int = proto.getServiceUuidsCount()
//    val filters: MutableList<ScanFilter> = ArrayList(count)
//    for (i in 0 until count) {
//      val uuid: String = proto.getServiceUuids(i)
//      val f = ScanFilter.Builder().setServiceUuid(ParcelUuid.fromString(uuid)).build()
//      filters.add(f)
//    }
//    val settings = ScanSettings.Builder().setScanMode(scanMode).build()
//    scanner.startScan(filters, settings, scanCallback21)
//  }
//
//  @TargetApi(21)
//  private fun stopScan21() {
//    val scanner = mBluetoothAdapter!!.bluetoothLeScanner
//    scanner?.stopScan(scanCallback21)
//  }
//
//  private var scanCallback18: LeScanCallback? = null
//    private get() {
//      if (field == null) {
//        field = label@ LeScanCallback { bluetoothDevice: BluetoothDevice?, rssi: Int, scanRecord: ByteArray? ->
//          if (!allowDuplicates && bluetoothDevice != null && bluetoothDevice.address != null) {
//            if (macDeviceScanned.contains(bluetoothDevice.address)) return@label
//            macDeviceScanned.add(bluetoothDevice.address)
//          }
//          val scanResult: Protos.ScanResult = ProtoMaker.from(bluetoothDevice, scanRecord, rssi)
//          invokeMethodUIThread("ScanResult", scanResult.toByteArray())
//        }
//      }
//      return field
//    }
//
//  @Throws(IllegalStateException::class)
//  private fun startScan18(proto: ScanSettings) {
//    val serviceUuids: List<String> = proto.getServiceUuidsList()
//    val uuids = arrayOfNulls<UUID>(serviceUuids.size)
//    for (i in serviceUuids.indices) {
//      uuids[i] = UUID.fromString(serviceUuids[i])
//    }
//    val success = mBluetoothAdapter!!.startLeScan(uuids, scanCallback18)
//    check(success) { "getBluetoothLeScanner() is null. Is the Adapter on?" }
//  }
//
//  private fun stopScan18() {
//    mBluetoothAdapter!!.stopLeScan(scanCallback18)
//  }
//
//  private val mGattCallback: BluetoothGattCallback = object : BluetoothGattCallback() {
//    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
//      log(LogLevel.DEBUG, "[onConnectionStateChange] status: $status newState: $newState")
//      if (newState == BluetoothProfile.STATE_DISCONNECTED) {
//        if (!mDevices.containsKey(gatt.device.address)) {
//          gatt.close()
//        }
//      }
//      invokeMethodUIThread("DeviceState", ProtoMaker.from(gatt.device, newState).toByteArray())
//    }
//
//    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
//      log(LogLevel.DEBUG, "[onServicesDiscovered] count: " + gatt.services.size + " status: " + status)
//      val p: Protos.DiscoverServicesResult.Builder = Protos.DiscoverServicesResult.newBuilder()
//      p.setRemoteId(gatt.device.address)
//      for (s in gatt.services) {
//        p.addServices(ProtoMaker.from(gatt.device, s, gatt))
//      }
//      invokeMethodUIThread("DiscoverServicesResult", p.build().toByteArray())
//    }
//
//    override fun onCharacteristicRead(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
//      log(LogLevel.DEBUG, "[onCharacteristicRead] uuid: " + characteristic.uuid.toString() + " status: " + status)
//      val p: Protos.ReadCharacteristicResponse.Builder = Protos.ReadCharacteristicResponse.newBuilder()
//      p.setRemoteId(gatt.device.address)
//      p.setCharacteristic(ProtoMaker.from(gatt.device, characteristic, gatt))
//      invokeMethodUIThread("ReadCharacteristicResponse", p.build().toByteArray())
//    }
//
//    override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
//      log(LogLevel.DEBUG, "[onCharacteristicWrite] uuid: " + characteristic.uuid.toString() + " status: " + status)
//      val request: Protos.WriteCharacteristicRequest.Builder = Protos.WriteCharacteristicRequest.newBuilder()
//      request.setRemoteId(gatt.device.address)
//      request.setCharacteristicUuid(characteristic.uuid.toString())
//      request.setServiceUuid(characteristic.service.uuid.toString())
//      val p: Protos.WriteCharacteristicResponse.Builder = Protos.WriteCharacteristicResponse.newBuilder()
//      p.setRequest(request)
//      p.setSuccess(status == BluetoothGatt.GATT_SUCCESS)
//      invokeMethodUIThread("WriteCharacteristicResponse", p.build().toByteArray())
//    }
//
//    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
//      log(LogLevel.DEBUG, "[onCharacteristicChanged] uuid: " + characteristic.uuid.toString())
//      val p: Protos.OnCharacteristicChanged.Builder = Protos.OnCharacteristicChanged.newBuilder()
//      p.setRemoteId(gatt.device.address)
//      p.setCharacteristic(ProtoMaker.from(gatt.device, characteristic, gatt))
//      invokeMethodUIThread("OnCharacteristicChanged", p.build().toByteArray())
//    }
//
//    override fun onDescriptorRead(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
//      log(LogLevel.DEBUG, "[onDescriptorRead] uuid: " + descriptor.uuid.toString() + " status: " + status)
//      // Rebuild the ReadAttributeRequest and send back along with response
//      val q: Protos.ReadDescriptorRequest.Builder = Protos.ReadDescriptorRequest.newBuilder()
//      q.setRemoteId(gatt.device.address)
//      q.setCharacteristicUuid(descriptor.characteristic.uuid.toString())
//      q.setDescriptorUuid(descriptor.uuid.toString())
//      if (descriptor.characteristic.service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY) {
//        q.setServiceUuid(descriptor.characteristic.service.uuid.toString())
//      } else {
//        // Reverse search to find service
//        for (s in gatt.services) {
//          for (ss in s.includedServices) {
//            if (ss.uuid == descriptor.characteristic.service.uuid) {
//              q.setServiceUuid(s.uuid.toString())
//              q.setSecondaryServiceUuid(ss.uuid.toString())
//              break
//            }
//          }
//        }
//      }
//      val p: Protos.ReadDescriptorResponse.Builder = Protos.ReadDescriptorResponse.newBuilder()
//      p.setRequest(q)
//      p.setValue(ByteString.copyFrom(descriptor.value))
//      invokeMethodUIThread("ReadDescriptorResponse", p.build().toByteArray())
//    }
//
//    override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
//      log(LogLevel.DEBUG, "[onDescriptorWrite] uuid: " + descriptor.uuid.toString() + " status: " + status)
//      val request: Protos.WriteDescriptorRequest.Builder = Protos.WriteDescriptorRequest.newBuilder()
//      request.setRemoteId(gatt.device.address)
//      request.setDescriptorUuid(descriptor.uuid.toString())
//      request.setCharacteristicUuid(descriptor.characteristic.uuid.toString())
//      request.setServiceUuid(descriptor.characteristic.service.uuid.toString())
//      val p: Protos.WriteDescriptorResponse.Builder = Protos.WriteDescriptorResponse.newBuilder()
//      p.setRequest(request)
//      p.setSuccess(status == BluetoothGatt.GATT_SUCCESS)
//      invokeMethodUIThread("WriteDescriptorResponse", p.build().toByteArray())
//      if (descriptor.uuid.compareTo(CCCD_ID) == 0) {
//        // SetNotificationResponse
//        val q: Protos.SetNotificationResponse.Builder = Protos.SetNotificationResponse.newBuilder()
//        q.setRemoteId(gatt.device.address)
//        q.setCharacteristic(ProtoMaker.from(gatt.device, descriptor.characteristic, gatt))
//        invokeMethodUIThread("SetNotificationResponse", q.build().toByteArray())
//      }
//    }
//
//    override fun onReliableWriteCompleted(gatt: BluetoothGatt, status: Int) {
//      log(LogLevel.DEBUG, "[onReliableWriteCompleted] status: $status")
//    }
//
//    override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
//      log(LogLevel.DEBUG, "[onReadRemoteRssi] rssi: $rssi status: $status")
//    }
//
//    override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
//      log(LogLevel.DEBUG, "[onMtuChanged] mtu: $mtu status: $status")
//      if (status == BluetoothGatt.GATT_SUCCESS) {
//        if (mDevices.containsKey(gatt.device.address)) {
//          val cache = mDevices[gatt.device.address]
//          if (cache != null) {
//            cache.mtu = mtu
//          }
//          val p: Protos.MtuSizeResponse.Builder = Protos.MtuSizeResponse.newBuilder()
//          p.setRemoteId(gatt.device.address)
//          p.setMtu(mtu)
//          invokeMethodUIThread("MtuSize", p.build().toByteArray())
//        }
//      }
//    }
//  }
//
//  private fun log(level: LogLevel, message: String) {
//    if (level.ordinal <= logLevel.ordinal) {
//      Log.d(TAG, message)
//    }
//  }
//
//  private fun invokeMethodUIThread(name: String, byteArray: ByteArray) {
//    Handler(Looper.getMainLooper()).post {
//      synchronized(tearDownLock) {
//        //Could already be teared down at this moment
//        if (channel != null) {
//          channel!!.invokeMethod(name, byteArray)
//        } else {
//          Log.w(TAG, "Tried to call $name on closed channel")
//        }
//      }
//    }
//  }
//
//  internal enum class LogLevel {
//    EMERGENCY, ALERT, CRITICAL, ERROR, WARNING, NOTICE, INFO, DEBUG
//  }
//
//  // BluetoothDeviceCache contains any other cached information not stored in Android Bluetooth API
//  // but still needed Dart side.
//  internal class BluetoothDeviceCache(val gatt: BluetoothGatt?) {
//    var mtu = 20
//  }
//
//  companion object {
//    private const val TAG = "FlutterBluePlugin"
//    private const val NAMESPACE = "flutter_blue_plus"
//    private val CCCD_ID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
//  }
//}