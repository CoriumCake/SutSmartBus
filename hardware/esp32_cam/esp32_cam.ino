#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPUpdate.h>
#include <PsychicMqttClient.h>
#include <Preferences.h>
#include "time.h"
#define CAMERA_MODEL_AI_THINKER
#include "camera_pins.h"
#include "config.h"

// Hardware Pins
#define BUZZER_PIN        13 // Active HIGH

// OTA state
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

// Direction Configuration
// Set to true if walking from Right (Zone R) to Left (Zone L) is an "Enter" event
// Set to false if walking from Left (Zone L) to Right (Zone R) is an "Enter" event
bool IS_RIGHT_TO_LEFT_ENTER = true;

// Detection Constants (Optimized)
int MOTION_THRESHOLD = 40;      // Difference in pixel value to count as motion
int TRIGGER_THRESHOLD = 1200;   // Number of motion pixels to trigger a zone
int ZONE_L = 60;                // Left line boundary (0-160)
int ZONE_R = 100;               // Right line boundary (0-160)
unsigned long COOLDOWN = 1200;  // ms between counts

// Globals
int passengerCount = 0;
int currentState = 0;           // 0=None, 1=Left, 2=Right
unsigned long lastCountTime = 0;
unsigned long lastMotionTime = 0;
uint8_t background[160 * 80];   // Background reference (160x80 ROI)
char bus_mac[18];
bool wifiConnected = false;
bool bgInitialized = false;

PsychicMqttClient mqttClient;
Preferences preferences;

// Audio Feedback
void beep(int duration) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(duration);
  digitalWrite(BUZZER_PIN, LOW);
}

// MQTT Functions
void sendMQTT(String dir) {
  if (!mqttClient.connected()) return;
  char buf[128];
  snprintf(buf, 128, "{\"bus_mac\":\"%s\",\"dir\":\"%s\",\"count\":%d,\"t\":%ld}", 
           bus_mac, dir.c_str(), passengerCount, millis()/1000);
  mqttClient.publish(MQTT_TOPIC_DETECTION, 1, false, buf);
}

void publishStatus() {
  if (!mqttClient.connected()) return;
  char buf[128];
  snprintf(buf, 128, "{\"bus_mac\":\"%s\",\"rssi\":%ld,\"uptime\":%lu,\"count\":%d}", 
           bus_mac, WiFi.RSSI(), millis()/1000, passengerCount);
  char topic[64];
  snprintf(topic, 64, "sut/bus/%s/status", bus_mac);
  mqttClient.publish(topic, 1, false, buf);
}

void performOTA() {
  otaPending = false;
  if (otaUrl.length() == 0) return;

  Serial.println("🔄 Starting OTA update...");
  Serial.printf("📥 Downloading: %s\n", otaUrl.c_str());

  WiFiClient client;
  httpUpdate.rebootOnUpdate(false);
  t_httpUpdate_return ret = httpUpdate.update(client, otaUrl);

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

void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup) {
  String message = String(payload);
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());

  if (String(topic).indexOf("ota") >= 0) {
    int urlStart = message.indexOf("\"url\":\"");
    int versionStart = message.indexOf("\"version\":\"");
    if (urlStart >= 0 && versionStart >= 0) {
      urlStart += 7;
      int urlEnd = message.indexOf("\"", urlStart);
      versionStart += 11;
      int versionEnd = message.indexOf("\"", versionStart);
      if (urlEnd > urlStart && versionEnd > versionStart) {
        otaUrl = message.substring(urlStart, urlEnd);
        otaVersion = message.substring(versionStart, versionEnd);
        Serial.printf("📥 OTA Update requested: v%s\n", otaVersion.c_str());
        otaPending = true;
      }
    }
  }
}

void reconnectMQTT() {
  if (strlen(MQTT_SERVER) == 0 || strcmp(MQTT_SERVER, "your_mqtt_host") == 0) {
    static bool warned = false;
    if (!warned) { Serial.println("⚠️ MQTT Blocked (Placeholder detected in config.h)"); warned = true; }
    return;
  }
  static unsigned long lastMqtt = 0;
  if (millis() - lastMqtt < 10000) return;
  lastMqtt = millis();
  
  char uri[128];
  snprintf(uri, 128, "mqtt://%s:%d", MQTT_SERVER, MQTT_PORT);
  Serial.printf("🔌 MQTT Connecting: %s\n", uri);
  
  mqttClient.onMessage(mqttCallback);
  mqttClient.onConnect([](bool sessionPresent) {
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
  });

  mqttClient.setServer(uri);
  mqttClient.setClientId(MQTT_CLIENT_ID);
  mqttClient.connect();
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  
  // Get MAC immediately
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(bus_mac, 18, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

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
  passengerCount = preferences.getInt("cnt", 0);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  beep(100); delay(100); beep(100); // Ready beeps
  Serial.println("🚌 Optimized Bus Cam Ready (Stripped-Down Serial)");
  Serial.printf("Direction Mode: R->L is %s\n", IS_RIGHT_TO_LEFT_ENTER ? "ENTER" : "EXIT");
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnected) { wifiConnected = true; Serial.println("✅ WiFi: " + WiFi.localIP().toString()); }
    if (!mqttClient.connected()) reconnectMQTT();
    if (otaPending) performOTA();
  }

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
      
      int diff = abs((int)p - (int)background[bgIdx]);
      if (diff > MOTION_THRESHOLD) {
        if (x < ZONE_L) motionL++;
        else if (x > ZONE_R) motionR++;
      }
      
      // Dynamic baseline: Slow leaky integrator (1/32 weight for current pixel)
      background[bgIdx] = (uint8_t)(((int)background[bgIdx] * 31 + (int)p) >> 5);
    }
  }

  // Noise Filter: If > 70% of a zone changes, it's global noise (lighting/shake)
  if (motionL > 3500 || motionR > 3500) {
    bgInitialized = false; 
    currentState = 0;
    Serial.println("🌫️ Massive Noise - Re-zeroing...");
    esp_camera_fb_return(fb);
    return;
  }

  bool triggerL = (motionL > TRIGGER_THRESHOLD);
  bool triggerR = (motionR > TRIGGER_THRESHOLD);

  // Skip frames where both zones trigger simultaneously (ambiguous)
  if (triggerL && triggerR) {
    esp_camera_fb_return(fb);
    return;
  }

  // Debug Print (only on state change or significant motion)
  static int lastL = 0, lastR = 0;
  if ((abs(motionL - lastL) > 200 || abs(motionR - lastR) > 200)) {
    Serial.printf("📊 L:%d R:%d S:%d\n", motionL, motionR, currentState);
    lastL = motionL; lastR = motionR;
  }

  // State Machine
  if (millis() - lastCountTime > COOLDOWN) {
    if (triggerL && currentState != 1) {
      if (currentState == 2) { // R -> L Event
        if (IS_RIGHT_TO_LEFT_ENTER) {
          passengerCount++;
          Serial.printf("🟢 ENTER Detected! Total: %d\n", passengerCount);
          sendMQTT("enter");
        } else {
          if (passengerCount > 0) passengerCount--;
          Serial.printf("🔴 EXIT Detected! Total: %d\n", passengerCount);
          sendMQTT("exit");
        }
        preferences.putInt("cnt", passengerCount);
        lastCountTime = millis();
        currentState = 0; 
        beep(200);
      } else {
        currentState = 1;
        lastMotionTime = millis();
      }
    } else if (triggerR && currentState != 2) {
      if (currentState == 1) { // L -> R Event
        if (IS_RIGHT_TO_LEFT_ENTER) {
          if (passengerCount > 0) passengerCount--;
          Serial.printf("🔴 EXIT Detected! Total: %d\n", passengerCount);
          sendMQTT("exit");
        } else {
          passengerCount++;
          Serial.printf("🟢 ENTER Detected! Total: %d\n", passengerCount);
          sendMQTT("enter");
        }
        preferences.putInt("cnt", passengerCount);
        lastCountTime = millis();
        currentState = 0;
        beep(200);
      } else {
        currentState = 2;
        lastMotionTime = millis();
      }
    }
    
    // Timeout if person lingers or disappears
    if (triggerL || triggerR) {
      lastMotionTime = millis();
    } else if (currentState != 0 && (millis() - lastMotionTime > 2000)) {
      currentState = 0;
      Serial.println("⏱️ State Reset (Timeout)");
    }
  }

  esp_camera_fb_return(fb);
  
  static unsigned long lastStat = 0;
  if (millis() - lastStat > 15000) { publishStatus(); lastStat = millis(); }
}
