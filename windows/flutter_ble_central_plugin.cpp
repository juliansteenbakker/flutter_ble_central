#include "flutter_ble_central_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>

#include <flutter/method_channel.h>
#include <flutter/basic_message_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>

#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <iomanip>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

namespace flutter_ble_central {

// static
void FlutterBleCentralPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.steenbakker.flutter_ble_central/method",
          &flutter::StandardMethodCodec::GetInstance());

auto event_scan_result =
    std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), "dev.steenbakker.flutter_ble_central/scan_result",
        &flutter::StandardMethodCodec::GetInstance());

  auto event_state_changed =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.steenbakker.flutter_ble_central/ble_state_changed",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterBleCentralPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnListen(arguments, std::move(events));
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnCancel(arguments);
      });
  event_scan_result->SetStreamHandler(std::move(handler));

  auto state_handler = std::make_unique<
      flutter::StreamHandlerFunctions<>>(
      [plugin_pointer = plugin.get()](
          const flutter::EncodableValue* arguments,
          std::unique_ptr<flutter::EventSink<>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnStateListenInternal(arguments, std::move(events));
      },
      [plugin_pointer = plugin.get()](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<flutter::StreamHandlerError<>> {
        return plugin_pointer->OnStateCancelInternal(arguments);
      });
  event_state_changed->SetStreamHandler(std::move(state_handler));

  // The GATT client streams.
  auto add_gatt_channel = [&](const char* name, auto sink_of) {
    auto channel =
        std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            registrar->messenger(), name,
            &flutter::StandardMethodCodec::GetInstance());
    channel->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<>>(
            [plugin_pointer = plugin.get(), sink_of](
                const flutter::EncodableValue*,
                std::unique_ptr<flutter::EventSink<>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<>> {
                sink_of(plugin_pointer) = std::move(events);
                return nullptr;
            },
            [plugin_pointer = plugin.get(), sink_of](const flutter::EncodableValue*)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
                sink_of(plugin_pointer) = nullptr;
                return nullptr;
            }));
    return channel;
  };

  auto event_connection_state = add_gatt_channel(
      "dev.steenbakker.flutter_ble_central/connection_state",
      [](FlutterBleCentralPlugin* p) -> auto& { return p->connection_state_sink_; });
  auto event_characteristic_value = add_gatt_channel(
      "dev.steenbakker.flutter_ble_central/characteristic_value",
      [](FlutterBleCentralPlugin* p) -> auto& { return p->characteristic_value_sink_; });
  auto event_bond_state = add_gatt_channel(
      "dev.steenbakker.flutter_ble_central/bond_state",
      [](FlutterBleCentralPlugin* p) -> auto& { return p->bond_state_sink_; });

  registrar->AddPlugin(std::move(plugin));
}

FlutterBleCentralPlugin::FlutterBleCentralPlugin() {
  InitializeAsync();
  }

FlutterBleCentralPlugin::~FlutterBleCentralPlugin() {}

winrt::fire_and_forget FlutterBleCentralPlugin::InitializeAsync() {
  try {
    auto bluetoothAdapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (bluetoothAdapter) {
      bluetoothRadio = co_await bluetoothAdapter.GetRadioAsync();
    } else {
      // Adapter unreachable via default path (e.g. disabled in Device Manager).
      // Enumerate radios directly so we can distinguish disabled from unsupported.
      auto radios = co_await Radio::GetRadiosAsync();
      for (auto const& radio : radios) {
        if (radio.Kind() == RadioKind::Bluetooth) {
          bluetoothRadio = radio;
          break;
        }
      }
    }
    if (bluetoothRadio) {
      radioStateChangedToken = bluetoothRadio.StateChanged({ this, &FlutterBleCentralPlugin::OnRadioStateChanged });
    }
  }
  catch (...) {
    bluetoothRadio = nullptr;
  }
}


// MARK: - GATT client

namespace {

// The uuid forms Dart may send, expanded onto the Bluetooth Base UUID like the
// other platforms do.
winrt::guid ParseUuid(const std::string& value) {
    std::string hex;
    for (char character : value) {
        if (character != '-') hex.push_back(character);
    }
    if (hex.size() == 4) hex = "0000" + hex + "00001000800000805F9B34FB";
    else if (hex.size() == 8) hex = hex + "00001000800000805F9B34FB";
    if (hex.size() != 32) throw std::invalid_argument("Invalid uuid: " + value);

    auto byte_at = [&](size_t index) {
        return static_cast<uint8_t>(std::stoul(hex.substr(index * 2, 2), nullptr, 16));
    };
    return winrt::guid{
        (static_cast<uint32_t>(byte_at(0)) << 24) | (static_cast<uint32_t>(byte_at(1)) << 16) |
            (static_cast<uint32_t>(byte_at(2)) << 8) | byte_at(3),
        static_cast<uint16_t>((byte_at(4) << 8) | byte_at(5)),
        static_cast<uint16_t>((byte_at(6) << 8) | byte_at(7)),
        { byte_at(8), byte_at(9), byte_at(10), byte_at(11),
          byte_at(12), byte_at(13), byte_at(14), byte_at(15) },
    };
}

// The lowercase dashed form Dart compares against.
std::string UuidToString(const winrt::guid& value) {
    std::ostringstream out;
    out << std::hex << std::setfill('0')
        << std::setw(8) << value.Data1 << '-'
        << std::setw(4) << value.Data2 << '-'
        << std::setw(4) << value.Data3 << '-'
        << std::setw(2) << static_cast<int>(value.Data4[0])
        << std::setw(2) << static_cast<int>(value.Data4[1]) << '-';
    for (size_t i = 2; i < 8; i++) {
        out << std::setw(2) << static_cast<int>(value.Data4[i]);
    }
    return out.str();
}

std::vector<uint8_t> BufferToBytes(const IBuffer& buffer) {
    auto reader = DataReader::FromBuffer(buffer);
    std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
    reader.ReadBytes(bytes);
    return bytes;
}

IBuffer BytesToBuffer(const std::vector<uint8_t>& bytes) {
    DataWriter writer;
    writer.WriteBytes(bytes);
    return writer.DetachBuffer();
}

// The properties map Dart's GattCharacteristicProperties expects.
flutter::EncodableMap PropertyMap(GattCharacteristicProperties properties) {
    auto has = [&](GattCharacteristicProperties flag) {
        return (properties & flag) != GattCharacteristicProperties::None;
    };
    return flutter::EncodableMap{
        {EncodableValue("broadcast"), EncodableValue(has(GattCharacteristicProperties::Broadcast))},
        {EncodableValue("read"), EncodableValue(has(GattCharacteristicProperties::Read))},
        {EncodableValue("writeWithoutResponse"),
            EncodableValue(has(GattCharacteristicProperties::WriteWithoutResponse))},
        {EncodableValue("write"), EncodableValue(has(GattCharacteristicProperties::Write))},
        {EncodableValue("notify"), EncodableValue(has(GattCharacteristicProperties::Notify))},
        {EncodableValue("indicate"), EncodableValue(has(GattCharacteristicProperties::Indicate))},
        {EncodableValue("authenticatedSignedWrites"),
            EncodableValue(has(GattCharacteristicProperties::AuthenticatedSignedWrites))},
        {EncodableValue("extendedProperties"),
            EncodableValue(has(GattCharacteristicProperties::ExtendedProperties))},
    };
}

}  // namespace

void FlutterBleCentralPlugin::PublishConnectionState(uint64_t address, int state) {
    if (!connection_state_sink_) return;
    connection_state_sink_->Success(EncodableValue(flutter::EncodableMap{
        {EncodableValue("address"), EncodableValue(std::to_string(address))},
        {EncodableValue("state"), EncodableValue(state)},
    }));
}

winrt::fire_and_forget FlutterBleCentralPlugin::ConnectAsync(
    uint64_t address, Result result) {
    auto lifetime = alive_;

    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    PublishConnectionState(address, 1);  // connecting

    // A coroutine cannot suspend inside a catch block, so a failure is carried
    // out of the try and reported below.
    BluetoothLEDevice device{ nullptr };
    GattSession session{ nullptr };
    const char* failure = nullptr;
    const char* code = "CONNECTION_ERROR";

    try {
        device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
        if (!device) {
            code = "UNKNOWN_PERIPHERAL";
            failure = "No device with that address";
        }
        else {
            // Windows has no connect call: asking for the services brings the
            // link up, and holding the device keeps it up.
            auto services =
                co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
            if (services.Status() != GattCommunicationStatus::Success) {
                failure = "Could not reach the device";
            }
            else {
                session =
                    co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId());
                if (session) session.MaintainConnection(true);
            }
        }
    }
    catch (...) {
        failure = "Failed to connect";
    }

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (failure) {
        PublishConnectionState(address, 0);
        result->Error(code, std::string(failure) + " (" + std::to_string(address) + ")");
        co_return;
    }

    Connection connection;
    connection.device = device;
    connection.session = session;
    connection.connection_changed_token = device.ConnectionStatusChanged(
        [this, address, lifetime](BluetoothLEDevice sender, IInspectable)
            -> winrt::fire_and_forget {
            auto connected =
                sender.ConnectionStatus() == BluetoothConnectionStatus::Connected;
            co_await ui_thread_;
            if (!lifetime->load()) co_return;
            PublishConnectionState(address, connected ? 2 : 0);
        });
    connections_[address] = std::move(connection);

    PublishConnectionState(address, 2);  // connected
    result->Success();
}

void FlutterBleCentralPlugin::Disconnect(uint64_t address) {
    auto found = connections_.find(address);
    if (found == connections_.end()) return;

    auto& connection = found->second;
    if (connection.device && connection.connection_changed_token) {
        connection.device.ConnectionStatusChanged(connection.connection_changed_token);
    }
    if (connection.session) connection.session.Close();
    // Releasing the device is what actually drops the link.
    connections_.erase(found);
    PublishConnectionState(address, 0);
}

IAsyncOperation<GattCharacteristic> FlutterBleCentralPlugin::FindCharacteristic(
    uint64_t address, std::string service_uuid, std::string characteristic_uuid) {
    auto found = connections_.find(address);
    if (found == connections_.end()) co_return nullptr;

    auto services = co_await found->second.device.GetGattServicesForUuidAsync(
        ParseUuid(service_uuid), BluetoothCacheMode::Cached);
    if (services.Status() != GattCommunicationStatus::Success ||
        services.Services().Size() == 0) {
        co_return nullptr;
    }

    auto characteristics = co_await services.Services().GetAt(0)
        .GetCharacteristicsForUuidAsync(
            ParseUuid(characteristic_uuid), BluetoothCacheMode::Cached);
    if (characteristics.Status() != GattCommunicationStatus::Success ||
        characteristics.Characteristics().Size() == 0) {
        co_return nullptr;
    }
    co_return characteristics.Characteristics().GetAt(0);
}

winrt::fire_and_forget FlutterBleCentralPlugin::DiscoverServicesAsync(
    uint64_t address, Result result) {
    auto lifetime = alive_;
    auto found = connections_.find(address);
    if (found == connections_.end()) {
        result->Error("NOT_CONNECTED", "Device is not connected");
        co_return;
    }
    auto device = found->second.device;

    flutter::EncodableList out;
    bool failed = false;
    try {
        auto services = co_await device.GetGattServicesAsync(BluetoothCacheMode::Cached);
        for (auto const& service : services.Services()) {
            flutter::EncodableList characteristic_list;
            auto characteristics =
                co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Cached);
            if (characteristics.Status() == GattCommunicationStatus::Success) {
                for (auto const& characteristic : characteristics.Characteristics()) {
                    flutter::EncodableList descriptor_list;
                    auto descriptors =
                        co_await characteristic.GetDescriptorsAsync(BluetoothCacheMode::Cached);
                    if (descriptors.Status() == GattCommunicationStatus::Success) {
                        for (auto const& descriptor : descriptors.Descriptors()) {
                            descriptor_list.push_back(EncodableValue(flutter::EncodableMap{
                                {EncodableValue("uuid"),
                                    EncodableValue(UuidToString(descriptor.Uuid()))},
                                {EncodableValue("characteristicUuid"),
                                    EncodableValue(UuidToString(characteristic.Uuid()))},
                            }));
                        }
                    }
                    characteristic_list.push_back(EncodableValue(flutter::EncodableMap{
                        {EncodableValue("uuid"),
                            EncodableValue(UuidToString(characteristic.Uuid()))},
                        {EncodableValue("serviceUuid"),
                            EncodableValue(UuidToString(service.Uuid()))},
                        {EncodableValue("properties"),
                            EncodableValue(PropertyMap(characteristic.CharacteristicProperties()))},
                        {EncodableValue("descriptors"), EncodableValue(descriptor_list)},
                    }));
                }
            }
            out.push_back(EncodableValue(flutter::EncodableMap{
                {EncodableValue("uuid"), EncodableValue(UuidToString(service.Uuid()))},
                {EncodableValue("isPrimary"), EncodableValue(true)},
                {EncodableValue("characteristics"), EncodableValue(characteristic_list)},
            }));
        }
    }
    catch (...) {
        failed = true;
    }

    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (failed) {
        result->Error("SERVICE_DISCOVERY_ERROR", "Failed to discover services");
        co_return;
    }
    result->Success(EncodableValue(out));
}

winrt::fire_and_forget FlutterBleCentralPlugin::ReadCharacteristicAsync(
    uint64_t address, std::string service, std::string characteristic, Result result) {
    auto lifetime = alive_;
    auto found = co_await FindCharacteristic(address, service, characteristic);
    if (!found) {
        co_await ui_thread_;
        if (!lifetime->load()) co_return;
        result->Error("CHARACTERISTIC_NOT_FOUND", "Characteristic " + characteristic +
            " not found. Call discoverServices first.");
        co_return;
    }

    auto read = co_await found.ReadValueAsync(BluetoothCacheMode::Uncached);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (read.Status() != GattCommunicationStatus::Success) {
        result->Error("READ_ERROR", "Read failed");
        co_return;
    }
    result->Success(EncodableValue(BufferToBytes(read.Value())));
}

winrt::fire_and_forget FlutterBleCentralPlugin::WriteCharacteristicAsync(
    uint64_t address, std::string service, std::string characteristic,
    std::vector<uint8_t> value, bool without_response, Result result) {
    auto lifetime = alive_;
    auto found = co_await FindCharacteristic(address, service, characteristic);
    if (!found) {
        co_await ui_thread_;
        if (!lifetime->load()) co_return;
        result->Error("CHARACTERISTIC_NOT_FOUND", "Characteristic " + characteristic +
            " not found. Call discoverServices first.");
        co_return;
    }

    auto status = co_await found.WriteValueWithResultAsync(
        BytesToBuffer(value),
        without_response ? GattWriteOption::WriteWithoutResponse
                         : GattWriteOption::WriteWithResponse);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (status.Status() != GattCommunicationStatus::Success) {
        result->Error("WRITE_ERROR", "Write failed");
        co_return;
    }
    result->Success();
}

winrt::fire_and_forget FlutterBleCentralPlugin::SetNotifyAsync(
    uint64_t address, std::string service, std::string characteristic,
    bool enable, Result result) {
    auto lifetime = alive_;
    auto found = co_await FindCharacteristic(address, service, characteristic);
    if (!found) {
        co_await ui_thread_;
        if (!lifetime->load()) co_return;
        result->Error("CHARACTERISTIC_NOT_FOUND", "Characteristic " + characteristic +
            " not found. Call discoverServices first.");
        co_return;
    }

    // Indicate is acknowledged and notify is not; prefer whichever the
    // characteristic offers, matching what the other platforms pick.
    auto properties = found.CharacteristicProperties();
    auto wanted = GattClientCharacteristicConfigurationDescriptorValue::None;
    if (enable) {
        wanted = (properties & GattCharacteristicProperties::Notify) !=
                     GattCharacteristicProperties::None
            ? GattClientCharacteristicConfigurationDescriptorValue::Notify
            : GattClientCharacteristicConfigurationDescriptorValue::Indicate;
    }

    auto status =
        co_await found.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(wanted);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (status.Status() != GattCommunicationStatus::Success) {
        result->Error("NOTIFICATION_ERROR", "Could not change the subscription");
        co_return;
    }

    auto connection = connections_.find(address);
    if (connection != connections_.end()) {
        auto key = service + "/" + characteristic;
        auto existing = connection->second.value_changed_tokens.find(key);
        if (enable && existing == connection->second.value_changed_tokens.end()) {
            auto service_uuid = UuidToString(found.Service().Uuid());
            auto characteristic_uuid = UuidToString(found.Uuid());
            connection->second.value_changed_tokens[key] = found.ValueChanged(
                [this, address, service_uuid, characteristic_uuid, lifetime](
                    GattCharacteristic, GattValueChangedEventArgs args)
                -> winrt::fire_and_forget {
                    auto bytes = BufferToBytes(args.CharacteristicValue());
                    co_await ui_thread_;
                    if (!lifetime->load() || !characteristic_value_sink_) co_return;
                    characteristic_value_sink_->Success(EncodableValue(flutter::EncodableMap{
                        {EncodableValue("address"), EncodableValue(std::to_string(address))},
                        {EncodableValue("serviceUuid"), EncodableValue(service_uuid)},
                        {EncodableValue("characteristicUuid"),
                            EncodableValue(characteristic_uuid)},
                        {EncodableValue("value"), EncodableValue(bytes)},
                    }));
                });
        }
        else if (!enable && existing != connection->second.value_changed_tokens.end()) {
            found.ValueChanged(existing->second);
            connection->second.value_changed_tokens.erase(existing);
        }
    }

    result->Success();
}

winrt::fire_and_forget FlutterBleCentralPlugin::ReadDescriptorAsync(
    uint64_t address, std::string service, std::string characteristic,
    std::string descriptor, Result result) {
    auto lifetime = alive_;
    auto found = co_await FindCharacteristic(address, service, characteristic);
    if (found) {
        auto descriptors = co_await found.GetDescriptorsForUuidAsync(
            ParseUuid(descriptor), BluetoothCacheMode::Cached);
        if (descriptors.Status() == GattCommunicationStatus::Success &&
            descriptors.Descriptors().Size() > 0) {
            auto read = co_await descriptors.Descriptors().GetAt(0)
                .ReadValueAsync(BluetoothCacheMode::Uncached);
            co_await ui_thread_;
            if (!lifetime->load()) co_return;
            if (read.Status() == GattCommunicationStatus::Success) {
                result->Success(EncodableValue(BufferToBytes(read.Value())));
                co_return;
            }
            result->Error("READ_DESCRIPTOR_ERROR", "Read failed");
            co_return;
        }
    }
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    result->Error("DESCRIPTOR_NOT_FOUND", "Descriptor " + descriptor + " not found");
}

winrt::fire_and_forget FlutterBleCentralPlugin::WriteDescriptorAsync(
    uint64_t address, std::string service, std::string characteristic,
    std::string descriptor, std::vector<uint8_t> value, Result result) {
    auto lifetime = alive_;
    auto found = co_await FindCharacteristic(address, service, characteristic);
    if (found) {
        auto descriptors = co_await found.GetDescriptorsForUuidAsync(
            ParseUuid(descriptor), BluetoothCacheMode::Cached);
        if (descriptors.Status() == GattCommunicationStatus::Success &&
            descriptors.Descriptors().Size() > 0) {
            auto status = co_await descriptors.Descriptors().GetAt(0)
                .WriteValueWithResultAsync(BytesToBuffer(value));
            co_await ui_thread_;
            if (!lifetime->load()) co_return;
            if (status.Status() == GattCommunicationStatus::Success) {
                result->Success();
                co_return;
            }
            result->Error("WRITE_DESCRIPTOR_ERROR", "Write failed");
            co_return;
        }
    }
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    result->Error("DESCRIPTOR_NOT_FOUND", "Descriptor " + descriptor + " not found");
}

winrt::fire_and_forget FlutterBleCentralPlugin::PairAsync(
    uint64_t address, bool pair, Result result) {
    auto lifetime = alive_;
    auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    if (!device) {
        co_await ui_thread_;
        if (!lifetime->load()) co_return;
        result->Error("UNKNOWN_PERIPHERAL", "No device with address " + std::to_string(address));
        co_return;
    }

    auto pairing = device.DeviceInformation().Pairing();
    int state = 10;  // BOND_NONE, the value Dart's BondState carries
    if (pair) {
        auto outcome = co_await pairing.PairAsync();
        auto status = outcome.Status();
        if (status == DevicePairingResultStatus::Paired ||
            status == DevicePairingResultStatus::AlreadyPaired) {
            state = 12;  // BOND_BONDED
        }
    }
    else {
        co_await pairing.UnpairAsync();
    }

    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (bond_state_sink_) {
        bond_state_sink_->Success(EncodableValue(flutter::EncodableMap{
            {EncodableValue("address"), EncodableValue(std::to_string(address))},
            {EncodableValue("bondState"), EncodableValue(state)},
        }));
    }
    result->Success();
}

void FlutterBleCentralPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));

    } else if (method_call.method_name().compare("isSupported") == 0) {
      bool supported = false;
      try {
        supported = bluetoothRadio != nullptr &&
            bluetoothRadio.State() != RadioState::Disabled;
      } catch (...) {}
      result->Success(flutter::EncodableValue(supported));
    } else if (method_call.method_name().compare("isBluetoothOn") == 0) {
      bool isOn = false;
      try {
        if (bluetoothRadio) {
          isOn = (bluetoothRadio.State() == RadioState::On);
        }
      }
      catch (...) {
        isOn = false;
      }
      result->Success(flutter::EncodableValue(isOn));
    } else if (method_call.method_name().compare("hasPermission") == 0) {
      // Windows doesn't have a permission system like mobile platforms
      // Return "granted" (0) if Bluetooth is available
      result->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
    } else if (method_call.method_name().compare("requestPermission") == 0) {
      // Windows doesn't require permission requests
      result->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
    } else if (method_call.method_name().compare("enableBluetooth") == 0) {
      EnableBluetoothAsync(std::move(result));
      return;
    } else if (method_call.method_name().compare("openBluetoothSettings") == 0) {
      // Open Windows Bluetooth settings
      ShellExecuteW(nullptr, L"open", L"ms-settings:bluetooth", nullptr, nullptr, SW_SHOWNORMAL);
      result->Success(flutter::EncodableValue());
    } else if (method_call.method_name().compare("openAppSettings") == 0) {
      // Open Windows app settings
      ShellExecuteW(nullptr, L"open", L"ms-settings:appsfeatures", nullptr, nullptr, SW_SHOWNORMAL);
      result->Success(flutter::EncodableValue());
    } else if (method_call.method_name().compare("start") == 0) {
      if (!bluetoothRadio || bluetoothRadio.State() == RadioState::Disabled) {
        result->Error("unsupported", "Bluetooth adapter not available");
        return;
      }
      try {
        if (!bluetoothLEWatcher) {
          bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
          bluetoothLEWatcher.ScanningMode(BluetoothLEScanningMode::Active);
          bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Received });
          bluetoothLEWatcher.Stopped({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Stopped });
        }
        auto status = bluetoothLEWatcher.Status();
        if (status != BluetoothLEAdvertisementWatcherStatus::Started) {
          bluetoothLEWatcher.Start();
        }
        result->Success(flutter::EncodableValue());
      } catch (winrt::hresult_error const& e) {
        bluetoothLEWatcher = nullptr;
        result->Error("start_failed", winrt::to_string(e.message()));
      } catch (...) {
        bluetoothLEWatcher = nullptr;
        result->Error("start_failed", "Failed to start scanning");
      }
    } else if (method_call.method_name().compare("stop") == 0) {
      try {
        if (bluetoothLEWatcher) {
          bluetoothLEWatcher.Stop();
          bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
        }
        bluetoothLEWatcher = nullptr;
        result->Success(flutter::EncodableValue());
      }
      catch (...) {
        bluetoothLEWatcher = nullptr;
        result->Error("stop_failed", "Failed to stop scanning");
      }
  }
    // GATT client
    else if (method_call.method_name().compare("connect") == 0 ||
             method_call.method_name().compare("disconnect") == 0 ||
             method_call.method_name().compare("getConnectionState") == 0 ||
             method_call.method_name().compare("discoverServices") == 0 ||
             method_call.method_name().compare("readCharacteristic") == 0 ||
             method_call.method_name().compare("writeCharacteristic") == 0 ||
             method_call.method_name().compare("setCharacteristicNotification") == 0 ||
             method_call.method_name().compare("readDescriptor") == 0 ||
             method_call.method_name().compare("writeDescriptor") == 0 ||
             method_call.method_name().compare("requestMtu") == 0 ||
             method_call.method_name().compare("createBond") == 0 ||
             method_call.method_name().compare("removeBond") == 0 ||
             method_call.method_name().compare("getBondState") == 0) {
        const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
        if (!arguments) {
            result->Error("INVALID_ARGUMENTS", "Arguments must be a map");
            return;
        }

        // Windows reports the address as the decimal form of the 48 bit value,
        // which is what the scan results sent and what comes back here.
        auto read_string = [&](const char* key) -> std::string {
            auto found = arguments->find(EncodableValue(key));
            if (found == arguments->end()) return {};
            if (const auto* value = std::get_if<std::string>(&found->second)) return *value;
            return {};
        };

        uint64_t address = 0;
        try {
            address = std::stoull(read_string("address"));
        }
        catch (...) {
            result->Error("INVALID_ARGUMENTS", "address is required");
            return;
        }

        const auto& method = method_call.method_name();
        if (method.compare("connect") == 0) {
            ConnectAsync(address, std::move(result));
        }
        else if (method.compare("disconnect") == 0) {
            Disconnect(address);
            result->Success();
        }
        else if (method.compare("getConnectionState") == 0) {
            auto found = connections_.find(address);
            auto connected = found != connections_.end() && found->second.device &&
                found->second.device.ConnectionStatus() ==
                    BluetoothConnectionStatus::Connected;
            result->Success(EncodableValue(connected ? 2 : 0));
        }
        else if (method.compare("discoverServices") == 0) {
            DiscoverServicesAsync(address, std::move(result));
        }
        else if (method.compare("readCharacteristic") == 0) {
            ReadCharacteristicAsync(address, read_string("serviceUuid"),
                read_string("characteristicUuid"), std::move(result));
        }
        else if (method.compare("writeCharacteristic") == 0) {
            std::vector<uint8_t> value;
            auto found = arguments->find(EncodableValue("value"));
            if (found != arguments->end()) {
                if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&found->second)) {
                    value = *bytes;
                }
            }
            auto without_response = false;
            auto option = arguments->find(EncodableValue("withoutResponse"));
            if (option != arguments->end()) {
                if (const auto* flag = std::get_if<bool>(&option->second)) {
                    without_response = *flag;
                }
            }
            WriteCharacteristicAsync(address, read_string("serviceUuid"),
                read_string("characteristicUuid"), value, without_response,
                std::move(result));
        }
        else if (method.compare("setCharacteristicNotification") == 0) {
            auto enable = false;
            auto found = arguments->find(EncodableValue("enable"));
            if (found != arguments->end()) {
                if (const auto* flag = std::get_if<bool>(&found->second)) enable = *flag;
            }
            SetNotifyAsync(address, read_string("serviceUuid"),
                read_string("characteristicUuid"), enable, std::move(result));
        }
        else if (method.compare("readDescriptor") == 0) {
            ReadDescriptorAsync(address, read_string("serviceUuid"),
                read_string("characteristicUuid"), read_string("descriptorUuid"),
                std::move(result));
        }
        else if (method.compare("writeDescriptor") == 0) {
            std::vector<uint8_t> value;
            auto found = arguments->find(EncodableValue("value"));
            if (found != arguments->end()) {
                if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&found->second)) {
                    value = *bytes;
                }
            }
            WriteDescriptorAsync(address, read_string("serviceUuid"),
                read_string("characteristicUuid"), read_string("descriptorUuid"),
                value, std::move(result));
        }
        else if (method.compare("requestMtu") == 0) {
            // Windows negotiates the MTU itself, so the size asked for is
            // ignored and what the session settled on is reported instead.
            auto found = connections_.find(address);
            if (found == connections_.end() || !found->second.session) {
                result->Error("NOT_CONNECTED", "Device is not connected");
                return;
            }
            result->Success(EncodableValue(
                static_cast<int>(found->second.session.MaxPduSize())));
        }
        else if (method.compare("createBond") == 0) {
            PairAsync(address, true, std::move(result));
        }
        else if (method.compare("removeBond") == 0) {
            PairAsync(address, false, std::move(result));
        }
        else if (method.compare("getBondState") == 0) {
            auto found = connections_.find(address);
            auto paired = found != connections_.end() && found->second.device &&
                found->second.device.DeviceInformation().Pairing().IsPaired();
            // The values Dart's BondState carries, which are Android's.
            result->Success(EncodableValue(paired ? 12 : 10));
        }
    }
    // Not exposed by Windows
    else if (method_call.method_name().compare("readRssi") == 0) {
        // Windows reports RSSI from advertisements only, never for a link that
        // is already up.
        result->Error("UNSUPPORTED", "RSSI of a connection is not available on Windows");
    }
    else if (method_call.method_name().compare("readPhy") == 0 ||
             method_call.method_name().compare("setPreferredPhy") == 0) {
        result->Error("UNSUPPORTED", "PHY control is not available on Windows");
    }
    else if (method_call.method_name().compare("requestConnectionPriority") == 0) {
        result->Error("UNSUPPORTED", "Connection priority is not available on Windows");
    }
    else if (method_call.method_name().compare("beginReliableWrite") == 0 ||
             method_call.method_name().compare("executeReliableWrite") == 0 ||
             method_call.method_name().compare("abortReliableWrite") == 0) {
        result->Error("UNSUPPORTED", "Reliable write is not available on Windows");
    }
    else {
    result->NotImplemented();
  }
}

union uint16_t_union {
  uint16_t uint16;
  byte bytes[sizeof(uint16_t)];
};

std::vector<uint8_t> to_bytevc(IBuffer buffer) {
  try {
    if (!buffer) {
      return std::vector<uint8_t>();
    }
    auto reader = DataReader::FromBuffer(buffer);
    auto result = std::vector<uint8_t>(reader.UnconsumedBufferLength());
    reader.ReadBytes(result);
    return result;
  }
  catch (...) {
    return std::vector<uint8_t>();
  }
}

std::vector<uint8_t> parseManufacturerData(BluetoothLEAdvertisement advertisement)  {
  try {
    if (advertisement.ManufacturerData().Size() == 0)
      return std::vector<uint8_t>();
    auto manufacturerData = advertisement.ManufacturerData().GetAt(0);
    // FIXME Compat with REG_DWORD_BIG_ENDIAN
    //uint8_t* prefix = uint16_t_union{ manufacturerData.CompanyId() }.bytes;

    //auto result = std::vector<uint8_t>{ prefix, prefix + sizeof(uint16_t_union) };
    auto data = to_bytevc(manufacturerData.Data());

    //result.insert(result.end(), data.begin(), data.end());
    return data;
  }
  catch (...) {
    return std::vector<uint8_t>();
  }
}

void FlutterBleCentralPlugin::BluetoothLEWatcher_Stopped(
    BluetoothLEAdvertisementWatcher sender,
    BluetoothLEAdvertisementWatcherStoppedEventArgs args) {
    // OutputDebugString((L"Stopped ".c_str());
    // Currently unused, but exception-safe
}

winrt::fire_and_forget FlutterBleCentralPlugin::BluetoothLEWatcher_Received(
    BluetoothLEAdvertisementWatcher sender,
    BluetoothLEAdvertisementReceivedEventArgs args) {
  try {
    // Extract all data on the callback thread first
    auto manufacturer_data = parseManufacturerData(args.Advertisement());
    auto bluetoothAddress = args.BluetoothAddress();
    auto localName = args.Advertisement().LocalName();
    auto name = winrt::to_string(localName);
    if (localName.empty()) {
      std::stringstream sstream;
      sstream << std::hex << bluetoothAddress;
      name = sstream.str();
    }
    auto manufacturerId = args.Advertisement().ManufacturerData().Size() > 0
        ? args.Advertisement().ManufacturerData().GetAt(0).CompanyId()
        : 0;
    auto rssi = args.RawSignalStrengthInDBm();
    auto address = std::to_string(bluetoothAddress);

    // Switch to UI thread before sending to Flutter
    co_await ui_thread_;

    if (scan_result_sink_) {
      scan_result_sink_->Success(flutter::EncodableMap{
        {"deviceName", name},
        {"address", address},
        {"manufacturerSpecificData", manufacturer_data},
        {"rssi", rssi},
        {"manufacturerId", manufacturerId},
      });
    }
  }
  catch (...) {
    // Silently ignore failed advertisement processing
  }
}



std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnListenInternal(
    const flutter::EncodableValue* arguments, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
{
  scan_result_sink_ = std::move(events);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnCancelInternal(
    const flutter::EncodableValue* arguments)
{
    scan_result_sink_ = nullptr;
  return nullptr;
}

// State changed event channel handlers
std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnStateListenInternal(
    const flutter::EncodableValue* arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
{
  state_changed_sink_ = std::move(events);
  // Send current state to new listener
  PublishState(GetCurrentState());
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnStateCancelInternal(
    const flutter::EncodableValue* arguments)
{
  state_changed_sink_ = nullptr;
  return nullptr;
}

winrt::fire_and_forget FlutterBleCentralPlugin::OnRadioStateChanged(Radio sender, IInspectable args) {
  try {
    auto state = GetCurrentState();
    co_await ui_thread_;
    PublishState(state);
  }
  catch (...) {
    // Ignore state change errors
  }
}

// CentralState enum values matching Dart:
// 0 = unknown, 1 = unsupported, 2 = unauthorized, 3 = poweredOff, 4 = idle
int FlutterBleCentralPlugin::GetCurrentState() {
  if (!bluetoothRadio) {
    return 1; // unsupported
  }
  try {
    switch (bluetoothRadio.State()) {
      case RadioState::On:
        return 4; // idle (ready)
      case RadioState::Off:
        return 3; // poweredOff
      case RadioState::Disabled:
        return 2; // unauthorized (disabled by policy)
      default:
        return 0; // unknown
    }
  }
  catch (...) {
    return 1; // unsupported - radio no longer available
  }
}

void FlutterBleCentralPlugin::PublishState(int state) {
  if (state_changed_sink_) {
    state_changed_sink_->Success(flutter::EncodableValue(state));
  }
}

winrt::fire_and_forget FlutterBleCentralPlugin::EnableBluetoothAsync(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!bluetoothRadio) {
    result->Success(flutter::EncodableValue(false));
    co_return;
  }

  bool success = false;
  try {
    auto accessStatus = co_await Radio::RequestAccessAsync();
    if (accessStatus == RadioAccessStatus::Allowed) {
      auto setResult = co_await bluetoothRadio.SetStateAsync(RadioState::On);
      success = (setResult == RadioAccessStatus::Allowed);
    }
  } catch (...) {
    success = false;
  }
  co_await ui_thread_;
  result->Success(flutter::EncodableValue(success));
}

}  // namespace flutter_ble_central
