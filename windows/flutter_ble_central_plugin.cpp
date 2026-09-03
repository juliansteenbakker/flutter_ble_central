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
#include <optional>
#include <vector>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

namespace flutter_ble_central {

namespace {

// The value Dart sent under `key`, or nothing when it is absent or the wrong
// type. A wrong type reads as absent, the way the Android side treats it.
std::optional<std::string> ReadString(const EncodableMap& arguments,
                                      const char* key) {
  auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) return std::nullopt;
  if (const auto* value = std::get_if<std::string>(&it->second)) return *value;
  return std::nullopt;
}

std::optional<bool> ReadBool(const EncodableMap& arguments, const char* key) {
  auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) return std::nullopt;
  if (const auto* value = std::get_if<bool>(&it->second)) return *value;
  return std::nullopt;
}

// Accepts both the byte buffer Dart sends for a Uint8List and the list of ints
// it falls back to.
std::optional<std::vector<uint8_t>> ReadBytes(const EncodableMap& arguments,
                                              const char* key) {
  auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) return std::nullopt;
  if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
    return *bytes;
  }
  if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
    std::vector<uint8_t> bytes;
    bytes.reserve(list->size());
    for (const auto& entry : *list) {
      if (const auto* number = std::get_if<int32_t>(&entry)) {
        bytes.push_back(static_cast<uint8_t>(*number));
      }
    }
    return bytes;
  }
  return std::nullopt;
}

}  // namespace

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

  // The three connection streams are all the same shape: park the sink on the
  // plugin, and drop it again on cancel.
  auto connection_stream = [&registrar](const char* name,
                                        std::unique_ptr<flutter::EventSink<>>* sink) {
    auto channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), name, &flutter::StandardMethodCodec::GetInstance());
    channel->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<>>(
        [sink](const flutter::EncodableValue*,
               std::unique_ptr<flutter::EventSink<>>&& events)
            -> std::unique_ptr<flutter::StreamHandlerError<>> {
          *sink = std::move(events);
          return nullptr;
        },
        [sink](const flutter::EncodableValue*)
            -> std::unique_ptr<flutter::StreamHandlerError<>> {
          *sink = nullptr;
          return nullptr;
        }));
    return channel;
  };

  auto event_connection_state =
      connection_stream("dev.steenbakker.flutter_ble_central/connection_state",
                        &plugin->connection_state_sink_);
  auto event_characteristic_value =
      connection_stream("dev.steenbakker.flutter_ble_central/characteristic_value",
                        &plugin->characteristic_value_sink_);
  auto event_bond_state =
      connection_stream("dev.steenbakker.flutter_ble_central/bond_state",
                        &plugin->bond_state_sink_);

  registrar->AddPlugin(std::move(plugin));
}

FlutterBleCentralPlugin::FlutterBleCentralPlugin() {
  // Built here rather than in the initialiser list: `alive_` is declared after
  // it, so it is not constructed yet at that point.
  gatt_ = std::make_unique<GattConnectionManager>(alive_, ui_thread_);
  gatt_->SetCallbacks(
      [this](const std::string& address, ConnectionState state) {
        if (connection_state_sink_) {
          connection_state_sink_->Success(EncodableValue(EncodableMap{
              {EncodableValue("address"), EncodableValue(address)},
              {EncodableValue("state"), EncodableValue(static_cast<int>(state))},
          }));
        }
      },
      [this](const std::string& address, const std::string& service_uuid,
             const std::string& characteristic_uuid,
             const std::vector<uint8_t>& value) {
        if (characteristic_value_sink_) {
          characteristic_value_sink_->Success(EncodableValue(EncodableMap{
              {EncodableValue("address"), EncodableValue(address)},
              {EncodableValue("serviceUuid"), EncodableValue(service_uuid)},
              {EncodableValue("characteristicUuid"), EncodableValue(characteristic_uuid)},
              {EncodableValue("value"), EncodableValue(value)},
          }));
        }
      },
      [this](const std::string& address, BondState state) {
        if (bond_state_sink_) {
          bond_state_sink_->Success(EncodableValue(EncodableMap{
              {EncodableValue("address"), EncodableValue(address)},
              {EncodableValue("bondState"), EncodableValue(static_cast<int>(state))},
          }));
        }
      });
  InitializeAsync();
}

FlutterBleCentralPlugin::~FlutterBleCentralPlugin() {
  // Revoke before the members go away: a radio or watcher event firing
  // afterwards would run against a destroyed plugin.
  *alive_ = false;
  // Same reason: a connection event arriving after this would run against a
  // destroyed plugin, and every peripheral is dropped rather than left held.
  if (gatt_) gatt_->CloseAll();
  try {
    if (bluetoothRadio && radioStateChangedToken) {
      bluetoothRadio.StateChanged(radioStateChangedToken);
    }
    if (bluetoothLEWatcher) {
      if (bluetoothLEWatcherReceivedToken) {
        bluetoothLEWatcher.Received(bluetoothLEWatcherReceivedToken);
      }
      if (bluetoothLEWatcherStoppedToken) {
        bluetoothLEWatcher.Stopped(bluetoothLEWatcherStoppedToken);
      }
      if (bluetoothLEWatcher.Status() == BluetoothLEAdvertisementWatcherStatus::Started) {
        bluetoothLEWatcher.Stop();
      }
    }
  }
  catch (...) {
    // Nothing useful to do while tearing down.
  }
}

winrt::fire_and_forget FlutterBleCentralPlugin::InitializeAsync() {
  auto alive = alive_;
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

  // Until this has run there is no adapter to report on, so a listener that
  // attached in the meantime is still sitting on unknown.
  auto state = GetCurrentState();
  co_await ui_thread_;
  if (!*alive) co_return;
  PublishState(state);

  radio_looked_up_ = true;
  auto waiting = std::move(waiting_on_radio_);
  waiting_on_radio_.clear();
  for (auto& work : waiting) work();
}

void FlutterBleCentralPlugin::WhenRadioReady(std::function<void()> work) {
  if (radio_looked_up_) {
    work();
    return;
  }
  waiting_on_radio_.push_back(std::move(work));
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
      WhenRadioReady([this, shared = std::shared_ptr(std::move(result))]() {
        bool supported = false;
        try {
          supported = bluetoothRadio != nullptr &&
              bluetoothRadio.State() != RadioState::Disabled;
        } catch (...) {}
        shared->Success(flutter::EncodableValue(supported));
      });
      return;
    } else if (method_call.method_name().compare("isBluetoothOn") == 0) {
      WhenRadioReady([this, shared = std::shared_ptr(std::move(result))]() {
        bool isOn = false;
        try {
          if (bluetoothRadio) {
            isOn = (bluetoothRadio.State() == RadioState::On);
          }
        }
        catch (...) {
          isOn = false;
        }
        shared->Success(flutter::EncodableValue(isOn));
      });
      return;
    } else if (method_call.method_name().compare("hasPermission") == 0) {
      // Windows doesn't have a permission system like mobile platforms
      // Return "granted" (0) if Bluetooth is available
      WhenRadioReady([this, shared = std::shared_ptr(std::move(result))]() {
        shared->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
      });
      return;
    } else if (method_call.method_name().compare("requestPermission") == 0) {
      // Windows doesn't require permission requests
      WhenRadioReady([this, shared = std::shared_ptr(std::move(result))]() {
        shared->Success(flutter::EncodableValue(bluetoothRadio != nullptr ? 0 : 1));
      });
      return;
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
        scan_service_uuids_.clear();
        if (const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments())) {
          auto entry = arguments->find(flutter::EncodableValue("serviceUuids"));
          if (entry != arguments->end()) {
            if (const auto* list = std::get_if<flutter::EncodableList>(&entry->second)) {
              for (const auto& value : *list) {
                const auto* uuid = std::get_if<std::string>(&value);
                if (!uuid) {
                  result->Error("INVALID_ARGUMENT", "A scan service uuid must be a string");
                  return;
                }
                try {
                  scan_service_uuids_.push_back(FormatUuid(ParseUuid(*uuid)));
                }
                catch (...) {
                  scan_service_uuids_.clear();
                  result->Error("INVALID_ARGUMENT", *uuid + " is not a service uuid");
                  return;
                }
              }
            }
          }
        }

        if (!bluetoothLEWatcher) {
          bluetoothLEWatcher = BluetoothLEAdvertisementWatcher();
          bluetoothLEWatcher.ScanningMode(BluetoothLEScanningMode::Active);
          bluetoothLEWatcherReceivedToken = bluetoothLEWatcher.Received({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Received });
          bluetoothLEWatcherStoppedToken = bluetoothLEWatcher.Stopped({ this, &FlutterBleCentralPlugin::BluetoothLEWatcher_Stopped });
        }
        auto status = bluetoothLEWatcher.Status();
        if (status != BluetoothLEAdvertisementWatcherStatus::Started) {
          seen_peripherals_.clear();
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
          bluetoothLEWatcher.Stopped(bluetoothLEWatcherStoppedToken);
        }
        bluetoothLEWatcherReceivedToken = {};
        bluetoothLEWatcherStoppedToken = {};
        bluetoothLEWatcher = nullptr;
        scan_service_uuids_.clear();
        seen_peripherals_.clear();
        result->Success(flutter::EncodableValue());
      }
      catch (...) {
        bluetoothLEWatcherReceivedToken = {};
        bluetoothLEWatcherStoppedToken = {};
        bluetoothLEWatcher = nullptr;
        scan_service_uuids_.clear();
        seen_peripherals_.clear();
        result->Error("stop_failed", "Failed to stop scanning");
      }
  } else if (IsConnectionMethod(method_call.method_name())) {
      HandleConnectionMethod(method_call, std::move(result));
  } else {
    result->NotImplemented();
  }
}

// Whether a method belongs to the GATT client half, so that everything it needs
// to read out of the arguments is read in one place.
bool FlutterBleCentralPlugin::IsConnectionMethod(const std::string& method) {
  static const std::set<std::string> methods{
      "connect", "disconnect", "getConnectionState", "discoverServices",
      "readCharacteristic", "writeCharacteristic", "setCharacteristicNotification",
      "readDescriptor", "writeDescriptor", "requestMtu", "createBond",
      "removeBond", "readRssi", "setPreferredPhy", "readPhy",
      "requestConnectionPriority", "beginReliableWrite", "executeReliableWrite",
      "abortReliableWrite", "getBondState"};
  return methods.count(method) > 0;
}

void FlutterBleCentralPlugin::ReportUnsupported(
    const std::string& method,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->Error("unsupported", method + " is not available on Windows");
}

void FlutterBleCentralPlugin::HandleConnectionMethod(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  // Windows exposes no way to serve these, so they are refused by name rather
  // than left to fail as a missing plugin.
  if (method == "readRssi" || method == "setPreferredPhy" || method == "readPhy" ||
      method == "requestConnectionPriority" || method == "beginReliableWrite" ||
      method == "executeReliableWrite" || method == "abortReliableWrite" ||
      method == "getBondState") {
    ReportUnsupported(method, std::move(result));
    return;
  }

  const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
  if (!arguments) {
    result->Error("INVALID_ARGUMENTS", "Arguments are not a map");
    return;
  }

  // Everything Dart sends is read and validated here, on the platform thread.
  // A uuid is parsed before any coroutine starts, because an exception escaping
  // a fire_and_forget calls winrt::terminate rather than reaching Dart.
  uint64_t address = 0;
  winrt::guid service_uuid{};
  winrt::guid characteristic_uuid{};
  winrt::guid descriptor_uuid{};
  std::vector<uint8_t> value;
  try {
    auto address_string = ReadString(*arguments, "address");
    if (!address_string) {
      result->Error("INVALID_ARGUMENTS", "address is required");
      return;
    }
    address = std::stoull(*address_string);

    if (auto uuid = ReadString(*arguments, "serviceUuid")) {
      service_uuid = ParseUuid(*uuid);
    }
    if (auto uuid = ReadString(*arguments, "characteristicUuid")) {
      characteristic_uuid = ParseUuid(*uuid);
    }
    if (auto uuid = ReadString(*arguments, "descriptorUuid")) {
      descriptor_uuid = ParseUuid(*uuid);
    }
    if (auto bytes = ReadBytes(*arguments, "value")) {
      value = *bytes;
    }
  } catch (const InvalidArgument& error) {
    result->Error("INVALID_ARGUMENTS", error.what());
    return;
  } catch (...) {
    result->Error("INVALID_ARGUMENTS", "address is not a device address");
    return;
  }

  if (method == "connect") {
    gatt_->Connect(address, std::move(result));
  } else if (method == "disconnect") {
    gatt_->Disconnect(address, std::move(result));
  } else if (method == "getConnectionState") {
    result->Success(EncodableValue(
        static_cast<int>(gatt_->GetConnectionState(address))));
  } else if (method == "discoverServices") {
    gatt_->DiscoverServices(address, std::move(result));
  } else if (method == "readCharacteristic") {
    gatt_->ReadCharacteristic(address, service_uuid, characteristic_uuid,
                              std::move(result));
  } else if (method == "writeCharacteristic") {
    auto without_response =
        ReadBool(*arguments, "withoutResponse").value_or(false);
    gatt_->WriteCharacteristic(address, service_uuid, characteristic_uuid, value,
                               without_response, std::move(result));
  } else if (method == "setCharacteristicNotification") {
    auto enable = ReadBool(*arguments, "enable").value_or(false);
    gatt_->SetCharacteristicNotification(address, service_uuid,
                                         characteristic_uuid, enable,
                                         std::move(result));
  } else if (method == "readDescriptor") {
    gatt_->ReadDescriptor(address, service_uuid, characteristic_uuid,
                          descriptor_uuid, std::move(result));
  } else if (method == "writeDescriptor") {
    gatt_->WriteDescriptor(address, service_uuid, characteristic_uuid,
                           descriptor_uuid, value, std::move(result));
  } else if (method == "requestMtu") {
    // Windows negotiates the MTU itself and offers no way to ask for one, so
    // the requested size is ignored and the negotiated one is reported.
    auto mtu = gatt_->GetMtu(address);
    if (mtu == 0) {
      result->Error("MTU_ERROR", "Device not connected");
    } else {
      result->Success(EncodableValue(mtu));
    }
  } else if (method == "createBond") {
    gatt_->CreateBond(address, std::move(result));
  } else if (method == "removeBond") {
    gatt_->RemoveBond(address, std::move(result));
  } else {
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
  auto alive = alive_;
  try {
    // Extract all data on the callback thread first
    auto manufacturer_data = parseManufacturerData(args.Advertisement());
    auto bluetoothAddress = args.BluetoothAddress();
    auto localName = args.Advertisement().LocalName();
    std::optional<std::string> name;
    if (!localName.empty()) name = winrt::to_string(localName);
    const uint16_t manufacturerId =
        args.Advertisement().ManufacturerData().Size() > 0
            ? args.Advertisement().ManufacturerData().GetAt(0).CompanyId()
            : uint16_t{0};
    auto rssi = args.RawSignalStrengthInDBm();
    auto address = std::to_string(bluetoothAddress);

    // The uuids a peripheral advertises are how a central picks the one it
    // wants out of everything in range, so they have to reach Dart.
    flutter::EncodableList service_uuids;
    for (auto const& uuid : args.Advertisement().ServiceUuids()) {
      service_uuids.push_back(flutter::EncodableValue(FormatUuid(uuid)));
    }

    // Switch to UI thread before sending to Flutter
    co_await ui_thread_;
    if (!*alive) co_return;

    // Fold this packet into what the peripheral has already said. Only what it
    // carries is taken: the fields it left out are the ones that were in the
    // packet before it, and overwriting those with nothing is the whole bug
    // this guards against.
    auto& seen = seen_peripherals_[bluetoothAddress];
    if (name) seen.name = std::move(name);
    if (!service_uuids.empty()) seen.service_uuids = std::move(service_uuids);
    if (!manufacturer_data.empty()) {
      seen.manufacturer_data = std::move(manufacturer_data);
      seen.manufacturer_id = manufacturerId;
    }

    // A filtered scan reports only peripherals that have advertised one of the
    // wanted services. Matched against the merged record rather than this packet,
    // since the uuid may have arrived in an earlier advertisement or in the scan
    // response, and a peripheral that already qualified goes on qualifying.
    if (!scan_service_uuids_.empty()) {
      bool wanted = false;
      for (const auto& value : seen.service_uuids) {
        const auto* uuid = std::get_if<std::string>(&value);
        if (!uuid) continue;
        if (std::find(scan_service_uuids_.begin(), scan_service_uuids_.end(), *uuid) !=
            scan_service_uuids_.end()) {
          wanted = true;
          break;
        }
      }
      if (!wanted) co_return;
    }

    if (scan_result_sink_) {
      // The rssi is this packet's rather than the merged record's: it is a
      // reading taken now, not something the peripheral said.
      scan_result_sink_->Success(flutter::EncodableMap{
        {"deviceName", seen.name ? flutter::EncodableValue(*seen.name)
                                 : flutter::EncodableValue()},
        {"address", address},
        {"manufacturerSpecificData", seen.manufacturer_data},
        {"rssi", rssi},
        {"manufacturerId", static_cast<int32_t>(seen.manufacturer_id)},
        {"serviceUuids", seen.service_uuids},
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
  SendCurrentState();
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> FlutterBleCentralPlugin::OnStateCancelInternal(
    const flutter::EncodableValue* arguments)
{
  state_changed_sink_ = nullptr;
  return nullptr;
}

winrt::fire_and_forget FlutterBleCentralPlugin::OnRadioStateChanged(Radio sender, IInspectable args) {
  auto alive = alive_;
  try {
    auto state = GetCurrentState();
    co_await ui_thread_;
    if (!*alive) co_return;
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
  // The radio can report the same state more than once; the repeat says
  // nothing new.
  if (state == central_state_) {
    return;
  }
  central_state_ = state;
  SendCurrentState();
}

void FlutterBleCentralPlugin::SendCurrentState() {
  if (state_changed_sink_) {
    state_changed_sink_->Success(flutter::EncodableValue(central_state_));
  }
}

winrt::fire_and_forget FlutterBleCentralPlugin::EnableBluetoothAsync(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto alive = alive_;
  if (!bluetoothRadio) {
    result->Success(flutter::EncodableValue(false));
    co_return;
  }

  bool success = false;
  try {
    auto accessStatus = co_await Radio::RequestAccessAsync();
    if (!*alive) co_return;
    if (accessStatus == RadioAccessStatus::Allowed) {
      auto setResult = co_await bluetoothRadio.SetStateAsync(RadioState::On);
      success = (setResult == RadioAccessStatus::Allowed);
    }
  } catch (...) {
    success = false;
  }
  co_await ui_thread_;
  if (!*alive) co_return;
  result->Success(flutter::EncodableValue(success));
}

}  // namespace flutter_ble_central
