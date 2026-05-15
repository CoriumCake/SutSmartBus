#include <WiFi.h>
#include <PsychicMqttClient.h>
#include <HTTPUpdate.h>
#include <TinyGPS++.h>
#include <ArduinoJson.h>
#include <WebServer.h>

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

#ifndef DHT_READ_INTERVAL_MS
#define DHT_READ_INTERVAL_MS 2000
#endif

#ifndef WIFI_RETRY_INTERVAL_MS
#define WIFI_RETRY_INTERVAL_MS 10000
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
unsigned long lastDebugStatus = 0, lastPmsDebug = 0, lastGpsDebug = 0, lastMqttSkipDebug = 0, lastWifiRetry = 0;
bool mqttConfigured = false;
bool mqttConnectAttempted = false;
char mqttUri[128];
uint8_t wifiNetworkIndex = 0;

// --- Function Prototypes ---
void handleWiFi();
const char* currentWifiSsid();
const char* currentWifiPassword();
void startWiFiAttempt(bool rotateNetwork);
void reconnectMQTT();
void setupMQTT();
void processGPS();
void processPMS();
void publishData();
void publishGPS();
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
      Serial.println("✅ WiFi Connected: " + WiFi.localIP().toString());
    }
    return;
  }

  if (wifiConnected) {
    wifiConnected = false;
    mqttConnectAttempted = false;
    Serial.printf("WiFi disconnected status=%d\n", status);
  }

  if (millis() - lastWifiRetry >= WIFI_RETRY_INTERVAL_MS) {
    startWiFiAttempt(true);
  }
}

const char* currentWifiSsid() {
  if (wifiNetworkIndex == 1 && strlen(WIFI_FALLBACK_1_SSID) > 0) {
    return WIFI_FALLBACK_1_SSID;
  }
  return WIFI_SSID;
}

const char* currentWifiPassword() {
  if (wifiNetworkIndex == 1 && strlen(WIFI_FALLBACK_1_SSID) > 0) {
    return WIFI_FALLBACK_1_PASSWORD;
  }
  return WIFI_PASSWORD;
}

void startWiFiAttempt(bool rotateNetwork) {
  if (rotateNetwork && strlen(WIFI_FALLBACK_1_SSID) > 0) {
    wifiNetworkIndex = (wifiNetworkIndex + 1) % 2;
  } else if (strlen(WIFI_FALLBACK_1_SSID) == 0) {
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
  static unsigned long lastAttempt = 0;
  if (millis() - lastAttempt < 10000) return;
  lastAttempt = millis();
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
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
    if (PM_DEBUG_MODE) {
      Serial.printf("[DEBUG] MQTT client_id=%s session=%d subscribed=%s\n", bus_mac, sessionPresent, MQTT_TOPIC_OTA);
    }
  });
  mqttClient.onDisconnect([](bool sessionPresent) {
    mqttConnectAttempted = false;
    Serial.println("MQTT disconnected");
  });
  mqttClient.onError([](esp_mqtt_error_codes_t error) {
    mqttConnectAttempted = false;
    Serial.printf("MQTT error type=%d tls=%d stack=%d sock=%d\n",
      error.error_type,
      error.esp_tls_last_esp_err,
      error.esp_tls_stack_err,
      error.esp_transport_sock_errno
    );
  });
  mqttClient.setServer(mqttUri);
  mqttClient.setClientId(bus_mac);
  // Keep reconnection in one place. The sketch already retries manually, and
  // enabling the library auto-reconnect can re-start an already running client.
  mqttClient.setAutoReconnect(false);
  mqttClient.setKeepAlive(30);
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
    if (PM_DEBUG_MODE) {
      Serial.printf("[DEBUG] PMS frame parsed pm2_5=%u pm10=%u\n", pm25, pm10);
    }
    return;
  }

  if (PM_DEBUG_MODE && millis() - lastPmsDebug >= PM_DEBUG_INTERVAL_MS) {
    lastPmsDebug = millis();
    Serial.printf("[DEBUG] PMS waiting for full frame available=%d\n", pmsSerial.available());
  }
}

void publishData() {
  if (!mqttClient.connected()) {
    if (PM_DEBUG_MODE && millis() - lastMqttSkipDebug >= PM_DEBUG_INTERVAL_MS) {
      lastMqttSkipDebug = millis();
      Serial.println("[DEBUG] Skip slow publish: MQTT is not connected");
    }
    return;
  }
  StaticJsonDocument<256> doc;
  doc["bus_mac"] = bus_mac;
  doc["bus_name"] = BUS_NAME;
  if (gps.location.isValid()) {
    doc["lat"] = gps.location.lat();
    doc["lon"] = gps.location.lng();
    doc["speed"] = gps.speed.kmph();
  }
  doc["temp"] = tempC;
  doc["hum"] = humid;
  doc["pm2_5"] = pm25;
  doc["pm10"] = pm10;
  doc["rssi"] = WiFi.RSSI();
  
  char buffer[256];
  serializeJson(doc, buffer);
  if (PM_DEBUG_MODE) {
    Serial.printf("[DEBUG] Publish slow topic=%s payload=%s\n", MQTT_TOPIC, buffer);
  }
  mqttClient.publish(MQTT_TOPIC, 1, false, buffer);
}

void publishGPS() {
  if (!mqttClient.connected()) {
    if (PM_DEBUG_MODE && millis() - lastMqttSkipDebug >= PM_DEBUG_INTERVAL_MS) {
      lastMqttSkipDebug = millis();
      Serial.println("[DEBUG] Skip fast GPS publish: MQTT is not connected");
    }
    return;
  }
  if (!gps.location.isValid()) {
    if (PM_DEBUG_MODE && millis() - lastGpsDebug >= PM_DEBUG_INTERVAL_MS) {
      lastGpsDebug = millis();
      Serial.printf("[DEBUG] Skip fast GPS publish: no valid GPS fix yet chars=%lu satellites=%lu\n",
        (unsigned long)gps.charsProcessed(),
        (unsigned long)(gps.satellites.isValid() ? gps.satellites.value() : 0)
      );
    }
    return;
  }
  StaticJsonDocument<128> doc;
  doc["bus_mac"] = bus_mac;
  doc["bus_name"] = BUS_NAME;
  doc["lat"] = gps.location.lat();
  doc["lon"] = gps.location.lng();
  doc["speed"] = gps.speed.kmph();
  
  char buffer[128];
  serializeJson(doc, buffer);
  if (PM_DEBUG_MODE) {
    Serial.printf("[DEBUG] Publish fast topic=%s payload=%s\n", MQTT_TOPIC_FAST, buffer);
  }
  mqttClient.publish(MQTT_TOPIC_FAST, 1, false, buffer);
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
  Serial.printf(
    "[DEBUG] status wifi=%s mqtt=%s rssi=%d gpsValid=%s gpsChars=%lu sats=%lu pm2_5=%u pm10=%u temp=%.1f hum=%.1f freeHeap=%lu\n",
    WiFi.status() == WL_CONNECTED ? "connected" : "disconnected",
    mqttClient.connected() ? "connected" : "disconnected",
    WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0,
    gps.location.isValid() ? "yes" : "no",
    (unsigned long)gps.charsProcessed(),
    (unsigned long)(gps.satellites.isValid() ? gps.satellites.value() : 0),
    pm25,
    pm10,
    tempC,
    humid,
    (unsigned long)ESP.getFreeHeap()
  );
}
