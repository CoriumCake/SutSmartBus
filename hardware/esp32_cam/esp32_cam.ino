#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPUpdate.h>
#include <PsychicMqttClient.h>
#include <Preferences.h>
#include <WebServer.h>
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
bool IS_RIGHT_TO_LEFT_ENTER = false;

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
bool mqttConfigured = false;

PsychicMqttClient mqttClient;
Preferences preferences;
WebServer httpServer(80);

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

void setupMQTT() {
  if (strlen(MQTT_SERVER) == 0 || strcmp(MQTT_SERVER, "your_mqtt_host") == 0) {
    Serial.println("⚠️ MQTT Blocked (Placeholder detected in config.h)");
    return;
  }
  char uri[128];
  snprintf(uri, 128, "mqtt://%s:%d", MQTT_SERVER, MQTT_PORT);
  Serial.printf("🔌 MQTT Configured: %s\n", uri);

  mqttClient.onMessage(mqttCallback);
  mqttClient.onConnect([](bool sessionPresent) {
    Serial.println("✅ MQTT Connected");
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
  });
  mqttClient.setServer(uri);
  mqttClient.setClientId(MQTT_CLIENT_ID);
  mqttConfigured = true;
}

void reconnectMQTT() {
  if (!mqttConfigured) return;
  static unsigned long lastMqtt = 0;
  if (millis() - lastMqtt < 10000) return;
  lastMqtt = millis();
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
  setupMQTT();

  httpServer.on("/", handleRoot);
  httpServer.on("/capture", handleCapture);
  httpServer.begin();
  Serial.println("🌐 HTTP server started on port 80");

  beep(100); delay(100); beep(100); // Ready beeps
  Serial.println("🚌 Optimized Bus Cam Ready (Stripped-Down Serial)");
  Serial.printf("Direction Mode: R->L is %s\n", IS_RIGHT_TO_LEFT_ENTER ? "ENTER" : "EXIT");
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      Serial.println("✅ WiFi: " + WiFi.localIP().toString());
      Serial.println("🌐 Live view: http://" + WiFi.localIP().toString());
    }
    if (!mqttClient.connected()) reconnectMQTT();
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
    if (!triggerL && !triggerR) {
      currentState = 0;
      Serial.println("✅ Zone Cleared, Ready");
    }
  }

  // Robust State Machine (cooldown only guards counting, not clearing)
  if (millis() - lastCountTime > COOLDOWN) {
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
      if (triggerR) {
        // Event: L -> R
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
        currentState = 3; // WAIT_CLEAR
        beep(200);
      } else if (millis() - lastMotionTime > 2000) {
        currentState = 0;
        Serial.println("⏱️ State Reset Left (Timeout)");
      }
    }
    else if (currentState == 2) { // ENTERED_R
      if (triggerL) {
        // Event: R -> L
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
        currentState = 3; // WAIT_CLEAR
        beep(200);
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
