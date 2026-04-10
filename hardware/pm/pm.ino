#include <WiFi.h>
#include <PubSubClient.h>
#include <HTTPUpdate.h>
#include <TinyGPS++.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <SD.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Wire.h>
#include <RTClib.h>
#include "DHT.h"
#include "config.h"

// OTA Update State
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

// Hardware Objects
WiFiClient espClient;
PubSubClient mqttClient(espClient);
WebServer server(80);
RTC_DS3231 rtc;
DHT dht(DHTPIN, DHTTYPE);
TinyGPSPlus gps;
HardwareSerial gpsSerial(2);
HardwareSerial pmsSerial(1);

// Global State
char bus_mac[18];
bool wifiConnected = false;
float tempC = 0, humid = 0;
uint16_t pm25 = 0, pm10 = 0;
unsigned long last5s = 0, last30s = 0, lastGpsPublish = 0;
const char* logFilename = "/gps_log.csv";

// --- Function Prototypes ---
void handleWiFi();
void reconnectMQTT();
void processGPS();
void processPMS();
void publishData();
void publishGPS();
void saveToSD();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void performOTA();

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("🚌 SUT SmartBus PM/GPS Module v2.0");

  // Initialize Hardware
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  pmsSerial.begin(9600, SERIAL_8N1, PMS_RX_PIN, PMS_TX_PIN);
  dht.begin();
  Wire.begin(I2C_SDA, I2C_SCL);
  rtc.begin();

  // Get MAC immediately for ID
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(bus_mac, 18, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  // WiFi & MQTT Setup
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setBufferSize(512);

  // SD Card setup
  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("❌ SD Card Fail");
  } else {
    if (!SD.exists(logFilename)) {
      File f = SD.open(logFilename, FILE_WRITE);
      f.println("Timestamp,Lat,Lon,PM25,PM10,Temp,Hum");
      f.close();
    }
    Serial.println("💾 SD Card Ready");
  }

  // Local Web Server for log access
  server.on("/", [](){ server.send(200, "text/plain", "SUT SmartBus PM Module"); });
  server.on("/download", [](){
    File file = SD.open(logFilename);
    if (file) { server.streamFile(file, "text/csv"); file.close(); }
    else server.send(404, "text/plain", "No Log");
  });
  server.begin();
  MDNS.begin(WEB_NAME);

  Serial.println("✅ System Ready (Offline-First)");
}

void loop() {
  handleWiFi();
  server.handleClient();
  
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) reconnectMQTT();
    mqttClient.loop();
    if (otaPending) performOTA();
  }

  processGPS();
  processPMS();

  // 5 Second Task: Environment & Status
  if (millis() - last5s >= INTERVAL_5S) {
    last5s = millis();
    tempC = dht.readTemperature();
    humid = dht.readHumidity();
    publishData();
  }

  // Fast GPS Publish
  if (millis() - lastGpsPublish >= GPS_INTERVAL) {
    lastGpsPublish = millis();
    publishGPS();
  }

  // 30 Second Task: SD Backup
  if (millis() - last30s >= INTERVAL_30S) {
    last30s = millis();
    saveToSD();
  }
}

void handleWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      Serial.println("✅ WiFi Connected: " + WiFi.localIP().toString());
    }
  } else {
    wifiConnected = false;
  }
}

void reconnectMQTT() {
  if (strcmp(MQTT_SERVER, "183.89.203.247") == 0 || strlen(MQTT_SERVER) < 7) return; 
  static unsigned long lastAttempt = 0;
  if (millis() - lastAttempt < 5000) return;
  lastAttempt = millis();

  Serial.printf("🔌 MQTT Connecting: %s\n", MQTT_SERVER);
  if (mqttClient.connect(bus_mac)) {
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(MQTT_TOPIC_OTA);
  }
}

void processGPS() {
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }
}

void processPMS() {
  // Simple PMS reader - looking for frame start 0x42 0x4D
  if (pmsSerial.available() >= 32) {
    if (pmsSerial.read() == 0x42 && pmsSerial.read() == 0x4D) {
      uint8_t buffer[30];
      pmsSerial.readBytes(buffer, 30);
      pm25 = (buffer[4] << 8) | buffer[5];
      pm10 = (buffer[6] << 8) | buffer[7];
    }
  }
}

void publishData() {
  if (!mqttClient.connected()) return;
  StaticJsonDocument<256> doc;
  doc["bus_mac"] = bus_mac;
  doc["temp"] = tempC;
  doc["hum"] = humid;
  doc["pm2_5"] = pm25;
  doc["pm10"] = pm10;
  doc["rssi"] = WiFi.RSSI();
  
  char buffer[256];
  serializeJson(doc, buffer);
  mqttClient.publish(MQTT_TOPIC, buffer);
}

void publishGPS() {
  if (!mqttClient.connected() || !gps.location.isValid()) return;
  StaticJsonDocument<128> doc;
  doc["bus_mac"] = bus_mac;
  doc["lat"] = gps.location.lat();
  doc["lon"] = gps.location.lng();
  doc["speed"] = gps.speed.kmph();
  
  char buffer[128];
  serializeJson(doc, buffer);
  mqttClient.publish(MQTT_TOPIC_FAST, buffer);
}

void saveToSD() {
  if (!SD.begin(SD_CS_PIN)) return;
  File file = SD.open(logFilename, FILE_APPEND);
  if (file) {
    DateTime now = rtc.now();
    file.printf("%04d-%02d-%02d %02d:%02d:%02d,", now.year(), now.month(), now.day(), now.hour(), now.minute(), now.second());
    file.printf("%.6f,%.6f,%d,%d,%.1f,%.1f\n", gps.location.lat(), gps.location.lng(), pm25, pm10, tempC, humid);
    file.close();
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  char message[length + 1];
  memcpy(message, payload, length);
  message[length] = '\0';
  
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
  t_httpUpdate_return ret = httpUpdate.update(espClient, otaUrl);
  if (ret == HTTP_UPDATE_OK) ESP.restart();
}
