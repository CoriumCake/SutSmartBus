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
// All settings are now in config.h
// Copy config.h.example to config.h and edit values
// WiFi networks list
struct WiFiNetwork {
  const char* ssid;
  const char* password;
};

// Backward compatibility for old config names
#ifndef WIFI_FALLBACK_1_SSID
  #ifdef WIFI_SSID_2
    #define WIFI_FALLBACK_1_SSID WIFI_SSID_2
    #define WIFI_FALLBACK_1_PASSWORD WIFI_PASSWORD_2
  #endif
#endif

const WiFiNetwork wifiNetworks[] = {
  {WIFI_SSID, WIFI_PASSWORD},
  #ifdef WIFI_FALLBACK_1_SSID
  {WIFI_FALLBACK_1_SSID, WIFI_FALLBACK_1_PASSWORD},
  #endif
};
const int wifiNetworkCount = sizeof(wifiNetworks) / sizeof(wifiNetworks[0]);
int currentWifiIndex = 0;

// WiFi connection settings (non-blocking)
bool wifiConnected = false;
unsigned long lastWifiAttempt = 0;
// Default timeout if not defined in config
#ifndef WIFI_TIMEOUT_MS
#define WIFI_TIMEOUT_MS 10000
#endif

const unsigned long WIFI_RETRY_INTERVAL = 10000;  // 10s retry
const unsigned long WIFI_CONNECT_TIMEOUT = WIFI_TIMEOUT_MS;
unsigned long wifiConnectStart = 0;
bool wifiConnecting = false;

// Bus Config
const char* bus_name    = BUS_NAME;
const char* web_name    = WEB_NAME;

const char* filename = "/gps.csv";

// ================= DHT =================
DHT dht(DHTPIN, DHTTYPE);
 
// ================= OBJECTS =================
WiFiClient espClient;
PubSubClient client(espClient);
StaticJsonDocument<512> doc;
WebServer server(80);
RTC_DS3231 rtc;
 
char bus_mac[18];
 
// ================= GPS =================
HardwareSerial gpsSerial(1);
TinyGPSPlus gps;
 
bool gpsValid = false;
double lastLat = 0;
double lastLon = 0;
 
// ================= DSM501 DATA =================
// Replaces PMS Serial
volatile unsigned long lowPulseOccupancy25 = 0; // PM2.5 (Vout1?) or config pin
volatile unsigned long lowPulseOccupancy10 = 0; // PM10
volatile unsigned long lastTrig25 = 0;
volatile unsigned long lastTrig10 = 0;

struct DSM_Data {
    uint16_t pm2_5_std;
    uint16_t pm10_0_std;
};
DSM_Data pmsData;
bool pmsDataValid = false;

// Interrupt Service Routines
void IRAM_ATTR onChangePM25() {
    if (digitalRead(DSM_PM25_PIN) == LOW) {
        lastTrig25 = micros();
    } else {
        lowPulseOccupancy25 += (micros() - lastTrig25);
    }
}

void IRAM_ATTR onChangePM10() {
    if (digitalRead(DSM_PM10_PIN) == LOW) {
        lastTrig10 = micros();
    } else {
        lowPulseOccupancy10 += (micros() - lastTrig10);
    }
}

// ================= DHT DATA =================
float tempC = 0;
float humid = 0;
 
// ================= TIMER CONFIG =================
unsigned long last5s = 0;
unsigned long last30s = 0;
unsigned long lastGpsPublish = 0;
unsigned long lastDsmRead = 0;
 
// ================= FUNCTION DECLARE =================
void tryConnectWiFi();
void handleWiFiConnection();
void maintainMqtt();
void processGPS();
void processDSM();
void processDHT();
void publishData();
void publishGPS();
void saveToSD();
void handleRoot();
void handleDownload();
void handleDelete();
void mqttCallback(char* topic, byte* payload, unsigned int length);
#ifdef OTA_ENABLED
void performOTA();
#endif
 
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
  client.setServer(MQTT_SERVER, MQTT_PORT); // Use macros directly
  client.setCallback(mqttCallback);  // Set callback for OTA commands
 
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  
  // DSM501 Setup
  pinMode(DSM_PM25_PIN, INPUT);
  pinMode(DSM_PM10_PIN, INPUT);
  attachInterrupt(digitalPinToInterrupt(DSM_PM25_PIN), onChangePM25, CHANGE);
  attachInterrupt(digitalPinToInterrupt(DSM_PM10_PIN), onChangePM10, CHANGE);
  lastDsmRead = millis();

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
 
  Serial.println("System Ready - [5s: MQTT/Serial] [30s: SD Card]");
}
 
// ================= LOOP =================
void loop() {
  handleWiFiConnection();

  processGPS(); 
  processDSM(); // Process accumulated Pulse Occupancy

  if (wifiConnected) {
    server.handleClient();
    maintainMqtt();
    client.loop();
    
    // Check if OTA update is pending
    #ifdef OTA_ENABLED
    if (otaPending) {
      performOTA();
    }
    #endif
  }
 
  // 1. งานทุก 5 วินาที: อัปเดต Serial และส่งข้อมูลไป Server (MQTT)
  if (millis() - last5s >= INTERVAL_5S) {
    last5s = millis();
 
    processDHT(); // อ่านค่า Temp/Humid ล่าสุด
 
    Serial.println("\n--- [ 5 SECONDS UPDATE ] ---");
    if (pmsDataValid) {
      Serial.printf("DSM: PM2.5=%d, PM10=%d | ", pmsData.pm2_5_std, pmsData.pm10_0_std);
    }
    Serial.printf("DHT: T=%.1f, H=%.0f\n", tempC, humid);
 
    publishData(); // ส่งไป MQTT
  }
 
  // 2. งานทุก 30 วินาที: บันทึกลง SD Card
  if (millis() - last30s >= INTERVAL_30S) {
    last30s = millis();
 
    Serial.println(">>> [ 30 SECONDS UPDATE: SAVING TO SD CARD ] <<<");
    saveToSD();
  }
 
  // (Optional) Fast GPS publish ทุก 500ms ถ้ายังจำเป็นต้องใช้
  if (millis() - lastGpsPublish >= GPS_INTERVAL) {
    lastGpsPublish = millis();
    publishGPS();
  }
}
 
// ================= FUNCTIONS =================
 
void processGPS() {
  while (gpsSerial.available()) {
    gps.encode(gpsSerial.read());
  }
  if (gps.location.isValid()) {
    gpsValid = true;
    lastLat = gps.location.lat();
    lastLon = gps.location.lng();
  }
}

// Convert LPO ratio to concentration (Simple approximation)
// DSM501 datasheet curve:
// Ratio 0-2% ~ 0 ug/m3? No, ~0.
// Ratio 5% ~ 5000 pcs/283ml (~50 ug/m3?)
// Very rough formula: Concentration = output * coeff
// We will use a standard polynomial or linear mapping commonly found in examples
float calculateConcentration(float ratio) {
  // x = ratio (0-100)
  // y = 0.62 * x^2 + 0.032 * x + 0.001 (sample from online)
  // Or linear: Ratio * 1000 roughly? 
  // Let's use a simple linear map for now as per many Arduino examples
  // 0 - 20% covers typical range
  return 1.1 * pow(ratio, 3) - 3.8 * pow(ratio, 2) + 520 * ratio + 0.62; // Spec sheet curve approx
}

void processDSM() {
  // Calculate every second or so, but we reset every INTERVAL_5S effectively in the loop logic?
  // Actually, loop calls this constantly. We should latch data every X seconds.
  // The main loop uses INTERVAL_5S. We should match that.
  
  if (millis() - lastDsmRead >= 5000) {
      unsigned long duration = millis() - lastDsmRead;
      
      // Calculate Ratio
      float ratio25 = (lowPulseOccupancy25 / 1000.0) / duration * 100.0; // %
      float ratio10 = (lowPulseOccupancy10 / 1000.0) / duration * 100.0; // %

      // Reset
      lowPulseOccupancy25 = 0;
      lowPulseOccupancy10 = 0;
      lastDsmRead = millis();

      // Convert to Concentration (Fake mapping for now, needs calibration)
      // Usually Vout1 (>1um) is PM2.5? Vout2 (>2.5um) is PM10?
      // Wait, Vout2 is larger particles (>2.5?)
      // We mapped Pin 16 to PM25, Pin 17 to PM10. 
      // Let's assume ratio -> approx ug/m3.
      
      // Simple linear for display valid only
      // If we use the curve, we need ratio 0-15%.
      
      pmsData.pm2_5_std = (uint16_t)(ratio25 * 100); // Just sending raw ratio*100 for debugging if no curve
      pmsData.pm10_0_std = (uint16_t)(ratio10 * 100);
      
      // Real curve attempt
      // pmsData.pm2_5_std = calculateConcentration(ratio25);
      
      pmsDataValid = true;  
  }
}
 
void processDHT() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (!isnan(t) && !isnan(h)) {
    tempC = t;
    humid = h;
  }
}
 
void publishData() {
  if (!client.connected()) return;
  doc.clear();
  doc["bus_mac"] = bus_mac;
  doc["bus_name"] = bus_name;
  if (gpsValid) {
    doc["lat"] = lastLat;
    doc["lon"] = lastLon;
  }
  if (pmsDataValid) {
    doc["pm2_5"] = pmsData.pm2_5_std;
    doc["pm10"]  = pmsData.pm10_0_std;
  }
  doc["temp"] = tempC;
  doc["hum"]  = humid;
  char payload[256];
  serializeJson(doc, payload);
  client.publish(MQTT_TOPIC, payload); // Use macro directly
  Serial.print("MQTT Sent: "); Serial.println(payload);
}
 
void publishGPS() {
  if (!client.connected() || !gpsValid) return;
  StaticJsonDocument<128> gpsDoc;
  gpsDoc["bus_mac"] = bus_mac;
  gpsDoc["bus_name"] = bus_name;
  gpsDoc["lat"] = lastLat;
  gpsDoc["lon"] = lastLon;
  char payload[128];
  serializeJson(gpsDoc, payload);
  client.publish(MQTT_TOPIC_FAST, payload); // Use macro directly
}
 
void saveToSD() {
  File file = SD.open(filename, FILE_APPEND);
  if (!file) {
    Serial.println("SD Error: Open Fail");
    return;
  }
  DateTime now = rtc.now();
  char dateStr[11], timeStr[9];
  sprintf(dateStr, "%04d/%02d/%02d", now.year(), now.month(), now.day());
  sprintf(timeStr, "%02d:%02d:%02d", now.hour(), now.minute(), now.second());
  file.print(dateStr); file.print(",");
  file.print(timeStr); file.print(",");
  file.print(gpsValid ? String(lastLat, 6) : ""); file.print(",");
  file.print(gpsValid ? String(lastLon, 6) : ""); file.print(",");
  file.print(pmsDataValid ? String(pmsData.pm2_5_std) : ""); file.print(",");
  file.print(pmsDataValid ? String(pmsData.pm10_0_std) : ""); file.print(",");
  file.print(tempC, 1); file.print(",");
  file.print(humid, 0); file.println(",RTC");
  file.close();
  Serial.println("SD Card: Data Logged Success");
}
 
void tryConnectWiFi() {
  if (wifiConnecting) return;
  
  WiFi.disconnect(true);
  delay(100);
  
  Serial.printf("📶 Trying WiFi %d/%d: %s\n", 
                currentWifiIndex + 1, wifiNetworkCount, 
                wifiNetworks[currentWifiIndex].ssid);
  
  WiFi.begin(wifiNetworks[currentWifiIndex].ssid, 
             wifiNetworks[currentWifiIndex].password);
  
  wifiConnecting = true;
  wifiConnectStart = millis();
  lastWifiAttempt = millis();
}

void handleWiFiConnection() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      wifiConnecting = false;
      Serial.println("\n✅ WiFi Connected: " + WiFi.localIP().toString());
    }
    return;
  }
  
  if (wifiConnected) {
    wifiConnected = false;
    Serial.println("⚠️ WiFi Disconnected");
  }
  
  if (wifiConnecting) {
    if (millis() - wifiConnectStart > WIFI_CONNECT_TIMEOUT) {
      Serial.printf("⏱️ Timeout on %s\n", wifiNetworks[currentWifiIndex].ssid);
      wifiConnecting = false;
      currentWifiIndex = (currentWifiIndex + 1) % wifiNetworkCount;
      tryConnectWiFi();
    }
    return;
  }
  
  if (millis() - lastWifiAttempt > WIFI_RETRY_INTERVAL) {
    tryConnectWiFi();
  }
}
 
void maintainMqtt() {
  if (!client.connected()) {
    Serial.printf("[MQTT] Attempting connection to %s:%d...\n", MQTT_SERVER, MQTT_PORT);
    Serial.printf("[MQTT] WiFi Status: %s, IP: %s\n", 
                  WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected",
                  WiFi.localIP().toString().c_str());
 
    if (client.connect(bus_mac)) {
      Serial.println("[MQTT] Connected successfully!");
      
      // Subscribe to OTA topic
      #ifdef OTA_ENABLED
      client.subscribe(MQTT_TOPIC_OTA);
      Serial.printf("📥 Subscribed to OTA topic: %s\n", MQTT_TOPIC_OTA);
      Serial.printf("📌 Current firmware version: %s\n", FIRMWARE_VERSION);
      #endif
    } else {
      int state = client.state();
      Serial.printf("[MQTT] Connection FAILED! Error code: %d\n", state);
    }
  }
}
 
void handleRoot() {
  server.send(200, "text/plain", "SUT BUS LOGGER (DSM501 Version) - Running");
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

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());
  
  #ifdef OTA_ENABLED
  if (String(topic).indexOf("ota") >= 0) {
    StaticJsonDocument<256> otaDoc;
    DeserializationError error = deserializeJson(otaDoc, message);
    
    if (!error && otaDoc.containsKey("url") && otaDoc.containsKey("version")) {
      otaUrl = otaDoc["url"].as<String>();
      otaVersion = otaDoc["version"].as<String>();
      
      Serial.printf("📥 OTA Update requested: v%s\n", otaVersion.c_str());
      
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

#ifdef OTA_ENABLED
void performOTA() {
  otaPending = false;
  if (otaUrl.length() == 0) return;
  
  Serial.println("🔄 Starting OTA update...");
  StaticJsonDocument<128> statusDoc;
  statusDoc["status"] = "downloading";
  statusDoc["version"] = otaVersion;
  char statusBuf[128];
  serializeJson(statusDoc, statusBuf);
  client.publish(MQTT_TOPIC, statusBuf);
  
  WiFiClient updateClient;
  httpUpdate.rebootOnUpdate(false);
  t_httpUpdate_return ret = httpUpdate.update(updateClient, otaUrl);
  
  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("❌ OTA Failed! Error (%d): %s\n", httpUpdate.getLastError(), httpUpdate.getLastErrorString().c_str());
      break;
    case HTTP_UPDATE_OK:
      Serial.println("✅ OTA Update successful! Rebooting...");
      statusDoc["status"] = "success";
      statusDoc["rebooting"] = true;
      serializeJson(statusDoc, statusBuf);
      client.publish(MQTT_TOPIC, statusBuf);
      client.loop();
      delay(2000);
      ESP.restart();
      break;
    default:
      break;
  }
  otaUrl = "";
  otaVersion = "";
}
#endif
