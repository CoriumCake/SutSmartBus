#include <WiFi.h>
#include <PubSubClient.h>
#include <HTTPUpdate.h>  // For HTTP-based OTA updates
#include <TinyGPS++.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <SD.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Wire.h>
#include <RTClib.h>
#include "DHT.h"
#include "config.h"  // Include configuration file

// OTA update state
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

// ================= CONFIGURATION =================
// ... (rest of configuration stays the same) ...

// ================= OBJECTS =================
WiFiClient espClient;
PubSubClient client(espClient);
StaticJsonDocument<512> doc;
WebServer server(80);
RTC_DS3231 rtc;
 
char bus_mac[18];
 
// ================= GPS =================
// ... (GPS setup stays the same) ...

// ================= PMS =================
// ... (PMS setup stays the same) ...

// ================= DHT DATA =================
float tempC = 0;
float humid = 0;
 
// ================= TIMER CONFIG =================
unsigned long last5s = 0;
unsigned long last30s = 0;
unsigned long lastGpsPublish = 0;
 
// ================= FUNCTION DECLARE =================
void tryConnectWiFi();
void handleWiFiConnection();
void maintainMqtt();
void processGPS();
void processPMS();
void processDHT();
bool readPMSFrame();
void publishData();
void publishGPS();
void saveToSD();
void handleRoot();
void handleDownload();
void handleDelete();
void mqttCallback(char* topic, byte* payload, unsigned int length);
void performOTA();
 
// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1000);
 
  // Initial WiFi Attempt (Try Primary first)
  Serial.printf("📡 Trying default WiFi: %s\n", wifiNetworks[0].ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(wifiNetworks[0].ssid, wifiNetworks[0].password);
  
  unsigned long startAttempt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < 4000) {
    delay(100);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("\n✅ Default WiFi Connected: " + WiFi.localIP().toString());
  } else {
    Serial.println("\n⚠️ Default WiFi failed - starting offline mode");
    lastWifiAttempt = millis();
  }

  MDNS.begin(web_name);
  WiFi.macAddress().toCharArray(bus_mac, sizeof(bus_mac));

  // --- MQTT Setup ---
  client.setServer(MQTT_SERVER, MQTT_PORT); 
  client.setCallback(mqttCallback); 
  client.setBufferSize(512);
 
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  pmsSerial.begin(9600, SERIAL_8N1, PMS_RX_PIN, PMS_TX_PIN);
  dht.begin();
  Wire.begin(21, 22);
  rtc.begin();
 
  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("SD Card Mount Failed");
  } else {
    if (!SD.exists(filename)) {
      File f = SD.open(filename, FILE_WRITE);
      f.println("Date,Time,Lat,Lon,PM2.5,PM10,Temp,Hum,Source");
      f.close();
    }
  }
 
  server.on("/", handleRoot);
  server.on("/download", handleDownload);
  server.on("/delete", handleDelete);
  server.begin();
 
  Serial.println("System Ready [WSS Mode]");
}
 
// ================= LOOP =================
void loop() {
  handleWiFiConnection();

  processGPS(); 
  processPMS(); 

  if (wifiConnected) {
    server.handleClient();
    wsClient.loop(); // CRITICAL: Handle WS frames
    maintainMqtt();
    client.loop();
    
    #ifdef OTA_ENABLED
    if (otaPending) performOTA();
    #endif
  }
 
  // 1. งานทุก 5 วินาที
  if (millis() - last5s >= INTERVAL_5S) {
    last5s = millis();
    processDHT(); 
    publishData(); 
  }
 
  // 2. งานทุก 30 วินาที
  if (millis() - last30s >= INTERVAL_30S) {
    last30s = millis();
    saveToSD();
  }
 
  // Fast GPS publish
  if (millis() - lastGpsPublish >= GPS_INTERVAL) {
    lastGpsPublish = millis();
    publishGPS();
  }
}
 
// ================= FUNCTIONS =================
// ... (GPS, PMS, DHT, SD functions stay the same) ...

void maintainMqtt() {
  if (!client.connected() && wsClient.isConnected()) {
    Serial.printf("[MQTT] WSS Reconnecting to %s...\n", MQTT_SERVER);
    if (client.connect(bus_mac)) {
      Serial.println("[MQTT] WSS Connected!");
      #ifdef OTA_ENABLED
      client.subscribe(MQTT_TOPIC_OTA);
      #endif
    } else {
      Serial.printf("[MQTT] WSS Failed, state: %d\n", client.state());
    }
  }
}
 
void handleRoot() {
  server.send(200, "text/plain", "SUT BUS LOGGER - Running");
}
 
void handleDownload() {
  File file = SD.open(filename);
  if (file) {
    server.streamFile(file, "text/csv");
    file.close();
  } else {
    server.send(404, "text/plain", "File Not Found");
  }
}
 
void handleDelete() {
  SD.remove(filename);
  server.send(200, "text/plain", "Log File Deleted");
}

// =============================================================================
// MQTT Callback for OTA Commands
// =============================================================================

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());
  
  // Check for OTA update command
  #ifdef OTA_ENABLED
  if (String(topic).indexOf("ota") >= 0) {
    // Parse JSON using ArduinoJson (already included in this sketch)
    StaticJsonDocument<256> otaDoc;
    DeserializationError error = deserializeJson(otaDoc, message);
    
    if (!error && otaDoc.containsKey("url") && otaDoc.containsKey("version")) {
      otaUrl = otaDoc["url"].as<String>();
      otaVersion = otaDoc["version"].as<String>();
      
      Serial.printf("📥 OTA Update requested: v%s\n", otaVersion.c_str());
      Serial.printf("📥 Firmware URL: %s\n", otaUrl.c_str());
      
      // Check if we need to update
      bool forceUpdate = otaDoc["force"] | false;
      if (otaVersion == FIRMWARE_VERSION && !forceUpdate) {
        Serial.println("ℹ️ Already on this version, skipping update");
        return;
      }
      
      otaPending = true;
    }
  }
  #endif
}

// =============================================================================
// OTA (Over-The-Air) Update Functions
// =============================================================================

#ifdef OTA_ENABLED
void performOTA() {
  otaPending = false;
  
  if (otaUrl.length() == 0) {
    Serial.println("❌ OTA URL is empty");
    return;
  }
  
  Serial.println("🔄 Starting OTA update...");
  Serial.printf("📥 Downloading: %s\n", otaUrl.c_str());
  
  // Publish OTA status to MQTT
  StaticJsonDocument<128> statusDoc;
  statusDoc["status"] = "downloading";
  statusDoc["version"] = otaVersion;
  statusDoc["current"] = FIRMWARE_VERSION;
  char statusBuf[128];
  serializeJson(statusDoc, statusBuf);
  client.publish(MQTT_TOPIC, statusBuf);
  
  // Perform HTTP OTA update
  WiFiClient updateClient;
  httpUpdate.rebootOnUpdate(false);
  
  t_httpUpdate_return ret = httpUpdate.update(updateClient, otaUrl);
  
  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("❌ OTA Failed! Error (%d): %s\n", 
                    httpUpdate.getLastError(), 
                    httpUpdate.getLastErrorString().c_str());
      
      statusDoc.clear();
      statusDoc["status"] = "failed";
      statusDoc["error"] = httpUpdate.getLastErrorString();
      serializeJson(statusDoc, statusBuf);
      client.publish(MQTT_TOPIC, statusBuf);
      break;
      
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("ℹ️ No updates available");
      break;
      
    case HTTP_UPDATE_OK:
      Serial.println("✅ OTA Update successful! Rebooting...");
      
      statusDoc.clear();
      statusDoc["status"] = "success";
      statusDoc["version"] = otaVersion;
      statusDoc["rebooting"] = true;
      serializeJson(statusDoc, statusBuf);
      client.publish(MQTT_TOPIC, statusBuf);
      client.loop();
      
      delay(2000);
      ESP.restart();
      break;
  }
  
  otaUrl = "";
  otaVersion = "";
}
#endif