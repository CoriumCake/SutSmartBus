#include <WiFi.h>
#include <PsychicMqttClient.h>
#include <HTTPUpdate.h>
#include <TinyGPS++.h>
#include <ArduinoJson.h>
#include <WebServer.h>
#include <math.h>

#include <ESPmDNS.h>
#include "DHT.h"
#include "config.h"

// Toggle firmware diagnostics here.
// Set to false after the MQTT/app issue is fixed.
#ifndef PM_DEBUG_MODE
#define PM_DEBUG_MODE true
#endif

#ifndef PM_DEBUG_INTERVAL_MS
#define PM_DEBUG_INTERVAL_MS 5000
#endif

#ifndef PM_DATA_PUBLISH_INTERVAL_MS
#define PM_DATA_PUBLISH_INTERVAL_MS 1000
#endif

#ifndef MQTT_STATUS_PUBLISH_INTERVAL_MS
#define MQTT_STATUS_PUBLISH_INTERVAL_MS 15000
#endif

#ifndef DHT_READ_INTERVAL_MS
#define DHT_READ_INTERVAL_MS 2000
#endif

#ifndef WIFI_RETRY_INTERVAL_MS
#define WIFI_RETRY_INTERVAL_MS 3000
#endif

#ifndef MQTT_WIFI_RECOVERY_MS
#define MQTT_WIFI_RECOVERY_MS 30000
#endif

#ifndef PM_TEMP_CHANGE_THRESHOLD_C
#define PM_TEMP_CHANGE_THRESHOLD_C 0.1f
#endif

#ifndef PM_HUM_CHANGE_THRESHOLD_PERCENT
#define PM_HUM_CHANGE_THRESHOLD_PERCENT 0.5f
#endif

#ifndef PM_RSSI_CHANGE_THRESHOLD_DBM
#define PM_RSSI_CHANGE_THRESHOLD_DBM 3
#endif

#ifndef PM_GPS_CHANGE_THRESHOLD_DEGREES
#define PM_GPS_CHANGE_THRESHOLD_DEGREES 0.00005
#endif

#ifndef PM_GPS_SPEED_CHANGE_THRESHOLD_KMPH
#define PM_GPS_SPEED_CHANGE_THRESHOLD_KMPH 2.0f
#endif

#ifndef PM_HEAP_LOG_THRESHOLD_BYTES
#define PM_HEAP_LOG_THRESHOLD_BYTES 2048
#endif

// OTA Update State
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

// Hardware Objects
PsychicMqttClient mqttClient;
WebServer server(80);
DHT dht(DHTPIN, DHTTYPE);
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);
HardwareSerial pmsSerial(1);

// Global State
char bus_mac[18];
bool wifiConnected = false;
float tempC = 0, humid = 0;
uint16_t pm25 = 0, pm10 = 0;
unsigned long lastDataPublish = 0, lastDhtRead = 0, lastGpsPublish = 0;
unsigned long lastStatusPublish = 0;
unsigned long lastDebugStatus = 0, lastPmsDebug = 0, lastGpsDebug = 0, lastMqttSkipDebug = 0, lastWifiRetry = 0;
unsigned long lastMqttAttempt = 0, lastMqttStop = 0;
unsigned long mqttDisconnectedSince = 0;
bool mqttConfigured = false;
bool mqttConnectAttempted = false;
bool mqttNeedsStopBeforeReconnect = false;
char mqttUri[128];
char mqttStatusTopic[96];
char mqttStatusOnlinePayload[224];
char mqttStatusOfflinePayload[224];
uint8_t wifiNetworkIndex = 0;
bool hasLastPublishedData = false;
bool lastPublishedDataHadGps = false;
uint16_t lastPublishedPm25 = 0, lastPublishedPm10 = 0;
float lastPublishedTempC = 0, lastPublishedHumid = 0, lastPublishedDataSpeed = 0;
double lastPublishedDataLat = 0, lastPublishedDataLon = 0;
int lastPublishedRssi = 0;
bool hasLastPublishedGps = false;
double lastPublishedGpsLat = 0, lastPublishedGpsLon = 0;
float lastPublishedGpsSpeed = 0;
bool hasLastLoggedPms = false;
uint16_t lastLoggedPm25 = 0, lastLoggedPm10 = 0;
bool slowMqttDisconnectedLogged = false;
bool fastMqttDisconnectedLogged = false;
bool gpsInvalidLogged = false;
bool hasLastDebugStatus = false;
int lastDebugWifiStatus = WL_IDLE_STATUS;
bool lastDebugMqttConnected = false, lastDebugGpsValid = false;
int lastDebugRssi = 0;
uint32_t lastDebugSats = 0, lastDebugFreeHeap = 0;
uint16_t lastDebugPm25 = 0, lastDebugPm10 = 0;
float lastDebugTempC = 0, lastDebugHumid = 0;

// --- Function Prototypes ---
void handleWiFi();
bool isConfiguredWifiNetwork(const char* ssid);
const char* currentWifiSsid();
const char* currentWifiPassword();
void startWiFiAttempt(bool rotateNetwork);
void reconnectMQTT();
void setupMQTT();
void processGPS();
void processPMS();
void buildStatusPayload(bool isOnline, char* buffer, size_t bufferSize);
void publishStatus();
void publishData();
void publishGPS();
bool shouldPublishData(bool hasGps, double lat, double lon, float speed, int rssi);
void rememberPublishedData(bool hasGps, double lat, double lon, float speed, int rssi);
bool shouldPublishGPS(double lat, double lon, float speed);
void rememberPublishedGPS(double lat, double lon, float speed);
bool floatChanged(float current, float previous, float threshold);
bool doubleChanged(double current, double previous, double threshold);
bool intChanged(int current, int previous, int threshold);
bool uint32Changed(uint32_t current, uint32_t previous, uint32_t threshold);
void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup);
void performOTA();
void debugStatus();

void setup() {
  Serial.begin(115200);
  delay(1000);
  if (PM_DEBUG_MODE) {
    Serial.println("[DEBUG] PM debug mode enabled");
  }
  Serial.println("🚌 SUT SmartBus PM/GPS Module v2.0");

  // Initialize Hardware
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  pmsSerial.begin(9600, SERIAL_8N1, PMS_RX_PIN, PMS_TX_PIN);
  dht.begin();

  // Get MAC immediately for ID
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(bus_mac, 18, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  // WiFi & MQTT Setup
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.setAutoReconnect(true);
  WiFi.setSleep(false);
  startWiFiAttempt(false);
  setupMQTT();

  // Local Web Server for basic device presence checks
  server.on("/", [](){ server.send(200, "text/plain", "SUT SmartBus PM Module"); });
  server.begin();
  MDNS.begin(WEB_NAME);

  Serial.println("✅ System Ready (Offline-First)");
}

void loop() {
  handleWiFi();
  server.handleClient();
  
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) reconnectMQTT();
    if (otaPending) performOTA();
  }

  processGPS();
  processPMS();

  if (PM_DEBUG_MODE && millis() - lastDebugStatus >= PM_DEBUG_INTERVAL_MS) {
    lastDebugStatus = millis();
    debugStatus();
  }

  if (millis() - lastDhtRead >= DHT_READ_INTERVAL_MS) {
    lastDhtRead = millis();
    float nextTemp = dht.readTemperature();
    float nextHumid = dht.readHumidity();
    if (!isnan(nextTemp)) {
      tempC = nextTemp;
    }
    if (!isnan(nextHumid)) {
      humid = nextHumid;
    }
  }

  if (millis() - lastStatusPublish >= MQTT_STATUS_PUBLISH_INTERVAL_MS) {
    lastStatusPublish = millis();
    publishStatus();
  }

  // Near-real-time environment publish for app updates
  if (millis() - lastDataPublish >= PM_DATA_PUBLISH_INTERVAL_MS) {
    lastDataPublish = millis();
    publishData();
  }

  // Fast GPS Publish
  if (millis() - lastGpsPublish >= GPS_INTERVAL) {
    lastGpsPublish = millis();
    publishGPS();
  }
}

void handleWiFi() {
  wl_status_t status = WiFi.status();
  if (status == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      Serial.println("WiFi connected: " + WiFi.localIP().toString());
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

bool isConfiguredWifiNetwork(const char* ssid) {
  return ssid != nullptr &&
      strlen(ssid) > 0 &&
      strcmp(ssid, "fallback_ssid_1") != 0 &&
      strcmp(ssid, "fallback_ssid_2") != 0;
}

const char* currentWifiSsid() {
  if (wifiNetworkIndex == 1 && isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    return WIFI_FALLBACK_1_SSID;
  }
  return WIFI_SSID;
}

const char* currentWifiPassword() {
  if (wifiNetworkIndex == 1 && isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    return WIFI_FALLBACK_1_PASSWORD;
  }
  return WIFI_PASSWORD;
}

void startWiFiAttempt(bool rotateNetwork) {
  if (rotateNetwork && isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    wifiNetworkIndex = (wifiNetworkIndex + 1) % 2;
  } else if (!isConfiguredWifiNetwork(WIFI_FALLBACK_1_SSID)) {
    wifiNetworkIndex = 0;
  }

  lastWifiRetry = millis();
  mqttConnectAttempted = false;
  const char* ssid = currentWifiSsid();

  if (PM_DEBUG_MODE) {
    Serial.printf(
      "[DEBUG] WiFi %s ssid=%s index=%u status=%d\n",
      rotateNetwork ? "retry" : "begin",
      ssid,
      wifiNetworkIndex,
      WiFi.status()
    );
  }

  WiFi.disconnect(false, false);
  WiFi.begin(ssid, currentWifiPassword());
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

  Serial.printf("🔌 MQTT Connecting: %s\n", mqttUri);
  mqttClient.connect();
}

void setupMQTT() {
  if ((strlen(MQTT_URI) == 0 || strcmp(MQTT_URI, "your_mqtt_uri") == 0) &&
      (strlen(MQTT_SERVER) == 0 || strcmp(MQTT_SERVER, "your_mqtt_host") == 0)) {
    Serial.println("⚠️ MQTT Blocked (Placeholder detected in config.h)");
    return;
  }

  snprintf(mqttUri, sizeof(mqttUri), "mqtt://%s:%d", MQTT_SERVER, MQTT_PORT);
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

  if ((strncmp(mqttUri, "wss://", 6) == 0 || strncmp(mqttUri, "mqtts://", 8) == 0) &&
      strlen(MQTT_ROOT_CA) > 0) {
    mqttClient.setCACert(MQTT_ROOT_CA);
  }

  mqttClient.onMessage(mqttCallback);
  mqttClient.onConnect([](bool sessionPresent) {
    mqttConnectAttempted = false;
    mqttNeedsStopBeforeReconnect = false;
    slowMqttDisconnectedLogged = false;
    fastMqttDisconnectedLogged = false;
    hasLastPublishedData = false;
    hasLastPublishedGps = false;
    gpsInvalidLogged = false;
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
    publishStatus();
    if (PM_DEBUG_MODE) {
      Serial.printf("[DEBUG] MQTT client_id=%s session=%d subscribed=%s\n", bus_mac, sessionPresent, MQTT_TOPIC_OTA);
    }
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
  mqttClient.setClientId(bus_mac);
  snprintf(mqttStatusTopic, sizeof(mqttStatusTopic), "sut/bus/%s/status", bus_mac);
  buildStatusPayload(true, mqttStatusOnlinePayload, sizeof(mqttStatusOnlinePayload));
  buildStatusPayload(false, mqttStatusOfflinePayload, sizeof(mqttStatusOfflinePayload));
  mqttClient.setWill(mqttStatusTopic, 1, true, mqttStatusOfflinePayload);
  // Keep reconnection in one place. The sketch already retries manually, and
  // enabling the library auto-reconnect can re-start an already running client.
  mqttClient.setAutoReconnect(false);
  mqttClient.setKeepAlive(10);
  mqttConfigured = true;
  if (PM_DEBUG_MODE) {
    Serial.printf("[DEBUG] MQTT configured uri=%s topic=%s fast_topic=%s\n", mqttUri, MQTT_TOPIC, MQTT_TOPIC_FAST);
  }
}

void processGPS() {
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }
}

void processPMS() {
  // Robust PMS frame sync: scan for 0x42 0x4D, then validate length/checksum.
  while (pmsSerial.available() >= 32) {
    if (pmsSerial.peek() != 0x42) {
      pmsSerial.read();
      continue;
    }

    uint8_t frame[32];
    size_t bytesRead = pmsSerial.readBytes(frame, sizeof(frame));
    if (bytesRead != sizeof(frame)) {
      if (PM_DEBUG_MODE) {
        Serial.printf("[DEBUG] PMS short frame: bytes=%u\n", (unsigned)bytesRead);
      }
      return;
    }

    if (frame[0] != 0x42 || frame[1] != 0x4D) {
      if (PM_DEBUG_MODE && millis() - lastPmsDebug >= PM_DEBUG_INTERVAL_MS) {
        lastPmsDebug = millis();
        Serial.printf("[DEBUG] PMS lost sync: header=0x%02X 0x%02X\n", frame[0], frame[1]);
      }
      continue;
    }

    uint16_t frameLength = ((uint16_t)frame[2] << 8) | frame[3];
    if (frameLength != 28) {
      if (PM_DEBUG_MODE && millis() - lastPmsDebug >= PM_DEBUG_INTERVAL_MS) {
        lastPmsDebug = millis();
        Serial.printf("[DEBUG] PMS unexpected frame length=%u\n", frameLength);
      }
      continue;
    }

    uint16_t expectedChecksum = ((uint16_t)frame[30] << 8) | frame[31];
    uint16_t actualChecksum = 0;
    for (int i = 0; i < 30; i++) {
      actualChecksum += frame[i];
    }

    if (actualChecksum != expectedChecksum) {
      if (PM_DEBUG_MODE && millis() - lastPmsDebug >= PM_DEBUG_INTERVAL_MS) {
        lastPmsDebug = millis();
        Serial.printf(
          "[DEBUG] PMS checksum mismatch expected=%u actual=%u\n",
          expectedChecksum,
          actualChecksum
        );
      }
      continue;
    }

    pm25 = ((uint16_t)frame[6] << 8) | frame[7];
    pm10 = ((uint16_t)frame[8] << 8) | frame[9];
    if (PM_DEBUG_MODE &&
        (!hasLastLoggedPms || pm25 != lastLoggedPm25 || pm10 != lastLoggedPm10)) {
      Serial.printf("[DEBUG] PMS frame parsed pm2_5=%u pm10=%u\n", pm25, pm10);
      hasLastLoggedPms = true;
      lastLoggedPm25 = pm25;
      lastLoggedPm10 = pm10;
    }
    return;
  }

  if (PM_DEBUG_MODE && millis() - lastPmsDebug >= PM_DEBUG_INTERVAL_MS) {
    lastPmsDebug = millis();
    Serial.printf("[DEBUG] PMS waiting for full frame available=%d\n", pmsSerial.available());
  }
}

void buildStatusPayload(bool isOnline, char* buffer, size_t bufferSize) {
  snprintf(
    buffer,
    bufferSize,
    "{\"bus_mac\":\"%s\",\"bus_name\":\"%s\",\"component\":\"pm\",\"is_online\":%s,\"rssi\":%d,\"uptime\":%lu,\"pm2_5\":%u,\"pm10\":%u,\"temp\":%.2f,\"hum\":%.2f}",
    bus_mac,
    BUS_NAME,
    isOnline ? "true" : "false",
    isOnline && WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : -100,
    millis() / 1000,
    pm25,
    pm10,
    tempC,
    humid
  );
}

void publishStatus() {
  if (!mqttClient.connected()) return;
  buildStatusPayload(true, mqttStatusOnlinePayload, sizeof(mqttStatusOnlinePayload));
  mqttClient.publish(mqttStatusTopic, 1, true, mqttStatusOnlinePayload);
}

bool floatChanged(float current, float previous, float threshold) {
  return fabsf(current - previous) >= threshold;
}

bool doubleChanged(double current, double previous, double threshold) {
  return fabs(current - previous) >= threshold;
}

bool intChanged(int current, int previous, int threshold) {
  int delta = current - previous;
  if (delta < 0) delta = -delta;
  return delta >= threshold;
}

bool uint32Changed(uint32_t current, uint32_t previous, uint32_t threshold) {
  return current > previous
    ? current - previous >= threshold
    : previous - current >= threshold;
}

bool shouldPublishData(bool hasGps, double lat, double lon, float speed, int rssi) {
  if (!hasLastPublishedData) return true;
  if (pm25 != lastPublishedPm25 || pm10 != lastPublishedPm10) return true;
  if (floatChanged(tempC, lastPublishedTempC, PM_TEMP_CHANGE_THRESHOLD_C)) return true;
  if (floatChanged(humid, lastPublishedHumid, PM_HUM_CHANGE_THRESHOLD_PERCENT)) return true;
  if (intChanged(rssi, lastPublishedRssi, PM_RSSI_CHANGE_THRESHOLD_DBM)) return true;
  if (hasGps != lastPublishedDataHadGps) return true;
  return false;
}

void rememberPublishedData(bool hasGps, double lat, double lon, float speed, int rssi) {
  hasLastPublishedData = true;
  lastPublishedDataHadGps = hasGps;
  lastPublishedPm25 = pm25;
  lastPublishedPm10 = pm10;
  lastPublishedTempC = tempC;
  lastPublishedHumid = humid;
  lastPublishedRssi = rssi;
  if (hasGps) {
    lastPublishedDataLat = lat;
    lastPublishedDataLon = lon;
    lastPublishedDataSpeed = speed;
  }
}

bool shouldPublishGPS(double lat, double lon, float speed) {
  if (!hasLastPublishedGps) return true;
  return doubleChanged(lat, lastPublishedGpsLat, PM_GPS_CHANGE_THRESHOLD_DEGREES) ||
      doubleChanged(lon, lastPublishedGpsLon, PM_GPS_CHANGE_THRESHOLD_DEGREES) ||
      floatChanged(speed, lastPublishedGpsSpeed, PM_GPS_SPEED_CHANGE_THRESHOLD_KMPH);
}

void rememberPublishedGPS(double lat, double lon, float speed) {
  hasLastPublishedGps = true;
  lastPublishedGpsLat = lat;
  lastPublishedGpsLon = lon;
  lastPublishedGpsSpeed = speed;
}

void publishData() {
  if (!mqttClient.connected()) {
    if (PM_DEBUG_MODE && !slowMqttDisconnectedLogged) {
      lastMqttSkipDebug = millis();
      Serial.println("[DEBUG] Skip slow publish: MQTT is not connected");
      slowMqttDisconnectedLogged = true;
    }
    return;
  }
  slowMqttDisconnectedLogged = false;

  bool hasGps = gps.location.isValid();
  double lat = hasGps ? gps.location.lat() : 0;
  double lon = hasGps ? gps.location.lng() : 0;
  float speed = hasGps ? gps.speed.kmph() : 0;
  int rssi = WiFi.RSSI();
  if (!shouldPublishData(hasGps, lat, lon, speed, rssi)) {
    return;
  }

  StaticJsonDocument<256> doc;
  doc["bus_mac"] = bus_mac;
  doc["bus_name"] = BUS_NAME;
  if (hasGps) {
    doc["lat"] = lat;
    doc["lon"] = lon;
    doc["speed"] = speed;
  }
  doc["temp"] = tempC;
  doc["hum"] = humid;
  doc["pm2_5"] = pm25;
  doc["pm10"] = pm10;
  doc["rssi"] = rssi;
  
  char buffer[256];
  serializeJson(doc, buffer);
  if (PM_DEBUG_MODE) {
    Serial.printf("[DEBUG] Publish slow topic=%s payload=%s\n", MQTT_TOPIC, buffer);
  }
  int msgId = mqttClient.publish(MQTT_TOPIC, 1, false, buffer);
  if (msgId >= 0) {
    rememberPublishedData(hasGps, lat, lon, speed, rssi);
  }
}

void publishGPS() {
  if (!mqttClient.connected()) {
    if (PM_DEBUG_MODE && !fastMqttDisconnectedLogged) {
      lastMqttSkipDebug = millis();
      Serial.println("[DEBUG] Skip fast GPS publish: MQTT is not connected");
      fastMqttDisconnectedLogged = true;
    }
    return;
  }
  fastMqttDisconnectedLogged = false;

  if (!gps.location.isValid()) {
    if (PM_DEBUG_MODE && !gpsInvalidLogged) {
      lastGpsDebug = millis();
      Serial.printf("[DEBUG] Skip fast GPS publish: no valid GPS fix yet chars=%lu satellites=%lu\n",
        (unsigned long)gps.charsProcessed(),
        (unsigned long)(gps.satellites.isValid() ? gps.satellites.value() : 0)
      );
      gpsInvalidLogged = true;
    }
    return;
  }
  gpsInvalidLogged = false;

  double lat = gps.location.lat();
  double lon = gps.location.lng();
  float speed = gps.speed.kmph();
  if (!shouldPublishGPS(lat, lon, speed)) {
    return;
  }

  StaticJsonDocument<128> doc;
  doc["bus_mac"] = bus_mac;
  doc["bus_name"] = BUS_NAME;
  doc["lat"] = lat;
  doc["lon"] = lon;
  doc["speed"] = speed;
  
  char buffer[128];
  serializeJson(doc, buffer);
  if (PM_DEBUG_MODE) {
    Serial.printf("[DEBUG] Publish fast topic=%s payload=%s\n", MQTT_TOPIC_FAST, buffer);
  }
  int msgId = mqttClient.publish(MQTT_TOPIC_FAST, 1, false, buffer);
  if (msgId >= 0) {
    rememberPublishedGPS(lat, lon, speed);
  }
}

void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup) {
  String message = String(payload);
  
  StaticJsonDocument<256> otaDoc;
  if (deserializeJson(otaDoc, message) == DeserializationError::Ok) {
    if (otaDoc.containsKey("url")) {
      otaUrl = otaDoc["url"].as<String>();
      otaPending = true;
    }
  }
}

void performOTA() {
  otaPending = false;
  Serial.println("🔄 Starting OTA...");
  WiFiClient client;
  t_httpUpdate_return ret = httpUpdate.update(client, otaUrl);
  if (ret == HTTP_UPDATE_OK) ESP.restart();
}

void debugStatus() {
  int wifiStatus = WiFi.status();
  bool mqttConnected = mqttClient.connected();
  int rssi = wifiStatus == WL_CONNECTED ? WiFi.RSSI() : 0;
  bool gpsValid = gps.location.isValid();
  double lat = gpsValid ? gps.location.lat() : 0;
  double lon = gpsValid ? gps.location.lng() : 0;
  uint32_t sats = gps.satellites.isValid() ? gps.satellites.value() : 0;
  uint32_t freeHeap = ESP.getFreeHeap();

  bool changed = !hasLastDebugStatus ||
      wifiStatus != lastDebugWifiStatus ||
      mqttConnected != lastDebugMqttConnected ||
      gpsValid != lastDebugGpsValid ||
      sats != lastDebugSats ||
      pm25 != lastDebugPm25 ||
      pm10 != lastDebugPm10 ||
      intChanged(rssi, lastDebugRssi, PM_RSSI_CHANGE_THRESHOLD_DBM) ||
      floatChanged(tempC, lastDebugTempC, PM_TEMP_CHANGE_THRESHOLD_C) ||
      floatChanged(humid, lastDebugHumid, PM_HUM_CHANGE_THRESHOLD_PERCENT) ||
      uint32Changed(freeHeap, lastDebugFreeHeap, PM_HEAP_LOG_THRESHOLD_BYTES);

  if (!changed) return;

  Serial.printf(
    "[DEBUG] status wifi=%s mqtt=%s rssi=%d gpsValid=%s lat=%.6f lon=%.6f gpsChars=%lu sats=%lu pm2_5=%u pm10=%u temp=%.1f hum=%.1f freeHeap=%lu\n",
    wifiStatus == WL_CONNECTED ? "connected" : "disconnected",
    mqttConnected ? "connected" : "disconnected",
    rssi,
    gpsValid ? "yes" : "no",
    lat,
    lon,
    (unsigned long)gps.charsProcessed(),
    (unsigned long)sats,
    pm25,
    pm10,
    tempC,
    humid,
    (unsigned long)freeHeap
  );

  hasLastDebugStatus = true;
  lastDebugWifiStatus = wifiStatus;
  lastDebugMqttConnected = mqttConnected;
  lastDebugGpsValid = gpsValid;
  lastDebugRssi = rssi;
  lastDebugSats = sats;
  lastDebugPm25 = pm25;
  lastDebugPm10 = pm10;
  lastDebugTempC = tempC;
  lastDebugHumid = humid;
  lastDebugFreeHeap = freeHeap;
}

