#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPUpdate.h>
#include <PsychicMqttClient.h>
#include <Preferences.h>
#include <WebServer.h>
#include <esp_mac.h>
#include <mbedtls/md.h>
#include "time.h"
#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h"
#include "config.h"

#ifndef RING_ALLOW_UNSIGNED_COMMANDS
#define RING_ALLOW_UNSIGNED_COMMANDS false
#endif

// Hardware Pins
#define BUZZER_PIN        13 // Active HIGH

#ifndef WIFI_RETRY_INTERVAL_MS
#define WIFI_RETRY_INTERVAL_MS 3000
#endif

#ifndef MQTT_WIFI_RECOVERY_MS
#define MQTT_WIFI_RECOVERY_MS 30000
#endif

// OTA state
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

// Direction Configuration
// Set to true if walking from Right (Zone R) to Left (Zone L) is an "Enter" event
// Set to false if walking from Left (Zone L) to Right (Zone R) is an "Enter" event
bool IS_RIGHT_TO_LEFT_ENTER = false;

// Detection Constants (Optimized)
int MOTION_THRESHOLD = 24;      // Pick up softer per-pixel changes from partial crossings
int TRIGGER_THRESHOLD_L = 700;  // Lower left trigger so weaker body motion still arms detection
int TRIGGER_THRESHOLD_R = 500;  // Right zone remains easier to trigger than left
int NOISE_THRESHOLD_BOTH = 1800; // Re-zero only when both zones are heavily disturbed
int NOISE_THRESHOLD_TOTAL = 6200; // Whole-frame disturbance threshold
int CLEAR_THRESHOLD_L = 180;    // Re-arm sooner after lighter motion tails off
int CLEAR_THRESHOLD_R = 180;
unsigned long CLEAR_HOLD_MS = 250; // Quiet period before the detector is ready again
int ZONE_L = 60;                // Left line boundary (0-160)
int ZONE_R = 100;               // Right line boundary (0-160)
unsigned long COOLDOWN = 700;   // ms between counts
const int MAX_PASSENGER_COUNT = 40;

// Globals
int passengerCount = 0;
int currentState = 0;           // 0=None, 1=Left, 2=Right
unsigned long lastCountTime = 0;
unsigned long lastMotionTime = 0;
unsigned long clearStartTime = 0;
uint8_t background[160 * 80];   // Background reference (160x80 ROI)
char bus_mac[18];
char reported_bus_mac[18];
char mqttClientId[40];
bool wifiConnected = false;
bool bgInitialized = false;
bool mqttConfigured = false;
char mqttUri[128];
bool ringPending = false;
bool mqttConnectAttempted = false;
bool mqttNeedsStopBeforeReconnect = false;
unsigned long lastMqttAttempt = 0, lastMqttStop = 0;
unsigned long lastWifiRetry = 0, mqttDisconnectedSince = 0;
uint8_t wifiNetworkIndex = 0;
char mqttStatusTopic[96];
char mqttStatusOnlinePayload[256];
char mqttStatusOfflinePayload[256];
char mqttRingTopic[96];
char mqttBusIdCommandTopic[96];
unsigned long lastAcceptedRingTimestamp = 0;

PsychicMqttClient mqttClient;
Preferences preferences;
WebServer httpServer(80);
bool isConfiguredWifiNetwork(const char* ssid) {
  return ssid != nullptr &&
         strlen(ssid) > 0 &&
         strcmp(ssid, "fallback_ssid_1") != 0 &&
         strcmp(ssid, "fallback_ssid_2") != 0;
}

uint8_t wifiNetworkCount() {
  uint8_t count = 1;
  if (isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) count++;
  if (isConfiguredWifiNetwork(WIFI_FALLBACK_2_SSID)) count++;
  return count;
}

const char* currentWifiSsid() {
  if (wifiNetworkIndex == 1 && isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    return WIFI_FALLBACK_1_SSID;
  }
  if (wifiNetworkIndex == 2 && isConfiguredWifiNetwork(WIFI_FALLBACK_2_SSID)) {
    return WIFI_FALLBACK_2_SSID;
  }
  return WIFI_SSID;
}

const char* currentWifiPassword() {
  if (wifiNetworkIndex == 1 && isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    return WIFI_FALLBACK_1_PASSWORD;
  }
  if (wifiNetworkIndex == 2 && isConfiguredWifiNetwork(WIFI_FALLBACK_2_SSID)) {
    return WIFI_FALLBACK_2_PASSWORD;
  }
  return WIFI_PASSWORD;
}

void startWiFiAttempt(bool rotateNetwork) {
  uint8_t networkCount = wifiNetworkCount();
  if (rotateNetwork && networkCount > 1) {
    wifiNetworkIndex = (wifiNetworkIndex + 1) % networkCount;
  } else if (networkCount == 1) {
    wifiNetworkIndex = 0;
  }

  lastWifiRetry = millis();
  mqttConnectAttempted = false;

  const char* ssid = currentWifiSsid();
  Serial.printf("WiFi %s ssid=%s index=%u status=%d\n",
                rotateNetwork ? "retry" : "begin",
                ssid,
                wifiNetworkIndex,
                WiFi.status());

  WiFi.disconnect(false, false);
  WiFi.begin(ssid, currentWifiPassword());
}

void handleWiFi() {
  wl_status_t status = WiFi.status();
  if (status == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      Serial.println("WiFi connected: " + WiFi.localIP().toString());
      Serial.println("Live view: http://" + WiFi.localIP().toString());
    }

    if (!mqttClient.connected()) {
      if (mqttDisconnectedSince == 0) {
        mqttDisconnectedSince = millis();
      } else if (millis() - mqttDisconnectedSince >= MQTT_WIFI_RECOVERY_MS) {
        Serial.println("WiFi connected but MQTT offline for too long, retrying WiFi association");
        startWiFiAttempt(true);
      }
    } else {
      mqttDisconnectedSince = 0;
    }
    return;
  }

  if (wifiConnected) {
    wifiConnected = false;
    mqttConnectAttempted = false;
    mqttNeedsStopBeforeReconnect = true;
    mqttDisconnectedSince = millis();
    Serial.printf("WiFi disconnected status=%d\n", status);
    startWiFiAttempt(false);
    return;
  }

  if (millis() - lastWifiRetry >= WIFI_RETRY_INTERVAL_MS) {
    startWiFiAttempt(true);
  }
}

// Audio Feedback
void beep(int duration) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(duration);
  digitalWrite(BUZZER_PIN, LOW);
}

int clampPassengerCount(int count) {
  if (count < 0) return 0;
  if (count > MAX_PASSENGER_COUNT) return MAX_PASSENGER_COUNT;
  return count;
}

void savePassengerCount() {
  passengerCount = clampPassengerCount(passengerCount);
  preferences.putInt("cnt", passengerCount);
}

// MQTT Functions
void sendMQTT(String dir) {
  if (!mqttClient.connected()) return;
  char buf[224];
  snprintf(
    buf,
    sizeof(buf),
    "{\"bus_id\":\"%s\",\"bus_mac\":\"%s\",\"bus_name\":\"%s\",\"dir\":\"%s\",\"count\":%d,\"count_source\":\"door\",\"t\":%ld}",
    BUS_ID_ALIAS,
    reported_bus_mac,
    BUS_NAME_ALIAS,
    dir.c_str(),
    passengerCount,
    millis()/1000
  );
  mqttClient.publish(MQTT_TOPIC_DETECTION, 1, false, buf);
}

void buildStatusPayload(bool isOnline, char* buffer, size_t bufferSize) {
  snprintf(
    buffer,
    bufferSize,
    "{\"bus_id\":\"%s\",\"bus_mac\":\"%s\",\"bus_name\":\"%s\",\"component\":\"esp32_cam\",\"is_online\":%s,\"rssi\":%ld,\"uptime\":%lu,\"count\":%d,\"person_count\":%d,\"count_source\":\"status\"}",
    BUS_ID_ALIAS,
    reported_bus_mac,
    BUS_NAME_ALIAS,
    isOnline ? "true" : "false",
    isOnline && WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : -100,
    millis() / 1000,
    passengerCount,
    passengerCount
  );
}

void publishStatus() {
  if (!mqttClient.connected()) return;
  buildStatusPayload(true, mqttStatusOnlinePayload, sizeof(mqttStatusOnlinePayload));
  mqttClient.publish(mqttStatusTopic, 1, true, mqttStatusOnlinePayload);
}

void buildMqttClientId() {
  char compactMac[13];
  int compactIndex = 0;
  for (size_t i = 0; bus_mac[i] != '\0' && compactIndex < (int)sizeof(compactMac) - 1; i++) {
    if (bus_mac[i] != ':') {
      compactMac[compactIndex++] = bus_mac[i];
    }
  }
  compactMac[compactIndex] = '\0';
  snprintf(mqttClientId, sizeof(mqttClientId), "BusCam-%s", compactMac);
}

void performOTA() {
  otaPending = false;
  if (otaUrl.length() == 0) return;

  Serial.println("🔄 Starting OTA update...");
  Serial.printf("📥 Downloading: %s\n", otaUrl.c_str());
  httpUpdate.rebootOnUpdate(false);

  const bool isHttps = otaUrl.startsWith("https://");
  t_httpUpdate_return ret;

  if (isHttps) {
    WiFiClientSecure secureClient;
    if (strlen(OTA_ROOT_CA) > 0) {
      secureClient.setCACert(OTA_ROOT_CA);
    } else if (OTA_ALLOW_INSECURE_TLS) {
      Serial.println("⚠️ OTA TLS verification disabled.");
      secureClient.setInsecure();
    } else {
      Serial.println("❌ OTA blocked: HTTPS URL requires OTA_ROOT_CA or OTA_ALLOW_INSECURE_TLS.");
      return;
    }
    ret = httpUpdate.update(secureClient, otaUrl);
  } else {
    WiFiClient client;
    ret = httpUpdate.update(client, otaUrl);
  }

  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("❌ OTA Failed (%d): %s\n", httpUpdate.getLastError(), httpUpdate.getLastErrorString().c_str());
      break;
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("ℹ️ No updates available");
      break;
    case HTTP_UPDATE_OK:
      Serial.println("✅ OTA Success! Rebooting...");
      delay(1000);
      ESP.restart();
      break;
  }
}

String extractJsonStringField(const String& message, const char* fieldName) {
  String marker = String("\"") + fieldName + "\":\"";
  int valueStart = message.indexOf(marker);
  if (valueStart < 0) return "";
  valueStart += marker.length();
  int valueEnd = message.indexOf("\"", valueStart);
  if (valueEnd <= valueStart) return "";
  return message.substring(valueStart, valueEnd);
}

unsigned long extractJsonUnsignedField(const String& message, const char* fieldName) {
  String marker = String("\"") + fieldName + "\":";
  int valueStart = message.indexOf(marker);
  if (valueStart < 0) return 0;
  valueStart += marker.length();
  while (valueStart < message.length() && message[valueStart] == ' ') {
    valueStart++;
  }
  int valueEnd = valueStart;
  while (valueEnd < message.length() && isDigit(message[valueEnd])) {
    valueEnd++;
  }
  if (valueEnd <= valueStart) return 0;
  return strtoul(message.substring(valueStart, valueEnd).c_str(), nullptr, 10);
}

const char* ringCommandSecret() {
  if (strlen(RING_COMMAND_SECRET) > 0) {
    return RING_COMMAND_SECRET;
  }
  return API_KEY;
}

String computeCommandSignature(const char* command, const char* busMac, unsigned long timestamp) {
  const char* secret = ringCommandSecret();
  if (secret == nullptr || strlen(secret) == 0) {
    return "";
  }

  char payload[96];
  snprintf(payload, sizeof(payload), "%s|%s|%lu", command, busMac, timestamp);

  const mbedtls_md_info_t* mdInfo = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (mdInfo == nullptr) {
    return "";
  }

  unsigned char digest[32];
  if (mbedtls_md_hmac(
        mdInfo,
        reinterpret_cast<const unsigned char*>(secret),
        strlen(secret),
        reinterpret_cast<const unsigned char*>(payload),
        strlen(payload),
        digest) != 0) {
    return "";
  }

  static const char kHex[] = "0123456789abcdef";
  char hex[65];
  for (size_t i = 0; i < sizeof(digest); i++) {
    hex[(i * 2)] = kHex[(digest[i] >> 4) & 0x0F];
    hex[(i * 2) + 1] = kHex[digest[i] & 0x0F];
  }
  hex[64] = '\0';
  return String(hex);
}

String computeRingSignature(const char* busMac, unsigned long timestamp) {
  return computeCommandSignature("ring", busMac, timestamp);
}

bool matchesBusIdentity(const String& target) {
  if (target == reported_bus_mac || target == bus_mac) return true;
  if (strlen(BUS_ID_ALIAS) > 0 && target == BUS_ID_ALIAS) return true;
  if (strlen(BUS_NAME_ALIAS) > 0 && target == BUS_NAME_ALIAS) return true;
  return false;
}

void resetPassengerCount(const char* reason) {
  passengerCount = 0;
  savePassengerCount();
  currentState = 0;
  clearStartTime = 0;
  publishStatus();
  Serial.printf("🔄 Passenger count reset (%s)\n", reason);
}

void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup) {
  String message = String(payload);
  String topicString = String(topic);
  if (topicString == mqttRingTopic || topicString == mqttBusIdCommandTopic) {
    bool isRingCommand = message.indexOf("\"command\":\"ring\"") >= 0;
    bool isResetCountCommand = message.indexOf("\"command\":\"reset_count\"") >= 0;
    const char* commandName = isResetCountCommand ? "reset_count" : "ring";
    String targetBusMac = extractJsonStringField(message, "bus_mac");
    unsigned long timestamp = extractJsonUnsignedField(message, "timestamp");
    String signature = extractJsonStringField(message, "sig");
    bool matchesBusMac = matchesBusIdentity(targetBusMac);
    bool validTimestamp = timestamp > lastAcceptedRingTimestamp;
    bool validSignature = signature.length() > 0 &&
                          signature == computeCommandSignature(commandName, targetBusMac.c_str(), timestamp);
    bool acceptsSignature = validSignature || RING_ALLOW_UNSIGNED_COMMANDS;

    if ((isRingCommand || isResetCountCommand) && matchesBusMac && validTimestamp && acceptsSignature) {
      lastAcceptedRingTimestamp = timestamp;
      if (isResetCountCommand) {
        resetPassengerCount("parking command");
      } else {
        ringPending = true;
        Serial.printf(
          "Ring command accepted for %s%s\n",
          targetBusMac.c_str(),
          validSignature ? "" : " without signature verification"
        );
      }
    } else {
      Serial.printf(
        "Command ignored: ring=%d reset=%d mac=%d timestamp=%d signature=%d allow_unsigned=%d topic=%s target=%s\n",
        isRingCommand,
        isResetCountCommand,
        matchesBusMac,
        validTimestamp,
        validSignature,
        RING_ALLOW_UNSIGNED_COMMANDS,
        topic,
        targetBusMac.c_str()
      );
    }
    return;
  }
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());

  if (String(topic).indexOf("ota") >= 0) {
    if (!OTA_ENABLED) {
      Serial.println("⚠️ OTA command ignored because OTA is disabled in config.");
      return;
    }

    const String targetMac = extractJsonStringField(message, "mac");
    const bool isForAll = targetMac.length() == 0 || targetMac == "ALL";
    const bool matchesBusMac =
        targetMac == reported_bus_mac || targetMac == bus_mac;

    if (!isForAll && !matchesBusMac) {
      Serial.printf("ℹ️ OTA command ignored for MAC %s\n", targetMac.c_str());
      return;
    }

    otaUrl = extractJsonStringField(message, "url");
    otaVersion = extractJsonStringField(message, "version");

    if (otaUrl.length() == 0 || otaVersion.length() == 0) {
      Serial.println("⚠️ OTA command missing url or version.");
      return;
    }

    if (otaVersion == FIRMWARE_VERSION) {
      Serial.printf("ℹ️ OTA skipped. Already on version %s\n", FIRMWARE_VERSION);
      return;
    }

    Serial.printf("📥 OTA Update requested: v%s for %s\n",
                  otaVersion.c_str(),
                  isForAll ? "ALL" : targetMac.c_str());
    otaPending = true;
  }
}

void setupMQTT() {
  if ((strlen(MQTT_URI) == 0 || strcmp(MQTT_URI, "your_mqtt_uri") == 0) &&
      (strlen(MQTT_SERVER) == 0 || strcmp(MQTT_SERVER, "your_mqtt_host") == 0)) {
    Serial.println("⚠️ MQTT Blocked (Placeholder detected in config.h)");
    return;
  }
  snprintf(mqttUri, sizeof(mqttUri), "mqtt://%s:%d", MQTT_SERVER, MQTT_PORT);
  Serial.printf("🔌 MQTT Configured: %s\n", mqttUri);

  if (strlen(MQTT_URI) > 0 && strcmp(MQTT_URI, "your_mqtt_uri") != 0) {
    snprintf(mqttUri, sizeof(mqttUri), "%s", MQTT_URI);
  }

  bool isWebsocket = strncmp(mqttUri, "ws://", 5) == 0 || strncmp(mqttUri, "wss://", 6) == 0;
  if (isWebsocket) {
    const char* pathStart = strchr(mqttUri + (strncmp(mqttUri, "wss://", 6) == 0 ? 6 : 5), '/');
    if (pathStart == nullptr) {
      size_t baseLen = strlen(mqttUri);
      if (baseLen + 6 < sizeof(mqttUri)) {
        strncat(mqttUri, "/mqtt", sizeof(mqttUri) - baseLen - 1);
      }
    }
  }

  if ((strncmp(mqttUri, "wss://", 6) == 0 || strncmp(mqttUri, "mqtts://", 8) == 0) && strlen(MQTT_ROOT_CA) > 0) {
    mqttClient.setCACert(MQTT_ROOT_CA);
  }

  mqttClient.onMessage(mqttCallback);
  mqttClient.onConnect([](bool sessionPresent) {
    mqttConnectAttempted = false;
    mqttNeedsStopBeforeReconnect = false;
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(mqttRingTopic, 1);
    if (strlen(mqttBusIdCommandTopic) > 0) {
      mqttClient.subscribe(mqttBusIdCommandTopic, 1);
    }
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
    publishStatus();
  });
  mqttClient.onDisconnect([](bool sessionPresent) {
    mqttConnectAttempted = false;
    mqttNeedsStopBeforeReconnect = true;
    Serial.println("MQTT disconnected");
  });
  mqttClient.onError([](esp_mqtt_error_codes_t error) {
    mqttConnectAttempted = false;
    mqttNeedsStopBeforeReconnect = true;
    Serial.printf("MQTT error type=%d tls=%d stack=%d sock=%d\n",
      error.error_type,
      error.esp_tls_last_esp_err,
      error.esp_tls_stack_err,
      error.esp_transport_sock_errno
    );
  });
  mqttClient.setServer(mqttUri);
  mqttClient.setClientId(mqttClientId);
  snprintf(mqttStatusTopic, sizeof(mqttStatusTopic), "sut/bus/%s/status", reported_bus_mac);
  snprintf(mqttRingTopic, sizeof(mqttRingTopic), "%s/%s/ring", MQTT_TOPIC_RING_PREFIX, reported_bus_mac);
  if (strlen(BUS_ID_ALIAS) > 0) {
    snprintf(mqttBusIdCommandTopic, sizeof(mqttBusIdCommandTopic), "%s/%s/ring", MQTT_TOPIC_RING_PREFIX, BUS_ID_ALIAS);
  } else {
    mqttBusIdCommandTopic[0] = '\0';
  }
  Serial.printf("MQTT Ring topic: %s\n", mqttRingTopic);
  if (strlen(mqttBusIdCommandTopic) > 0) {
    Serial.printf("MQTT Bus ID command topic: %s\n", mqttBusIdCommandTopic);
  }
  buildStatusPayload(true, mqttStatusOnlinePayload, sizeof(mqttStatusOnlinePayload));
  buildStatusPayload(false, mqttStatusOfflinePayload, sizeof(mqttStatusOfflinePayload));
  mqttClient.setWill(mqttStatusTopic, 1, true, mqttStatusOfflinePayload);
  // We already retry from loop(); enabling the library auto-reconnect as well
  // can double-start the underlying ESP-IDF client after a disconnect.
  mqttClient.setAutoReconnect(false);
  mqttClient.setKeepAlive(10);
  Serial.printf("MQTT Client ID: %s\n", mqttClientId);
  Serial.printf("MQTT Final URI: %s\n", mqttUri);
  mqttConfigured = true;
}

void reconnectMQTT() {
  if (!mqttConfigured) return;
  if (mqttConnectAttempted) return;
  if (mqttNeedsStopBeforeReconnect) {
    mqttClient.forceStop();
    mqttNeedsStopBeforeReconnect = false;
    lastMqttStop = millis();
    return;
  }

  if (lastMqttStop != 0 && millis() - lastMqttStop < 500) return;
  if (millis() - lastMqttAttempt < 10000) return;
  lastMqttAttempt = millis();
  mqttConnectAttempted = true;
  Serial.println("🔌 MQTT Reconnecting...");
  mqttClient.connect();
}

// ── Overlay Drawing ───────────────────────────────────────────────────────────

static void px(uint8_t *buf, int w, int h, int x, int y, uint8_t v) {
  if (x >= 0 && x < w && y >= 0 && y < h) buf[y * w + x] = v;
}

// 4×5 bitmap glyphs: index 0='L', 1='R'
static const uint8_t GLYPHS[][5] = {
  {0b10000000, 0b10000000, 0b10000000, 0b10000000, 0b11100000}, // L
  {0b11100000, 0b10010000, 0b11100000, 0b10100000, 0b10010000}, // R
};
static void drawGlyph(uint8_t *buf, int w, int h, int cx, int cy, int g, uint8_t col) {
  for (int r = 0; r < 5; r++)
    for (int c = 0; c < 4; c++)
      if (GLYPHS[g][r] & (0x80 >> c))
        px(buf, w, h, cx + c, cy + r, col);
}

void drawOverlay(uint8_t *buf, int w, int h) {
  const int y0 = 20, y1 = 100;

  // Dashed ROI top/bottom borders
  for (int x = 0; x < w; x++) {
    uint8_t v = (x / 3) % 2 ? 255 : 0;
    buf[y0 * w + x] = v;
    buf[(y1 - 1) * w + x] = v;
  }

  // Zone boundary lines — white line + black shadow for contrast on any bg
  for (int y = y0; y < y1; y++) {
    px(buf, w, h, ZONE_L - 1, y, 0);   px(buf, w, h, ZONE_L, y, 255);
    px(buf, w, h, ZONE_R,     y, 255); px(buf, w, h, ZONE_R + 1, y, 0);
  }

  // 'L' label centred in left zone, 'R' in right zone
  int midY = (y0 + y1) / 2 - 2;
  int lx   = ZONE_L / 2 - 2;
  int rx   = ZONE_R + (w - ZONE_R) / 2 - 2;
  drawGlyph(buf, w, h, lx + 1, midY + 1, 0, 0);  drawGlyph(buf, w, h, lx, midY, 0, 255);
  drawGlyph(buf, w, h, rx + 1, midY + 1, 1, 0);  drawGlyph(buf, w, h, rx, midY, 1, 255);

  // Enter-direction arrow in the dead zone between the two lines
  // →  if L→R = enter (IS_RIGHT_TO_LEFT_ENTER == false)
  // ←  if R→L = enter (IS_RIGHT_TO_LEFT_ENTER == true)
  int ax = (ZONE_L + ZONE_R) / 2;
  int ay = midY + 8;
  // horizontal shaft
  for (int i = -3; i <= 3; i++) px(buf, w, h, ax + i, ay, 255);
  if (!IS_RIGHT_TO_LEFT_ENTER) {
    // arrowhead pointing right
    px(buf, w, h, ax + 2, ay - 1, 255); px(buf, w, h, ax + 3, ay, 255);
    px(buf, w, h, ax + 2, ay + 1, 255);
  } else {
    // arrowhead pointing left
    px(buf, w, h, ax - 2, ay - 1, 255); px(buf, w, h, ax - 3, ay, 255);
    px(buf, w, h, ax - 2, ay + 1, 255);
  }
}

// ── HTTP Handlers ─────────────────────────────────────────────────────────────
void handleCapture() {
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) { httpServer.send(503, "text/plain", "Camera error"); return; }

  drawOverlay(fb->buf, fb->width, fb->height);

  uint8_t *jpg_buf = nullptr;
  size_t jpg_len = 0;
  bool ok = frame2jpg(fb, 80, &jpg_buf, &jpg_len);
  esp_camera_fb_return(fb);

  if (!ok) { httpServer.send(503, "text/plain", "JPEG encode error"); return; }

  httpServer.setContentLength(jpg_len);
  httpServer.sendHeader("Cache-Control", "no-cache, no-store");
  httpServer.sendHeader("Access-Control-Allow-Origin", "*");
  httpServer.send(200, "image/jpeg", "");
  WiFiClient client = httpServer.client();
  client.write(jpg_buf, jpg_len);
  free(jpg_buf);
}

void handleRoot() {
  httpServer.send(200, "text/html",
    "<!DOCTYPE html><html><head>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>Bus Cam</title>"
    "<style>"
    "body{background:#111;display:flex;flex-direction:column;align-items:center;"
    "justify-content:center;height:100vh;margin:0;color:#fff;font-family:sans-serif}"
    "img{image-rendering:pixelated;width:100%;max-width:480px;border:1px solid #333}"
    "p{margin:8px 0;font-size:13px;color:#888}"
    "</style></head><body>"
    "<img id='cam' src='/capture'>"
    "<p id='info'>Connecting...</p>"
    "<script>"
    "const img=document.getElementById('cam');"
    "const info=document.getElementById('info');"
    "let last=Date.now(),frames=0;"
    "function next(){"
    "  const t=Date.now();"
    "  img.src='/capture?'+t;"
    "  img.onload=()=>{"
    "    frames++;"
    "    if(t-last>=1000){info.textContent=frames+' fps';frames=0;last=t;}"
    "    next();"
    "  };"
    "  img.onerror=()=>setTimeout(next,1000);"
    "}"
    "next();"
    "</script></body></html>"
  );
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  
  // Read the burned-in station MAC directly from efuse.
  uint64_t chipid = ESP.getEfuseMac();
  snprintf(
    bus_mac,
    sizeof(bus_mac),
    "%02X:%02X:%02X:%02X:%02X:%02X",
    (uint8_t)(chipid >> 40),
    (uint8_t)(chipid >> 32),
    (uint8_t)(chipid >> 24),
    (uint8_t)(chipid >> 16),
    (uint8_t)(chipid >> 8),
    (uint8_t)chipid
  );
  if (strlen(BUS_MAC_ALIAS) > 0) {
    snprintf(reported_bus_mac, sizeof(reported_bus_mac), "%s", BUS_MAC_ALIAS);
  } else {
    snprintf(reported_bus_mac, sizeof(reported_bus_mac), "%s", bus_mac);
  }
  buildMqttClientId();

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM; config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM; config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_GRAYSCALE;
  config.frame_size = FRAMESIZE_QQVGA;
  config.jpeg_quality = 12;
  config.fb_count = 2;

  if (esp_camera_init(&config) != ESP_OK) { Serial.println("❌ Cam Fail"); delay(1000); ESP.restart(); }

  // Stabilization delay
  Serial.println("⌛ Stabilizing camera...");
  delay(2000);

  preferences.begin("bus", false);
  passengerCount = clampPassengerCount(preferences.getInt("cnt", 0));
  preferences.putInt("cnt", passengerCount);

  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);
  startWiFiAttempt(false);
  setupMQTT();

  httpServer.on("/", handleRoot);
  httpServer.on("/capture", handleCapture);
  httpServer.begin();
  Serial.println("🌐 HTTP server started on port 80");

  Serial.println("🚌 Optimized Bus Cam Ready (Stripped-Down Serial)");
  Serial.printf("ESP32-CAM MAC Address: %s\n", bus_mac);
  Serial.printf("Direction Mode: R->L is %s\n", IS_RIGHT_TO_LEFT_ENTER ? "ENTER" : "EXIT");
}

void loop() {
  handleWiFi();
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) reconnectMQTT();
    if (ringPending) {
      ringPending = false;
      beep(500);
    }
    if (otaPending) performOTA();
  }
  httpServer.handleClient();

  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) return;

  // ROI: y=[20-100]
  int motionL = 0, motionR = 0;
  int startY = 20, endY = 100;
  int totalPixels = 160 * (endY - startY);
  
  if (!bgInitialized) {
    for (int i = 0; i < totalPixels; i++) background[i] = fb->buf[startY * 160 + i];
    bgInitialized = true;
    Serial.println("📸 Background Baseline Initialized");
  }

  // Count motion and update background
  for (int y = startY; y < endY; y++) {
    for (int x = 0; x < 160; x++) {
      int idx = y * 160 + x;
      int bgIdx = (y - startY) * 160 + x;
      uint8_t p = fb->buf[idx];
      uint8_t bg = background[bgIdx];
      
      int diff = abs((int)p - (int)bg);
      if (diff > MOTION_THRESHOLD) {
        if (x < ZONE_L) motionL++;
        else if (x > ZONE_R) motionR++;
        
        // Foreground: Sigma-Delta (1 step per frame) prevents ghosting
        if (p > bg) background[bgIdx] = bg + 1;
        else if (p < bg) background[bgIdx] = bg - 1;
      } else {
        // Background: Exponential Moving Average for faster lighting adaptation
        background[bgIdx] = (uint8_t)(((int)bg * 7 + (int)p) >> 3);
      }
    }
  }

  // Noise Filter: only treat it as global noise when both zones surge together.
  if (motionL > NOISE_THRESHOLD_BOTH &&
      motionR > NOISE_THRESHOLD_BOTH &&
      (motionL + motionR) > NOISE_THRESHOLD_TOTAL) {
    bgInitialized = false; 
    currentState = 0;
    clearStartTime = 0;
    Serial.println("🌫️ Massive Noise - Re-zeroing...");
    esp_camera_fb_return(fb);
    return;
  }

  bool triggerL = (motionL > TRIGGER_THRESHOLD_L);
  bool triggerR = (motionR > TRIGGER_THRESHOLD_R);

  // Update last motion time for timeout/clear logic
  if (triggerL || triggerR) {
    lastMotionTime = millis();
  }

  // Debug Print (only on significant motion changes)
  static int lastL = 0, lastR = 0;
  if ((abs(motionL - lastL) > 200 || abs(motionR - lastR) > 200)) {
    Serial.printf("📊 L:%d R:%d S:%d\n", motionL, motionR, currentState);
    lastL = motionL; lastR = motionR;
  }

  // WAIT_CLEAR runs outside cooldown so back-to-back people aren't missed
  if (currentState == 3) {
    bool zonesQuiet = (motionL < CLEAR_THRESHOLD_L && motionR < CLEAR_THRESHOLD_R);
    if (zonesQuiet) {
      if (clearStartTime == 0) clearStartTime = millis();
      if (millis() - clearStartTime >= CLEAR_HOLD_MS) {
        currentState = 0;
        clearStartTime = 0;
        Serial.println("✅ Zone Cleared, Ready");
      }
    } else {
      clearStartTime = 0;
    }
  }

  // Robust State Machine (cooldown only guards counting, not clearing)
  if (true) {
    if (currentState == 0) { // CLEAR
      if (triggerL && !triggerR) {
        currentState = 1; // ENTERED_L
        Serial.println("➡️ Trigger Left");
      } else if (triggerR && !triggerL) {
        currentState = 2; // ENTERED_R
        Serial.println("⬅️ Trigger Right");
      }
    }
    else if (currentState == 1) { // ENTERED_L
      if (triggerR && millis() - lastCountTime > COOLDOWN) {
        // Event: L -> R
        if (IS_RIGHT_TO_LEFT_ENTER) {
          if (passengerCount > 0) passengerCount--;
          Serial.printf("🔴 EXIT Detected! Total: %d\n", passengerCount);
          sendMQTT("exit");
        } else {
          if (passengerCount < MAX_PASSENGER_COUNT) passengerCount++;
          Serial.printf("🟢 ENTER Detected! Total: %d\n", passengerCount);
          sendMQTT("enter");
        }
        savePassengerCount();
        publishStatus();
        lastCountTime = millis();
        currentState = 3; // WAIT_CLEAR
      } else if (millis() - lastMotionTime > 2000) {
        currentState = 0;
        Serial.println("⏱️ State Reset Left (Timeout)");
      }
    }
    else if (currentState == 2) { // ENTERED_R
      if (triggerL && millis() - lastCountTime > COOLDOWN) {
        // Event: R -> L
        if (IS_RIGHT_TO_LEFT_ENTER) {
          if (passengerCount < MAX_PASSENGER_COUNT) passengerCount++;
          Serial.printf("🟢 ENTER Detected! Total: %d\n", passengerCount);
          sendMQTT("enter");
        } else {
          if (passengerCount > 0) passengerCount--;
          Serial.printf("🔴 EXIT Detected! Total: %d\n", passengerCount);
          sendMQTT("exit");
        }
        savePassengerCount();
        publishStatus();
        lastCountTime = millis();
        currentState = 3; // WAIT_CLEAR
      } else if (millis() - lastMotionTime > 2000) {
        currentState = 0;
        Serial.println("⏱️ State Reset Right (Timeout)");
      }
    }
  }

  esp_camera_fb_return(fb);
  
  static unsigned long lastStat = 0;
  if (millis() - lastStat > 15000) { publishStatus(); lastStat = millis(); }
}

