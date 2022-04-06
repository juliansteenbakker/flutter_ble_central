//package dev.steenbakker.flutter_ble_central
//
//import com.polidea.multiplatformbleadapter.AdvertisementData
//import com.polidea.multiplatformbleadapter.ScanResult
//import com.polidea.multiplatformbleadapter.utils.Base64Converter
//import com.polidea.multiplatformbleadapter.utils.UUIDConverter
//import org.json.JSONArray
//import org.json.JSONException
//import org.json.JSONObject
//import java.util.*
//
//
//class ScanResultJsonConverter : JsonConverter<ScanResult?> {
//    private interface Metadata {
//        companion object {
//            const val ID = "id"
//            const val NAME = "name"
//            const val RSSI = "rssi"
//            const val MTU = "mtu"
//            const val MANUFACTURER_DATA = "manufacturerData"
//            const val SERVICE_DATA = "serviceData"
//            const val SERVICE_UUIDS = "serviceUUIDs"
//            const val LOCAL_NAME = "localName"
//            const val TX_POWER_LEVEL = "txPowerLevel"
//            const val SOLICITED_SERVICE_UUIDS = "solicitedServiceUUIDs"
//            const val IS_CONNECTABLE = "isConnectable"
//            const val OVERFLOW_SERVICE_UUIDS = "overflowServiceUUIDs"
//        }
//    }
//
//    fun toJson(value: ScanResult): String? {
//        return try {
//            val root = JSONObject()
//            root.put(Metadata.ID, if (value.getDeviceId() != null) value.getDeviceId() else JSONObject.NULL)
//            root.put(Metadata.NAME, if (value.getDeviceName() != null) value.getDeviceName() else JSONObject.NULL)
//            root.put(Metadata.RSSI, value.getRssi())
//            root.put(Metadata.MTU, value.getMtu())
//            if (value.getAdvertisementData() != null) {
//                serializeAdvertisementData(root, value.getAdvertisementData())
//            }
//            root.put(Metadata.IS_CONNECTABLE, JSONObject.NULL)
//            root.put(Metadata.OVERFLOW_SERVICE_UUIDS, JSONObject.NULL)
//            root.toString()
//        } catch (jsonException: JSONException) {
//            jsonException.printStackTrace()
//            null
//        }
//    }
//
//    @Throws(JSONException::class)
//    private fun serializeAdvertisementData(root: JSONObject,
//                                           advertisementData: AdvertisementData) {
//        serializeManufacturerData(root, advertisementData)
//        serializeServiceData(root, advertisementData)
//        serializeServiceUuids(root, advertisementData)
//        serializeSolicitedServiceUuids(root, advertisementData)
//        root.put(Metadata.LOCAL_NAME, if (advertisementData.getLocalName() != null) advertisementData.getLocalName() else JSONObject.NULL)
//        root.put(Metadata.TX_POWER_LEVEL, if (advertisementData.getTxPowerLevel() != null) advertisementData.getTxPowerLevel() else JSONObject.NULL)
//    }
//
//    @Throws(JSONException::class)
//    private fun serializeManufacturerData(target: JSONObject,
//                                          advertisementData: AdvertisementData) {
//        target.put(Metadata.MANUFACTURER_DATA, if (advertisementData.getManufacturerData() != null) Base64Converter.encode(advertisementData.getManufacturerData()) else JSONObject.NULL)
//    }
//
//    @Throws(JSONException::class)
//    private fun serializeServiceData(target: JSONObject,
//                                     advertisementData: AdvertisementData) {
//        if (advertisementData.getServiceData() != null && !advertisementData.getServiceData().isEmpty()) {
//            val serviceData: MutableMap<String?, String?> = HashMap()
//            for ((key, value): Map.Entry<UUID, ByteArray> in advertisementData.getServiceData().entrySet()) {
//                serviceData[UUIDConverter.fromUUID(key)] = Base64Converter.encode(value)
//            }
//            target.put(Metadata.SERVICE_DATA, JSONObject(serviceData))
//        } else {
//            target.put(Metadata.SERVICE_DATA, JSONObject.NULL)
//        }
//    }
//
//    @Throws(JSONException::class)
//    private fun serializeServiceUuids(target: JSONObject,
//                                      advertisementData: AdvertisementData) {
//        if (advertisementData.getServiceUUIDs() != null && !advertisementData.getServiceUUIDs().isEmpty()) {
//            val serviceUuids: MutableList<String?> = ArrayList()
//            for (uuid in advertisementData.getServiceUUIDs()) {
//                serviceUuids.add(UUIDConverter.fromUUID(uuid))
//            }
//            target.put(Metadata.SERVICE_UUIDS, JSONArray(serviceUuids))
//        } else {
//            target.put(Metadata.SERVICE_UUIDS, JSONObject.NULL)
//        }
//    }
//
//    @Throws(JSONException::class)
//    private fun serializeSolicitedServiceUuids(target: JSONObject,
//                                               advertisementData: AdvertisementData) {
//        if (advertisementData.getSolicitedServiceUUIDs() != null && !advertisementData.getSolicitedServiceUUIDs().isEmpty()) {
//            val solicitedServiceUuuids: MutableList<String?> = ArrayList()
//            for (uuid in advertisementData.getSolicitedServiceUUIDs()) {
//                solicitedServiceUuuids.add(UUIDConverter.fromUUID(uuid))
//            }
//            target.put(Metadata.SOLICITED_SERVICE_UUIDS, JSONArray(solicitedServiceUuuids))
//        } else {
//            target.put(Metadata.SOLICITED_SERVICE_UUIDS, JSONObject.NULL)
//        }
//    }
//}