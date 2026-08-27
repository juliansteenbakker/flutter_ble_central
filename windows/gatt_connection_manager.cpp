#include "gatt_connection_manager.h"

#include <array>
#include <sstream>
#include <utility>

namespace flutter_ble_central {

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Foundation::Collections;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Devices::Bluetooth;
using namespace winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace winrt::Windows::Devices::Enumeration;

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// The tail of the Bluetooth Base UUID, onto which the 16 and 32 bit short forms
// of a uuid are expanded.
constexpr auto kBluetoothBaseSuffix = "00001000800000805F9B34FB";

uint8_t ParseHexDigit(char digit, const std::string& uuid) {
  if (digit >= '0' && digit <= '9') return static_cast<uint8_t>(digit - '0');
  if (digit >= 'a' && digit <= 'f') return static_cast<uint8_t>(digit - 'a' + 10);
  if (digit >= 'A' && digit <= 'F') return static_cast<uint8_t>(digit - 'A' + 10);
  throw InvalidArgument("Invalid uuid: " + uuid);
}

std::vector<uint8_t> ToBytes(IBuffer const& buffer) {
  if (!buffer) return {};
  auto reader = DataReader::FromBuffer(buffer);
  std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
  reader.ReadBytes(bytes);
  return bytes;
}

IBuffer ToBuffer(const std::vector<uint8_t>& bytes) {
  DataWriter writer;
  writer.WriteBytes(bytes);
  return writer.DetachBuffer();
}

EncodableValue ToEncodableBytes(const std::vector<uint8_t>& bytes) {
  // Dart reads this back as a list of ints rather than a byte buffer, matching
  // what the Android implementation sends.
  EncodableList list;
  list.reserve(bytes.size());
  for (auto byte : bytes) list.push_back(EncodableValue(static_cast<int>(byte)));
  return EncodableValue(list);
}

// Keys a characteristic within a connection.
std::string CharacteristicKey(const winrt::guid& service_uuid,
                              const winrt::guid& characteristic_uuid) {
  return FormatUuid(service_uuid) + "/" + FormatUuid(characteristic_uuid);
}

// The message a GATT status that is not Success deserves.
std::string DescribeStatus(GattCommunicationStatus status) {
  switch (status) {
    case GattCommunicationStatus::Unreachable:
      return "The peripheral is unreachable";
    case GattCommunicationStatus::ProtocolError:
      return "The peripheral answered with a protocol error";
    case GattCommunicationStatus::AccessDenied:
      return "Access denied; the peripheral may need to be paired first";
    default:
      return "The operation failed";
  }
}

}  // namespace

winrt::guid ParseUuid(const std::string& value) {
  std::string hex;
  for (char character : value) {
    if (character != '-') hex.push_back(character);
  }

  switch (hex.size()) {
    case 4: hex = "0000" + hex + kBluetoothBaseSuffix; break;
    case 8: hex = hex + kBluetoothBaseSuffix; break;
    case 32: break;
    default: throw InvalidArgument("Invalid uuid: " + value);
  }

  std::array<uint8_t, 16> bytes{};
  for (size_t i = 0; i < bytes.size(); i++) {
    bytes[i] = static_cast<uint8_t>((ParseHexDigit(hex[i * 2], value) << 4) |
                                    ParseHexDigit(hex[i * 2 + 1], value));
  }

  return winrt::guid{
      (static_cast<uint32_t>(bytes[0]) << 24) |
          (static_cast<uint32_t>(bytes[1]) << 16) |
          (static_cast<uint32_t>(bytes[2]) << 8) | static_cast<uint32_t>(bytes[3]),
      static_cast<uint16_t>((static_cast<uint16_t>(bytes[4]) << 8) | bytes[5]),
      static_cast<uint16_t>((static_cast<uint16_t>(bytes[6]) << 8) | bytes[7]),
      {bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
       bytes[15]},
  };
}

std::string FormatUuid(const winrt::guid& value) {
  static const char* digits = "0123456789abcdef";
  std::string out;
  out.reserve(36);

  auto append = [&out](uint8_t byte) {
    out.push_back(digits[(byte >> 4) & 0x0F]);
    out.push_back(digits[byte & 0x0F]);
  };

  append(static_cast<uint8_t>(value.Data1 >> 24));
  append(static_cast<uint8_t>(value.Data1 >> 16));
  append(static_cast<uint8_t>(value.Data1 >> 8));
  append(static_cast<uint8_t>(value.Data1));
  out.push_back('-');
  append(static_cast<uint8_t>(value.Data2 >> 8));
  append(static_cast<uint8_t>(value.Data2));
  out.push_back('-');
  append(static_cast<uint8_t>(value.Data3 >> 8));
  append(static_cast<uint8_t>(value.Data3));
  out.push_back('-');
  append(value.Data4[0]);
  append(value.Data4[1]);
  out.push_back('-');
  for (size_t i = 2; i < 8; i++) append(value.Data4[i]);

  return out;
}

GattConnectionManager::GattConnectionManager(
    std::shared_ptr<std::atomic_bool> alive, winrt::apartment_context ui_thread)
    : alive_(std::move(alive)), ui_thread_(std::move(ui_thread)) {}

GattConnectionManager::~GattConnectionManager() { CloseAll(); }

void GattConnectionManager::SetCallbacks(StateCallback on_state,
                                         ValueCallback on_value,
                                         BondCallback on_bond) {
  on_state_ = std::move(on_state);
  on_value_ = std::move(on_value);
  on_bond_ = std::move(on_bond);
}

GattConnectionManager::Connection* GattConnectionManager::Find(
    const std::string& key) {
  auto it = connections_.find(key);
  return it == connections_.end() ? nullptr : &it->second;
}

const GattConnectionManager::Connection* GattConnectionManager::Find(
    const std::string& key) const {
  auto it = connections_.find(key);
  return it == connections_.end() ? nullptr : &it->second;
}

bool GattConnectionManager::FindCharacteristic(
    const std::string& key, const winrt::guid& service_uuid,
    const winrt::guid& characteristic_uuid, GattCharacteristic& characteristic,
    std::string& error) const {
  const auto* connection = Find(key);
  if (!connection) {
    error = "Device not connected";
    return false;
  }
  auto it = connection->characteristics.find(
      CharacteristicKey(service_uuid, characteristic_uuid));
  if (it == connection->characteristics.end()) {
    error =
        "Characteristic not found; call discoverServices before reading or "
        "writing";
    return false;
  }
  characteristic = it->second;
  return true;
}

void GattConnectionManager::PublishState(const std::string& key,
                                         ConnectionState state) {
  auto* connection = Find(key);
  if (connection) {
    if (connection->state == state) return;
    connection->state = state;
  }
  if (on_state_) on_state_(key, state);
}

void GattConnectionManager::Close(const std::string& key) {
  auto it = connections_.find(key);
  if (it == connections_.end()) return;
  auto& connection = it->second;

  // Revoke before releasing: an event arriving afterwards would run against a
  // connection that is already gone.
  try {
    for (auto& [characteristic_key, token] : connection.value_tokens) {
      auto found = connection.characteristics.find(characteristic_key);
      if (found != connection.characteristics.end()) {
        found->second.ValueChanged(token);
      }
    }
    if (connection.device && connection.connection_status_token) {
      connection.device.ConnectionStatusChanged(connection.connection_status_token);
    }
    if (connection.session) {
      connection.session.MaintainConnection(false);
      connection.session.Close();
    }
    for (auto& service : connection.services) {
      service.Close();
    }
    if (connection.device) {
      connection.device.Close();
    }
  } catch (...) {
    // Already gone, or the radio went away underneath it.
  }

  connections_.erase(it);
}

void GattConnectionManager::CloseAll() {
  std::vector<std::string> keys;
  keys.reserve(connections_.size());
  for (const auto& [key, _] : connections_) keys.push_back(key);
  for (const auto& key : keys) Close(key);
}

ConnectionState GattConnectionManager::GetConnectionState(
    uint64_t address) const {
  const auto* connection = Find(std::to_string(address));
  if (!connection) return ConnectionState::Disconnected;
  try {
    return connection->device && connection->device.ConnectionStatus() ==
                                     BluetoothConnectionStatus::Connected
               ? ConnectionState::Connected
               : connection->state;
  } catch (...) {
    return ConnectionState::Disconnected;
  }
}

int GattConnectionManager::GetMtu(uint64_t address) const {
  const auto* connection = Find(std::to_string(address));
  if (!connection || !connection->session) return 0;
  try {
    return static_cast<int>(connection->session.MaxPduSize());
  } catch (...) {
    return 0;
  }
}

winrt::fire_and_forget GattConnectionManager::OnConnectionStatusChanged(
    BluetoothLEDevice sender, IInspectable) {
  auto lifetime = alive_;
  auto connected = false;
  std::string key;
  try {
    connected = sender.ConnectionStatus() == BluetoothConnectionStatus::Connected;
    key = std::to_string(sender.BluetoothAddress());
  } catch (...) {
    co_return;
  }

  try {
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (!Find(key)) co_return;
    PublishState(key, connected ? ConnectionState::Connected
                                : ConnectionState::Disconnected);
  } catch (...) {
    // An exception leaving here would take the process with it.
  }
}

winrt::fire_and_forget GattConnectionManager::Connect(uint64_t address,
                                                      MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    if (Find(key)) {
      result->Error("CONNECTION_ERROR", "Already connected to device");
      co_return;
    }

    // Windows has no explicit connect. Resolving the device and holding a
    // session open with MaintainConnection is what brings the link up, and the
    // radio reports it through ConnectionStatusChanged.
    auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (!device) {
      result->Error("CONNECTION_ERROR",
                    "No peripheral with that address is in range");
      co_return;
    }

    auto session = co_await GattSession::FromDeviceIdAsync(device.BluetoothDeviceId());
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    // Another connect landed while this one was in flight. The session opened
    // here is dropped rather than left holding the link.
    if (Find(key)) {
      session.MaintainConnection(false);
      session.Close();
      result->Error("CONNECTION_ERROR", "Already connected to device");
      co_return;
    }

    Connection connection;
    connection.device = device;
    connection.session = session;
    connection.token = ++next_token_;
    connection.state = ConnectionState::Disconnected;

    // MaintainConnection is what brings the link up; it does not do so at once,
    // and the radio reports the result through ConnectionStatusChanged.
    session.MaintainConnection(true);
    connection.connection_status_token = device.ConnectionStatusChanged(
        {this, &GattConnectionManager::OnConnectionStatusChanged});
    connections_[key] = std::move(connection);

    result->Success();

    // Report where the link already is. A peripheral another app is talking to
    // is connected the moment it resolves, and ConnectionStatusChanged will
    // never fire to say so.
    auto connected =
        device.ConnectionStatus() == BluetoothConnectionStatus::Connected;
    PublishState(key, connected ? ConnectionState::Connected
                                : ConnectionState::Connecting);
    if (connected) co_return;

    // MaintainConnection on its own only says the link should be kept once it
    // exists; the radio does not reach out until something asks the peripheral
    // for its database. Without this a connect to an unpaired peripheral sits
    // in connecting until it times out, and the peripheral never sees it.
    auto token = connections_[key].token;
    co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    // Closed, or reconnected under the same address, while the request was out.
    auto* still = Find(key);
    if (!still || still->token != token) co_return;

    // ConnectionStatusChanged reports the link coming up, but it has often
    // already fired by the time the request resolves.
    if (device.ConnectionStatus() == BluetoothConnectionStatus::Connected) {
      PublishState(key, ConnectionState::Connected);
    }
  } catch (const winrt::hresult_error& error) {
    Close(key);
    result->Error("CONNECTION_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    Close(key);
    result->Error("CONNECTION_ERROR", "Failed to connect");
  }
}

winrt::fire_and_forget GattConnectionManager::Disconnect(uint64_t address,
                                                         MethodResult result) {
  auto key = std::to_string(address);
  try {
    if (!Find(key)) {
      result->Error("CONNECTION_ERROR", "Device not connected");
      co_return;
    }
    Close(key);
    if (on_state_) on_state_(key, ConnectionState::Disconnected);
    result->Success();
  } catch (...) {
    result->Error("CONNECTION_ERROR", "Failed to disconnect");
  }
}

winrt::fire_and_forget GattConnectionManager::DiscoverServices(
    uint64_t address, MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    auto* connection = Find(key);
    if (!connection) {
      result->Error("SERVICE_DISCOVERY_ERROR", "Device not connected");
      co_return;
    }
    auto device = connection->device;
    auto token = connection->token;

    // Uncached, so a peripheral whose database changed since Windows last saw
    // it is read again rather than answered from the pairing store.
    auto services_result =
        co_await device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (services_result.Status() != GattCommunicationStatus::Success) {
      result->Error("SERVICE_DISCOVERY_ERROR",
                    DescribeStatus(services_result.Status()));
      co_return;
    }

    std::vector<GattDeviceService> services;
    std::map<std::string, GattCharacteristic> characteristics;
    EncodableList serialized;

    for (auto const& service : services_result.Services()) {
      auto service_uuid = FormatUuid(service.Uuid());

      auto characteristics_result =
          co_await service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached);
      co_await ui_thread_;
      if (!lifetime->load()) co_return;

      // A service that refuses to be read is reported without its
      // characteristics rather than failing the whole discovery.
      EncodableList serialized_characteristics;
      if (characteristics_result.Status() == GattCommunicationStatus::Success) {
        for (auto const& characteristic : characteristics_result.Characteristics()) {
          auto characteristic_uuid = FormatUuid(characteristic.Uuid());
          auto properties = characteristic.CharacteristicProperties();
          auto has = [&properties](GattCharacteristicProperties flag) {
            return (properties & flag) != GattCharacteristicProperties::None;
          };

          EncodableList serialized_descriptors;
          auto descriptors_result = co_await characteristic.GetDescriptorsAsync(
              BluetoothCacheMode::Uncached);
          co_await ui_thread_;
          if (!lifetime->load()) co_return;

          if (descriptors_result.Status() == GattCommunicationStatus::Success) {
            for (auto const& descriptor : descriptors_result.Descriptors()) {
              serialized_descriptors.push_back(EncodableValue(EncodableMap{
                  {EncodableValue("uuid"), EncodableValue(FormatUuid(descriptor.Uuid()))},
                  {EncodableValue("characteristicUuid"), EncodableValue(characteristic_uuid)},
                  {EncodableValue("serviceUuid"), EncodableValue(service_uuid)},
              }));
            }
          }

          serialized_characteristics.push_back(EncodableValue(EncodableMap{
              {EncodableValue("uuid"), EncodableValue(characteristic_uuid)},
              {EncodableValue("serviceUuid"), EncodableValue(service_uuid)},
              {EncodableValue("properties"),
               EncodableValue(EncodableMap{
                   {EncodableValue("broadcast"),
                    EncodableValue(has(GattCharacteristicProperties::Broadcast))},
                   {EncodableValue("read"),
                    EncodableValue(has(GattCharacteristicProperties::Read))},
                   {EncodableValue("writeWithoutResponse"),
                    EncodableValue(has(GattCharacteristicProperties::WriteWithoutResponse))},
                   {EncodableValue("write"),
                    EncodableValue(has(GattCharacteristicProperties::Write))},
                   {EncodableValue("notify"),
                    EncodableValue(has(GattCharacteristicProperties::Notify))},
                   {EncodableValue("indicate"),
                    EncodableValue(has(GattCharacteristicProperties::Indicate))},
                   {EncodableValue("authenticatedSignedWrites"),
                    EncodableValue(has(GattCharacteristicProperties::AuthenticatedSignedWrites))},
                   {EncodableValue("extendedProperties"),
                    EncodableValue(has(GattCharacteristicProperties::ExtendedProperties))},
               })},
              {EncodableValue("descriptors"), EncodableValue(serialized_descriptors)},
          }));

          characteristics.emplace(
              CharacteristicKey(service.Uuid(), characteristic.Uuid()),
              characteristic);
        }
      }

      services.push_back(service);
      serialized.push_back(EncodableValue(EncodableMap{
          {EncodableValue("uuid"), EncodableValue(service_uuid)},
          // Windows only hands back primary services.
          {EncodableValue("isPrimary"), EncodableValue(true)},
          {EncodableValue("characteristics"), EncodableValue(serialized_characteristics)},
      }));
    }

    // A disconnect, or a reconnect, while this was in flight. What it left
    // behind is not this call's to overwrite.
    auto* current = Find(key);
    if (!current || current->token != token) {
      result->Error("SERVICE_DISCOVERY_ERROR",
                    "Disconnected before discovery finished");
      co_return;
    }

    current->services = std::move(services);
    current->characteristics = std::move(characteristics);
    result->Success(EncodableValue(serialized));
  } catch (const winrt::hresult_error& error) {
    result->Error("SERVICE_DISCOVERY_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("SERVICE_DISCOVERY_ERROR", "Failed to discover services");
  }
}

winrt::fire_and_forget GattConnectionManager::ReadCharacteristic(
    uint64_t address, winrt::guid service_uuid, winrt::guid characteristic_uuid,
    MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    GattCharacteristic characteristic{nullptr};
    std::string error;
    if (!FindCharacteristic(key, service_uuid, characteristic_uuid, characteristic,
                            error)) {
      result->Error("READ_ERROR", error);
      co_return;
    }
    if ((characteristic.CharacteristicProperties() &
         GattCharacteristicProperties::Read) ==
        GattCharacteristicProperties::None) {
      result->Error("READ_ERROR", "Characteristic does not support read");
      co_return;
    }

    auto read = co_await characteristic.ReadValueAsync(BluetoothCacheMode::Uncached);
    auto bytes = read.Status() == GattCommunicationStatus::Success
                     ? ToBytes(read.Value())
                     : std::vector<uint8_t>{};
    auto status = read.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != GattCommunicationStatus::Success) {
      result->Error("READ_ERROR", DescribeStatus(status));
      co_return;
    }
    result->Success(ToEncodableBytes(bytes));
  } catch (const winrt::hresult_error& error) {
    result->Error("READ_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("READ_ERROR", "Failed to read the characteristic");
  }
}

winrt::fire_and_forget GattConnectionManager::WriteCharacteristic(
    uint64_t address, winrt::guid service_uuid, winrt::guid characteristic_uuid,
    std::vector<uint8_t> value, bool without_response, MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    GattCharacteristic characteristic{nullptr};
    std::string error;
    if (!FindCharacteristic(key, service_uuid, characteristic_uuid, characteristic,
                            error)) {
      result->Error("WRITE_ERROR", error);
      co_return;
    }

    auto option = without_response ? GattWriteOption::WriteWithoutResponse
                                   : GattWriteOption::WriteWithResponse;
    auto required = without_response
                        ? GattCharacteristicProperties::WriteWithoutResponse
                        : GattCharacteristicProperties::Write;
    if ((characteristic.CharacteristicProperties() & required) ==
        GattCharacteristicProperties::None) {
      result->Error("WRITE_ERROR",
                    without_response
                        ? "Characteristic does not support write without response"
                        : "Characteristic does not support write");
      co_return;
    }

    auto write =
        co_await characteristic.WriteValueWithResultAsync(ToBuffer(value), option);
    auto status = write.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != GattCommunicationStatus::Success) {
      result->Error("WRITE_ERROR", DescribeStatus(status));
      co_return;
    }
    result->Success();
  } catch (const winrt::hresult_error& error) {
    result->Error("WRITE_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("WRITE_ERROR", "Failed to write the characteristic");
  }
}

winrt::fire_and_forget GattConnectionManager::SetCharacteristicNotification(
    uint64_t address, winrt::guid service_uuid, winrt::guid characteristic_uuid,
    bool enable, MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);
  auto characteristic_key = CharacteristicKey(service_uuid, characteristic_uuid);

  try {
    GattCharacteristic characteristic{nullptr};
    std::string error;
    if (!FindCharacteristic(key, service_uuid, characteristic_uuid, characteristic,
                            error)) {
      result->Error("NOTIFICATION_ERROR", error);
      co_return;
    }

    auto properties = characteristic.CharacteristicProperties();
    auto descriptor_value =
        GattClientCharacteristicConfigurationDescriptorValue::None;
    if (enable) {
      if ((properties & GattCharacteristicProperties::Notify) !=
          GattCharacteristicProperties::None) {
        descriptor_value =
            GattClientCharacteristicConfigurationDescriptorValue::Notify;
      } else if ((properties & GattCharacteristicProperties::Indicate) !=
                 GattCharacteristicProperties::None) {
        descriptor_value =
            GattClientCharacteristicConfigurationDescriptorValue::Indicate;
      } else {
        result->Error("NOTIFICATION_ERROR",
                      "Characteristic supports neither notify nor indicate");
        co_return;
      }
    }

    auto written =
        co_await characteristic
            .WriteClientCharacteristicConfigurationDescriptorWithResultAsync(
                descriptor_value);
    auto status = written.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != GattCommunicationStatus::Success) {
      result->Error("NOTIFICATION_ERROR", DescribeStatus(status));
      co_return;
    }

    auto* connection = Find(key);
    if (!connection) {
      result->Error("NOTIFICATION_ERROR", "Device not connected");
      co_return;
    }

    auto existing = connection->value_tokens.find(characteristic_key);
    if (enable) {
      if (existing == connection->value_tokens.end()) {
        auto service_uuid_string = FormatUuid(service_uuid);
        auto characteristic_uuid_string = FormatUuid(characteristic_uuid);
        // The lifetime flag is captured rather than read off `this`, so that a
        // notification still on the thread pool after teardown returns without
        // touching the manager at all.
        auto token = characteristic.ValueChanged(
            [this, lifetime, key, service_uuid_string, characteristic_uuid_string](
                GattCharacteristic const&, GattValueChangedEventArgs const& args) {
              if (!lifetime->load()) return;
              PublishValue(key, service_uuid_string, characteristic_uuid_string,
                           ToBytes(args.CharacteristicValue()));
            });
        connection->value_tokens[characteristic_key] = token;
      }
    } else if (existing != connection->value_tokens.end()) {
      characteristic.ValueChanged(existing->second);
      connection->value_tokens.erase(existing);
    }

    result->Success();
  } catch (const winrt::hresult_error& error) {
    result->Error("NOTIFICATION_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("NOTIFICATION_ERROR", "Failed to change the notification");
  }
}

winrt::fire_and_forget GattConnectionManager::PublishValue(
    std::string address, std::string service_uuid,
    std::string characteristic_uuid, std::vector<uint8_t> value) {
  auto lifetime = alive_;
  try {
    co_await ui_thread_;
    if (!lifetime->load()) co_return;
    if (on_value_) on_value_(address, service_uuid, characteristic_uuid, value);
  } catch (...) {
    // An exception leaving here would take the process with it.
  }
}

winrt::fire_and_forget GattConnectionManager::ReadDescriptor(
    uint64_t address, winrt::guid service_uuid, winrt::guid characteristic_uuid,
    winrt::guid descriptor_uuid, MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    GattCharacteristic characteristic{nullptr};
    std::string error;
    if (!FindCharacteristic(key, service_uuid, characteristic_uuid, characteristic,
                            error)) {
      result->Error("READ_DESCRIPTOR_ERROR", error);
      co_return;
    }

    auto descriptors = co_await characteristic.GetDescriptorsForUuidAsync(
        descriptor_uuid, BluetoothCacheMode::Uncached);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (descriptors.Status() != GattCommunicationStatus::Success ||
        descriptors.Descriptors().Size() == 0) {
      result->Error("READ_DESCRIPTOR_ERROR", "Descriptor not found");
      co_return;
    }

    auto read = co_await descriptors.Descriptors().GetAt(0).ReadValueAsync(
        BluetoothCacheMode::Uncached);
    auto status = read.Status();
    auto bytes = status == GattCommunicationStatus::Success
                     ? ToBytes(read.Value())
                     : std::vector<uint8_t>{};

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != GattCommunicationStatus::Success) {
      result->Error("READ_DESCRIPTOR_ERROR", DescribeStatus(status));
      co_return;
    }
    result->Success(ToEncodableBytes(bytes));
  } catch (const winrt::hresult_error& error) {
    result->Error("READ_DESCRIPTOR_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("READ_DESCRIPTOR_ERROR", "Failed to read the descriptor");
  }
}

winrt::fire_and_forget GattConnectionManager::WriteDescriptor(
    uint64_t address, winrt::guid service_uuid, winrt::guid characteristic_uuid,
    winrt::guid descriptor_uuid, std::vector<uint8_t> value,
    MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    GattCharacteristic characteristic{nullptr};
    std::string error;
    if (!FindCharacteristic(key, service_uuid, characteristic_uuid, characteristic,
                            error)) {
      result->Error("WRITE_DESCRIPTOR_ERROR", error);
      co_return;
    }

    auto descriptors = co_await characteristic.GetDescriptorsForUuidAsync(
        descriptor_uuid, BluetoothCacheMode::Uncached);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (descriptors.Status() != GattCommunicationStatus::Success ||
        descriptors.Descriptors().Size() == 0) {
      result->Error("WRITE_DESCRIPTOR_ERROR", "Descriptor not found");
      co_return;
    }

    auto written = co_await descriptors.Descriptors().GetAt(0).WriteValueWithResultAsync(
        ToBuffer(value));
    auto status = written.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != GattCommunicationStatus::Success) {
      result->Error("WRITE_DESCRIPTOR_ERROR", DescribeStatus(status));
      co_return;
    }
    result->Success();
  } catch (const winrt::hresult_error& error) {
    result->Error("WRITE_DESCRIPTOR_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("WRITE_DESCRIPTOR_ERROR", "Failed to write the descriptor");
  }
}

winrt::fire_and_forget GattConnectionManager::CreateBond(uint64_t address,
                                                         MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);
  // The result is answered before the ceremony starts, so a failure after that
  // point goes out on the bond stream instead. Tracked, since a failure before
  // it still has to reach Dart.
  auto answered = false;

  try {
    auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (!device) {
      result->Error("BOND_ERROR", "No peripheral with that address is in range");
      co_return;
    }

    auto information = co_await DeviceInformation::CreateFromIdAsync(device.DeviceId());
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    auto pairing = information.Pairing();
    if (pairing.IsPaired()) {
      answered = true;
      result->Success();
      if (on_bond_) on_bond_(key, BondState::Bonded);
      co_return;
    }

    // Pairing is a request, the way Android's createBond is: it is answered
    // once the ceremony ends, and the outcome also goes out on the bond stream.
    answered = true;
    result->Success();
    if (on_bond_) on_bond_(key, BondState::Bonding);

    // Only the ceremony that needs no passkey is accepted. Anything else would
    // sit waiting on input this plugin has nowhere to ask for.
    auto custom = pairing.Custom();
    auto token = custom.PairingRequested(
        [](DeviceInformationCustomPairing const&,
           DevicePairingRequestedEventArgs const& args) {
          if (args.PairingKind() == DevicePairingKinds::ConfirmOnly) {
            args.Accept();
          }
        });

    auto paired = co_await custom.PairAsync(DevicePairingKinds::ConfirmOnly,
                                            DevicePairingProtectionLevel::None);
    custom.PairingRequested(token);
    auto status = paired.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    auto bonded = status == DevicePairingResultStatus::Paired ||
                  status == DevicePairingResultStatus::AlreadyPaired;
    if (on_bond_) on_bond_(key, bonded ? BondState::Bonded : BondState::None);
  } catch (...) {
    if (!answered) result->Error("BOND_ERROR", "Failed to pair with the device");
    if (on_bond_) on_bond_(key, BondState::None);
  }
}

winrt::fire_and_forget GattConnectionManager::RemoveBond(uint64_t address,
                                                         MethodResult result) {
  auto lifetime = alive_;
  auto key = std::to_string(address);

  try {
    auto device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(address);
    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (!device) {
      result->Error("BOND_ERROR", "No peripheral with that address is known");
      co_return;
    }

    auto information = co_await DeviceInformation::CreateFromIdAsync(device.DeviceId());
    auto unpaired = co_await information.Pairing().UnpairAsync();
    auto status = unpaired.Status();

    co_await ui_thread_;
    if (!lifetime->load()) co_return;

    if (status != DeviceUnpairingResultStatus::Unpaired &&
        status != DeviceUnpairingResultStatus::AlreadyUnpaired) {
      result->Error("BOND_ERROR", "Failed to remove the bond");
      co_return;
    }
    result->Success();
    if (on_bond_) on_bond_(key, BondState::None);
  } catch (const winrt::hresult_error& error) {
    result->Error("BOND_ERROR", winrt::to_string(error.message()));
  } catch (...) {
    result->Error("BOND_ERROR", "Failed to remove the bond");
  }
}

}  // namespace flutter_ble_central
