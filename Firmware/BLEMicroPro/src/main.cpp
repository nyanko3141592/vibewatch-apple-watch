#include <Arduino.h>
#include <bluefruit.h>
#include "vibe_hid.h"

namespace {

enum : uint8_t { reportInput = 1, reportOutput = 2, reportFeature = 3 };

// Private relay used by VibeWatchBridge. The HID service remains the native
// Codex-facing transport; this service only injects/observes its 63-byte frames.
const uint8_t relayServiceUuid[16] = {0x41,0x57,0x45,0x42,0x49,0x56,0x2D,0x49,0x41,0x4F,0x2D,0x3A,0x00,0x00,0x60,0x83};
const uint8_t relayCommandUuid[16] = {0x41,0x57,0x45,0x42,0x49,0x56,0x2D,0x49,0x41,0x4F,0x2D,0x3A,0x01,0x00,0x60,0x83};
const uint8_t relayStatusUuid[16]  = {0x41,0x57,0x45,0x42,0x49,0x56,0x2D,0x49,0x41,0x4F,0x2D,0x3A,0x02,0x00,0x60,0x83};

class VibeHidService : public BLEService {
 public:
  VibeHidService()
      : BLEService(UUID16_SVC_HUMAN_INTERFACE_DEVICE),
        keyboardInput(UUID16_CHR_REPORT), consumerInput(UUID16_CHR_REPORT),
        pointerInput(UUID16_CHR_REPORT), vendorInput(UUID16_CHR_REPORT),
        vendorOutput(UUID16_CHR_REPORT), vendorFeature(UUID16_CHR_REPORT),
        protocolMode(UUID16_CHR_PROTOCOL_MODE), controlPoint(UUID16_CHR_HID_CONTROL_POINT) {}

  err_t begin() override {
    VERIFY_STATUS(BLEService::begin());

    protocolMode.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE_WO_RESP);
    protocolMode.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
    protocolMode.setFixedLen(1);
    VERIFY_STATUS(protocolMode.begin());
    protocolMode.write8(1);

    VERIFY_STATUS(beginInput(keyboardInput, 1, 8));
    VERIFY_STATUS(beginInput(consumerInput, 2, 2));
    VERIFY_STATUS(beginInput(pointerInput, 3, 5));
    VERIFY_STATUS(beginInput(vendorInput, vibe::vendorReportId, vibe::reportLength));

    vendorOutput.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
    vendorOutput.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
    vendorOutput.setFixedLen(vibe::reportLength);
    vendorOutput.setReportRefDescriptor(vibe::vendorReportId, reportOutput);
    vendorOutput.setWriteCallback(onHostOutput);
    VERIFY_STATUS(vendorOutput.begin());

    vendorFeature.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
    vendorFeature.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
    vendorFeature.setFixedLen(vibe::reportLength);
    vendorFeature.setReportRefDescriptor(vibe::vendorReportId, reportFeature);
    VERIFY_STATUS(vendorFeature.begin());

    BLECharacteristic reportMap(UUID16_CHR_REPORT_MAP);
    reportMap.setTempMemory();
    reportMap.setProperties(CHR_PROPS_READ);
    reportMap.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
    reportMap.setFixedLen(sizeof(vibe::reportMap));
    VERIFY_STATUS(reportMap.begin());
    reportMap.write(vibe::reportMap, sizeof(vibe::reportMap));

    const uint8_t hidInfo[] = {0x00, 0x01, 0x00, 0x01};
    BLECharacteristic info(UUID16_CHR_HID_INFORMATION);
    info.setTempMemory();
    info.setProperties(CHR_PROPS_READ);
    info.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
    info.setFixedLen(sizeof(hidInfo));
    VERIFY_STATUS(info.begin());
    info.write(hidInfo, sizeof(hidInfo));

    controlPoint.setProperties(CHR_PROPS_WRITE_WO_RESP);
    controlPoint.setPermission(SECMODE_NO_ACCESS, SECMODE_ENC_NO_MITM);
    controlPoint.setFixedLen(1);
    VERIFY_STATUS(controlPoint.begin());
    return ERROR_NONE;
  }

  bool sendVendor(const uint8_t* data, uint16_t len) {
    return len == vibe::reportLength && vendorInput.notify(data, len);
  }

  static void setOutputHandler(void (*handler)(const uint8_t*, uint16_t)) { outputHandler = handler; }

 private:
  BLECharacteristic keyboardInput, consumerInput, pointerInput;
  BLECharacteristic vendorInput, vendorOutput, vendorFeature;
  BLECharacteristic protocolMode, controlPoint;
  static void (*outputHandler)(const uint8_t*, uint16_t);

  err_t beginInput(BLECharacteristic& characteristic, uint8_t id, uint16_t len) {
    characteristic.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
    characteristic.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
    characteristic.setFixedLen(len);
    characteristic.setReportRefDescriptor(id, reportInput);
    return characteristic.begin();
  }

  static void onHostOutput(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t len) {
    if (outputHandler) outputHandler(data, len);
  }
};

void (*VibeHidService::outputHandler)(const uint8_t*, uint16_t) = nullptr;

VibeHidService hid;
BLEDis deviceInfo;
BLEBas battery;
BLEService relayService(relayServiceUuid);
BLECharacteristic relayCommand(relayCommandUuid);
BLECharacteristic relayStatus(relayStatusUuid);
String rpcBuffer;

void sendFramedJson(String payload) {
  if (!payload.endsWith("\r\n")) payload += "\r\n";
  for (size_t offset = 0; offset < payload.length();) {
    uint8_t report[vibe::reportLength] = {};
    const size_t count = min(static_cast<size_t>(vibe::rpcChunkLength), payload.length() - offset);
    report[0] = vibe::jsonRpcChannel;
    report[1] = static_cast<uint8_t>(count);
    memcpy(report + 2, payload.c_str() + offset, count);
    hid.sendVendor(report, sizeof(report));
    offset += count;
    if (offset < payload.length()) delay(8);
  }
}

int rpcId(const String& json) {
  int marker = json.indexOf("\"id\"");
  if (marker < 0) marker = json.indexOf("\"i\"");
  if (marker < 0) return -1;
  marker = json.indexOf(':', marker);
  return marker < 0 ? -1 : json.substring(marker + 1).toInt();
}

String rpcMethod(const String& json) {
  int marker = json.indexOf("\"method\"");
  if (marker < 0) marker = json.indexOf("\"m\"");
  if (marker < 0) return "";
  int colon = json.indexOf(':', marker);
  int first = json.indexOf('"', colon + 1);
  int last = json.indexOf('"', first + 1);
  return first < 0 || last < 0 ? "" : json.substring(first + 1, last);
}

void processHostFrame(const uint8_t* data, uint16_t len) {
  if (len != vibe::reportLength || data[0] != vibe::jsonRpcChannel || data[1] > vibe::rpcChunkLength) return;
  relayStatus.notify(data, len);
  for (uint8_t i = 0; i < data[1]; ++i) rpcBuffer += static_cast<char>(data[i + 2]);
  if (!rpcBuffer.endsWith("}") && !rpcBuffer.endsWith("}\r\n")) return;

  const String method = rpcMethod(rpcBuffer);
  const int id = rpcId(rpcBuffer);
  if (id >= 0 && method.length()) {
    String result = "{\"ok\":1}";
    if (method == "device.status") {
      result = "{\"version\":\"v1.0\",\"profile_index\":0,\"layer_index\":1,\"battery\":100,\"is_charging\":true}";
    } else if (method == "sys.version") {
      result = "{\"version\":\"v1.0\"}";
    }
    sendFramedJson("{\"id\":" + String(id) + ",\"method\":\"" + method + "\",\"result\":" + result + "}");
  }
  rpcBuffer = "";
}

void onRelayCommand(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t len) {
  if (len == vibe::reportLength) hid.sendVendor(data, len);
}

void startAdvertising() {
  Bluefruit.Advertising.stop();
  Bluefruit.Advertising.clearData();
  Bluefruit.ScanResponse.clearData();
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_HID_KEYBOARD);
  Bluefruit.Advertising.addService(hid);
  Bluefruit.Advertising.addName();
  Bluefruit.ScanResponse.addService(relayService);
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.configAttrTableSize(4096);
  Bluefruit.begin(1, 0);
  Bluefruit.setName(vibe::deviceName);
  Bluefruit.setTxPower(4);
  Bluefruit.Security.setIOCaps(false, false, false);
  Bluefruit.Security.setPairPasskeyCallback(nullptr);

  deviceInfo.setManufacturer(vibe::manufacturer);
  deviceInfo.setModel(vibe::model);
  deviceInfo.setFirmwareRev(vibe::firmwareVersion);
  const char pnp[] = {0x01, 0x3A, 0x30, 0x60, static_cast<char>(0x83), 0x01, 0x00};
  deviceInfo.setPNPID(pnp, sizeof(pnp));
  deviceInfo.begin();
  battery.begin();
  battery.write(100);

  VibeHidService::setOutputHandler(processHostFrame);
  hid.begin();

  relayService.begin();
  relayCommand.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  relayCommand.setPermission(SECMODE_NO_ACCESS, SECMODE_ENC_NO_MITM);
  relayCommand.setMaxLen(vibe::reportLength);
  relayCommand.setWriteCallback(onRelayCommand);
  relayCommand.begin();
  relayStatus.setProperties(CHR_PROPS_NOTIFY);
  relayStatus.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
  relayStatus.setMaxLen(vibe::reportLength);
  relayStatus.begin();

  startAdvertising();
}

void loop() {
  delay(20);
}
