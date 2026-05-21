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
int TRIGGER_THRESHOLD_L = 520;  // Keep both sides similarly sensitive so exits are not missed
int TRIGGER_THRESHOLD_R = 520;
int NOISE_THRESHOLD_BOTH = 1800; // Re-zero only when both zones are heavily disturbed
int NOISE_THRESHOLD_TOTAL = 6200; // Whole-frame disturbance threshold
int CLEAR_THRESHOLD_L = 180;    // Quiet level used to remove post-count side blocking
int CLEAR_THRESHOLD_R = 180;
int START_DOMINANCE_MARGIN = 120; // Motion lead needed to arm from one side when both fire
int CROSS_DOMINANCE_MARGIN = 120; // Motion lead needed to finish crossing when both fire
int EXIT_START_BIAS = 360;      // Prefer exits when both zones start nearly together
int EXIT_END_THRESHOLD = 420;   // Exit finish can be softer than a fresh entry-side start
int EXIT_END_BIAS = 360;        // Let exits finish even while the start-side tail is still visible
int EXIT_REARM_OPPOSITE_THRESHOLD = 420; // Same-side exit restart may begin before full quiet
unsigned long CLEAR_HOLD_MS = 250; // Quiet period before same-side blocking is removed
int ZONE_L = 60;                // Left line boundary (0-160)
int ZONE_R = 100;               // Right line boundary (0-160)
unsigned long COOLDOWN = 450;   // ms between counts
unsigned long MIN_CROSSING_MS = 120; // Ignore one-frame flips from leftover far-side motion
unsigned long TRACK_TIMEOUT_MS = 3200; // Drop a partial crossing if it never reaches the far side
unsigned long TRACK_RECOVERY_MS = 2200; // Late far-side pulse can still finish a timed-out track
unsigned long EXIT_SAME_SIDE_REARM_MS = 300; // Allow a real exit soon after an enter ended on R
unsigned long SAME_SIDE_REARM_MS = 900; // Allow immediate opposite-flow starts after a short hold
const int MAX_PASSENGER_COUNT = 40;

// Globals
int passengerCount = 0;
int currentState = 0;           // 0=Ready, 1=tracking from left, 2=tracking from right
int blockedStartSide = 0;       // Last ending side; avoids double-counting the same person
unsigned long lastCountTime = 0;
unsigned long lastMotionTime = 0;
unsigned long trackStartTime = 0;
unsigned long clearStartTime = 0;
int expiredTrackSide = 0;
unsigned long expiredTrackAt = 0;
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
bool lastPassengerEventIsEnter = true;
bool hasPassengerEvent = false;
unsigned long lastPassengerEventAt = 0;
unsigned long passengerEventSeq = 0;

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

int dominantMotionSide(int motionL, int motionR, bool triggerL, bool triggerR) {
  if (triggerL && !triggerR) return 1;
  if (triggerR && !triggerL) return 2;

  if (triggerL && triggerR) {
    if (motionL >= motionR + START_DOMINANCE_MARGIN) return 1;
    if (motionR >= motionL + START_DOMINANCE_MARGIN) return 2;
  }

  return 0;
}

int oppositeSide(int side) {
  if (side == 1) return 2;
  if (side == 2) return 1;
  return 0;
}

int motionForSide(int side, int motionL, int motionR) {
  if (side == 1) return motionL;
  if (side == 2) return motionR;
  return 0;
}

int exitStartSide() {
  return IS_RIGHT_TO_LEFT_ENTER ? 1 : 2;
}

int entryStartSide() {
  return IS_RIGHT_TO_LEFT_ENTER ? 2 : 1;
}

int trackingStartSide(int motionL, int motionR, bool triggerL, bool triggerR) {
  if (triggerL && !triggerR) return 1;
  if (triggerR && !triggerL) return 2;
  if (!triggerL || !triggerR) return 0;

  int exitSide = exitStartSide();
  int entrySide = entryStartSide();
  int exitMotion = motionForSide(exitSide, motionL, motionR);
  int entryMotion = motionForSide(entrySide, motionL, motionR);

  if (exitMotion + EXIT_START_BIAS >= entryMotion) return exitSide;
  if (entryMotion >= exitMotion + START_DOMINANCE_MARGIN) return entrySide;
  return 0;
}

bool crossedToSide(int side, int motionL, int motionR, bool triggerL, bool triggerR) {
  if (side == 1) {
    return triggerL && (!triggerR || motionL >= motionR + CROSS_DOMINANCE_MARGIN);
  }
  if (side == 2) {
    return triggerR && (!triggerL || motionR >= motionL + CROSS_DOMINANCE_MARGIN);
  }
  return false;
}

bool oppositeSideQuiet(int side, int motionL, int motionR) {
  if (side == 1) return motionR < CLEAR_THRESHOLD_R;
  if (side == 2) return motionL < CLEAR_THRESHOLD_L;
  return true;
}

bool canStartFromSide(int side, int motionL, int motionR, unsigned long now) {
  if (side == 0) return false;
  if (blockedStartSide != side) return true;

  if (side == exitStartSide()) {
    return (now - lastCountTime >= EXIT_SAME_SIDE_REARM_MS) &&
           motionForSide(oppositeSide(side), motionL, motionR) < EXIT_REARM_OPPOSITE_THRESHOLD;
  }

  return (now - lastCountTime >= SAME_SIDE_REARM_MS) &&
         oppositeSideQuiet(side, motionL, motionR);
}

void clearExpiredTrack() {
  expiredTrackSide = 0;
  expiredTrackAt = 0;
}

void rememberTimedOutTrack(int side, unsigned long now) {
  expiredTrackSide = side;
  expiredTrackAt = now;
}

bool hasActiveExpiredTrack(unsigned long now) {
  if (expiredTrackSide == 0) return false;
  if (now - expiredTrackAt <= TRACK_RECOVERY_MS) return true;

  clearExpiredTrack();
  return false;
}

bool crossingCompletedFromSide(int startSide, int motionL, int motionR, bool triggerL, bool triggerR) {
  int finishSide = oppositeSide(startSide);

  if (startSide == exitStartSide()) {
    int finishMotion = motionForSide(finishSide, motionL, motionR);
    int startMotion = motionForSide(startSide, motionL, motionR);
    return finishMotion > EXIT_END_THRESHOLD &&
           finishMotion + EXIT_END_BIAS >= startMotion;
  }

  return crossedToSide(finishSide, motionL, motionR, triggerL, triggerR);
}

bool canRecoverTimedOutTrack(int motionL, int motionR, bool triggerL, bool triggerR, unsigned long now) {
  return hasActiveExpiredTrack(now) &&
         crossingCompletedFromSide(expiredTrackSide, motionL, motionR, triggerL, triggerR) &&
         now - lastCountTime > COOLDOWN;
}

void recordPassengerCrossing(bool leftToRight) {
  bool isEnter = leftToRight ? !IS_RIGHT_TO_LEFT_ENTER : IS_RIGHT_TO_LEFT_ENTER;
  const char* direction = isEnter ? "enter" : "exit";

  if (isEnter) {
    if (passengerCount < MAX_PASSENGER_COUNT) passengerCount++;
  } else {
    if (passengerCount > 0) passengerCount--;
  }

  Serial.printf("%s detected. Total: %d\n", isEnter ? "ENTER" : "EXIT", passengerCount);
  lastPassengerEventIsEnter = isEnter;
  hasPassengerEvent = true;
  lastPassengerEventAt = millis();
  passengerEventSeq++;
  sendMQTT(direction);
  savePassengerCount();
  publishStatus();
  lastCountTime = millis();
  blockedStartSide = leftToRight ? 2 : 1;
  trackStartTime = 0;
  clearStartTime = 0;
  clearExpiredTrack();
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

bool isJsonWhitespace(char c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

int findJsonValueStart(const String& message, const char* fieldName) {
  String marker = String("\"") + fieldName + "\"";
  int fieldStart = message.indexOf(marker);
  if (fieldStart < 0) return -1;

  int colon = message.indexOf(':', fieldStart + marker.length());
  if (colon < 0) return -1;

  int valueStart = colon + 1;
  while (valueStart < message.length() && isJsonWhitespace(message[valueStart])) {
    valueStart++;
  }
  return valueStart;
}

String extractJsonStringField(const String& message, const char* fieldName) {
  int valueStart = findJsonValueStart(message, fieldName);
  if (valueStart < 0 || valueStart >= message.length() || message[valueStart] != '"') return "";
  valueStart++;
  int valueEnd = message.indexOf("\"", valueStart);
  if (valueEnd <= valueStart) return "";
  return message.substring(valueStart, valueEnd);
}

unsigned long extractJsonUnsignedField(const String& message, const char* fieldName) {
  int valueStart = findJsonValueStart(message, fieldName);
  if (valueStart < 0) return 0;
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
  blockedStartSide = 0;
  trackStartTime = 0;
  clearStartTime = 0;
  clearExpiredTrack();
  hasPassengerEvent = false;
  publishStatus();
  Serial.printf("🔄 Passenger count reset (%s)\n", reason);
}

void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup) {
  String message = String(payload);
  String topicString = String(topic);
  if (topicString == mqttRingTopic || topicString == mqttBusIdCommandTopic) {
    String command = extractJsonStringField(message, "command");
    bool isRingCommand = command == "ring";
    bool isResetCountCommand = command == "reset_count";
    const char* commandName = command.c_str();
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

void handleStatus() {
  char statusJson[160];
  unsigned long eventAge = hasPassengerEvent ? millis() - lastPassengerEventAt : 0;
  snprintf(
    statusJson,
    sizeof(statusJson),
    "{\"count\":%d,\"event\":\"%s\",\"event_age_ms\":%lu,\"event_seq\":%lu}",
    passengerCount,
    hasPassengerEvent ? (lastPassengerEventIsEnter ? "enter" : "exit") : "",
    eventAge,
    passengerEventSeq
  );
  httpServer.sendHeader("Cache-Control", "no-cache, no-store");
  httpServer.sendHeader("Access-Control-Allow-Origin", "*");
  httpServer.send(200, "application/json", statusJson);
}

void handleRoot() {
  httpServer.send(200, "text/html",
    "<!DOCTYPE html><html><head>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>Bus Cam</title>"
    "<style>"
    "body{background:#111;display:flex;flex-direction:column;align-items:center;"
    "justify-content:center;height:100vh;margin:0;color:#fff;font-family:sans-serif}"
    ".stage{position:relative;width:100%;max-width:480px}"
    "img{image-rendering:pixelated;width:100%;border:1px solid #333;display:block}"
    ".badge{position:absolute;top:12px;left:50%;transform:translateX(-50%) scale(.96);"
    "display:flex;align-items:center;gap:8px;padding:10px 14px;border-radius:999px;"
    "font-weight:800;letter-spacing:.08em;color:#fff;opacity:0;transition:opacity .16s,transform .16s;"
    "box-shadow:0 8px 24px rgba(0,0,0,.35);pointer-events:none}"
    ".badge.show{opacity:1;transform:translateX(-50%) scale(1)}"
    ".badge.enter{background:#16a34a}.badge.exit{background:#dc2626}"
    ".dot{display:grid;place-items:center;width:24px;height:24px;border-radius:50%;"
    "background:rgba(255,255,255,.22);font-size:20px;line-height:1}"
    "p{margin:8px 0;font-size:13px;color:#888}"
    "</style></head><body>"
    "<div class='stage'>"
    "<img id='cam' src='/capture'>"
    "<div id='badge' class='badge'><span id='dot' class='dot'>+</span><span id='label'>ENTER</span></div>"
    "</div>"
    "<p id='info'>Connecting...</p>"
    "<script>"
    "const img=document.getElementById('cam');"
    "const info=document.getElementById('info');"
    "const badge=document.getElementById('badge');"
    "const dot=document.getElementById('dot');"
    "const label=document.getElementById('label');"
    "let last=Date.now(),frames=0,shownFps=0;"
    "let lastSeq=0,badgeTimer=null;"
    "function showEvent(type){"
    "  const enter=type==='enter';"
    "  badge.className='badge show '+(enter?'enter':'exit');"
    "  dot.innerHTML=enter?'&#128994;':'&#128308;';"
    "  label.innerHTML=enter?'&#128994; ENTER':'&#128308; EXIT';"
    "  clearTimeout(badgeTimer);"
    "  badgeTimer=setTimeout(()=>badge.classList.remove('show'),1800);"
    "}"
    "async function poll(){"
    "  try{"
    "    const r=await fetch('/status?'+Date.now(),{cache:'no-store'});"
    "    const s=await r.json();"
    "    info.textContent='Count: '+s.count+' | '+shownFps+' fps';"
    "    if(s.event_seq&&s.event_seq!==lastSeq){lastSeq=s.event_seq;if(s.event_age_ms<2500)showEvent(s.event);}"
    "  }catch(e){}"
    "  setTimeout(poll,500);"
    "}"
    "function next(){"
    "  const t=Date.now();"
    "  img.src='/capture?'+t;"
    "  img.onload=()=>{"
    "    frames++;"
    "    if(t-last>=1000){shownFps=frames;frames=0;last=t;}"
    "    next();"
    "  };"
    "  img.onerror=()=>setTimeout(next,1000);"
    "}"
    "next();"
    "poll();"
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
  httpServer.on("/status", handleStatus);
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
    blockedStartSide = 0;
    trackStartTime = 0;
    clearStartTime = 0;
    clearExpiredTrack();
    Serial.println("🌫️ Massive Noise - Re-zeroing...");
    esp_camera_fb_return(fb);
    return;
  }

  bool triggerL = (motionL > TRIGGER_THRESHOLD_L);
  bool triggerR = (motionR > TRIGGER_THRESHOLD_R);
  unsigned long now = millis();
  int startSide = trackingStartSide(motionL, motionR, triggerL, triggerR);

  // Update last motion time for timeout/clear logic
  if (triggerL || triggerR) {
    lastMotionTime = now;
  }

  // Debug Print (only on significant motion changes)
  static int lastL = 0, lastR = 0;
  if ((abs(motionL - lastL) > 200 || abs(motionR - lastR) > 200)) {
    Serial.printf("Motion L:%d R:%d S:%d B:%d D:%d\n",
                  motionL,
                  motionR,
                  currentState,
                  blockedStartSide,
                  startSide);
    lastL = motionL; lastR = motionR;
  }

  // Clear only removes post-count blocking. Tracking itself times out so a
  // person passing through the center dead zone does not lose their sequence.
  bool zonesQuiet = (motionL < CLEAR_THRESHOLD_L && motionR < CLEAR_THRESHOLD_R);
  if (currentState == 0 && (blockedStartSide != 0 || expiredTrackSide != 0) && zonesQuiet) {
    if (clearStartTime == 0) clearStartTime = now;
    if (now - clearStartTime >= CLEAR_HOLD_MS) {
      blockedStartSide = 0;
      clearExpiredTrack();
      clearStartTime = 0;
      Serial.println("Zones quiet, detector fully re-armed");
    }
  } else if (!zonesQuiet) {
    clearStartTime = 0;
  }

  // Re-armable state machine. It counts on a left-dominant -> right-dominant
  // or right-dominant -> left-dominant crossing, so people can follow each
  // other without waiting for the whole doorway to become empty.
  if (currentState == 0) {
    int recoveredStartSide = expiredTrackSide;
    if (canRecoverTimedOutTrack(motionL, motionR, triggerL, triggerR, now)) {
      Serial.printf("Track recovered after timeout: %s\n", recoveredStartSide == 1 ? "left" : "right");
      recordPassengerCrossing(recoveredStartSide == 1);
    } else if (hasActiveExpiredTrack(now)) {
      // Wait for the late far-side pulse to complete or expire instead of
      // turning it into a fresh opposite-direction track.
    } else if (canStartFromSide(startSide, motionL, motionR, now)) {
      currentState = startSide;
      blockedStartSide = 0;
      clearExpiredTrack();
      clearStartTime = 0;
      lastMotionTime = now;
      trackStartTime = now;
      Serial.printf("Track start: %s\n", currentState == 1 ? "left" : "right");
    }
  } else if (currentState == 1) {
    if (crossingCompletedFromSide(1, motionL, motionR, triggerL, triggerR) &&
        now - trackStartTime >= MIN_CROSSING_MS &&
        now - lastCountTime > COOLDOWN) {
      recordPassengerCrossing(true);
      currentState = 0;
    } else if (now - lastMotionTime > TRACK_TIMEOUT_MS) {
      rememberTimedOutTrack(1, now);
      currentState = 0;
      trackStartTime = 0;
      Serial.println("Track reset: left timeout");
    }
  } else if (currentState == 2) {
    if (crossingCompletedFromSide(2, motionL, motionR, triggerL, triggerR) &&
        now - trackStartTime >= MIN_CROSSING_MS &&
        now - lastCountTime > COOLDOWN) {
      recordPassengerCrossing(false);
      currentState = 0;
    } else if (now - lastMotionTime > TRACK_TIMEOUT_MS) {
      rememberTimedOutTrack(2, now);
      currentState = 0;
      trackStartTime = 0;
      Serial.println("Track reset: right timeout");
    }
  }

  esp_camera_fb_return(fb);
  
  static unsigned long lastStat = 0;
  if (millis() - lastStat > 15000) { publishStatus(); lastStat = millis(); }
}

