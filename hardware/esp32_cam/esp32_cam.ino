#include "esp_camera.h"
#include <WiFi.h>
#include <PubSubClient.h>
#include <HTTPUpdate.h>  // For HTTP-based OTA updates
#include <WebServer.h> // Add WebServer include
#include <Preferences.h> // INTERNAL STORAGE
#include "time.h"
#include "config.h"  // ⚠️ Create from config.h.example with your credentials

// OTA update state
bool otaPending = false;
String otaUrl = "";
String otaVersion = "";

#define DETECT_LED 12  // Red LED (Exit / Status)
#define LED_RED_PIN 12
#define LED_GREEN_PIN 14 // Green LED (Enter)
#define BUZZER_PIN 13  // Buzzer on GPIO 13 - HIGH = beep, LOW = silent 

// Non-blocking LED timers
unsigned long redLedOffTime = 0;
unsigned long greenLedOffTime = 0;

// NTP settings for timestamp (from config.h)
const char* ntpServer = NTP_SERVER;
const long gmtOffset_sec = GMT_OFFSET_SEC;
const int daylightOffset_sec = DAYLIGHT_OFFSET;
bool timeConfigured = false;

// WiFi networks list (from config.h)
struct WiFiNetwork {
  const char* ssid;
  const char* password;
};

// Default WiFi from config.h
const char* DEFAULT_WIFI_SSID = WIFI_SSID;
const char* DEFAULT_WIFI_PASS = WIFI_PASSWORD;

const unsigned long DEFAULT_WIFI_TIMEOUT = WIFI_TIMEOUT_MS;

// Fallback WiFi networks from config.h
const WiFiNetwork wifiNetworks[] = {
  {WIFI_FALLBACK_1_SSID, WIFI_FALLBACK_1_PASSWORD},
  {WIFI_FALLBACK_2_SSID, WIFI_FALLBACK_2_PASSWORD},
};
const int wifiNetworkCount = sizeof(wifiNetworks) / sizeof(wifiNetworks[0]);
int currentWifiIndex = 0;

// MQTT servers list from config.h
struct MQTTServer {
  const char* host;
  int port;
};

const MQTTServer mqttServers[] = {
  {MQTT_SERVER_BACKUP, MQTT_PORT_BACKUP},  // Backup (empty = skip)
  {MQTT_SERVER, MQTT_PORT},                 // Primary server
};
const int mqttServerCount = sizeof(mqttServers) / sizeof(mqttServers[0]);
int currentMqttIndex = 0;
const char* mqtt_topic = MQTT_TOPIC_DETECTION;

// fixed settings
const int LEFT_ZONE = 70;   // wider left tolerance (QQVGA 160x120 scale)
const int RIGHT_ZONE = 90;  // wider right tolerance
const int MOTION_THRESHOLD = 25; // Adjusted for smaller resolution
const unsigned long COOLDOWN_MS = 2000;  // 2s between counts

// WiFi connection settings (non-blocking)
bool wifiConnected = false;
unsigned long lastWifiAttempt = 0;
const unsigned long WIFI_RETRY_INTERVAL = 10000;  // 1 minute
const unsigned long WIFI_CONNECT_TIMEOUT = 4000;  // 4s per network (non-blocking)
unsigned long wifiConnectStart = 0;
bool wifiConnecting = false;

// Internal Storage (Preferences)
Preferences preferences;

WiFiClient espClient;
PubSubClient mqttClient(espClient);
int passengerCount = 0;
int state = 0;  // 0=none, 1=left, 2=right
unsigned long lastCountTime = 0;
uint8_t roiPrev[4800] = {0}; // 160 width * 30 height

WebServer server(80);

void handleRoot() {
  String html = "<html><head><title>SUT Bus Camera</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;text-align:center;margin:0;padding:20px;background:#222;color:#eee;}";
  html += "img{width:95%;max-width:800px;height:auto;border:2px solid #fff;image-rendering:pixelated;image-rendering:-moz-crisp-edges;}";
  html += "button{padding:10px 20px;font-size:16px;cursor:pointer;background:#007bff;color:white;border:none;border-radius:5px;}";
  html += "</style></head><body>";
  html += "<h1>Bus Camera Calibration</h1>";
  html += "<div><img src='/capture' id='cam' onload='setTimeout(refresh, 500)'></div>";
  html += "<br><p>Refreshes automatically for positioning. <a href='/capture' target='_blank'>Snapshot</a></p>";
  html += "<script>function refresh(){ document.getElementById('cam').src = '/capture?t=' + new Date().getTime(); }</script>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

void handleCapture() {
  // Capture a frame
  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) {
    server.send(500, "text/plain", "Camera Capture Failed");
    return;
  }
  
  // We need to send the image buffer. 
  // Note: If you want to see the "flipped" and "drawn" image, you would need to process it here similar to saveImageToSD
  // For now, we just send the raw frame for positioning.
  // Ideally, if the camera is mounted upside down, we should flip it here too so the user sees the correct orientation.
  
  // Send as JPEG (Note: config is GRAYSCALE QQVGA, browsers might not display raw grayscale well?)
  // Wait, config says PIXFORMAT_GRAYSCALE? 
  // Browsers expect JPEG. We should checking config. 
  // If PIXFORMAT_GRAYSCALE, we need to convert or re-init camera?
  // Actually, for streaming/viewing, PIXFORMAT_JPEG is much better.
  // The detection logic uses grayscale. This might be a conflict.
  // IF we want to view it, we might need to change pixel format potentially?
  // Or maybe we can send BMP header + grayscale data like saveImageToSD?
  // Let's send BMP for compatibility with the grayscale buffer we have.
  
  // BMP Header construction (similar to saveImageToSD but streaming)
  // ... Or just send raw stream if we change format to JPEG?
  // Detection works best on Grayscale.
  // Let's implement a BMP sender for the browser since we are in Grayscale mode.

    size_t width = 160;
    size_t height = 120;
    size_t imageSize = width * height;
    size_t fileSize = 54 + 1024 + imageSize; // Header + Palette + Data
    
    // BMP Header
    uint8_t bmpHeader[54 + 1024];
    memset(bmpHeader, 0, 54 + 1024);
    
    bmpHeader[0] = 'B'; bmpHeader[1] = 'M';
    bmpHeader[2] = fileSize & 0xFF; bmpHeader[3] = (fileSize >> 8) & 0xFF;
    bmpHeader[4] = (fileSize >> 16) & 0xFF; bmpHeader[5] = (fileSize >> 24) & 0xFF;
    bmpHeader[10] = (54 + 1024) & 0xFF; bmpHeader[11] = ((54 + 1024) >> 8) & 0xFF;
    
    bmpHeader[14] = 40;
    bmpHeader[18] = width & 0xFF; bmpHeader[19] = (width >> 8) & 0xFF;
    // create top-down bitmap (negative height)
    int32_t netHeight = -((int32_t)height); 
    bmpHeader[22] = netHeight & 0xFF; bmpHeader[23] = (netHeight >> 8) & 0xFF;
    bmpHeader[24] = (netHeight >> 16) & 0xFF; bmpHeader[25] = (netHeight >> 24) & 0xFF;
    
    bmpHeader[26] = 1; bmpHeader[28] = 8; // 1 plane, 8 bpp
    bmpHeader[30] = 0; // No compression
    bmpHeader[34] = imageSize & 0xFF; bmpHeader[35] = (imageSize >> 8) & 0xFF; 
    bmpHeader[36] = (imageSize >> 16) & 0xFF;

    // Palette (Grayscale)
    for (int i = 0; i < 256; i++) {
        int offset = 54 + (i * 4);
        bmpHeader[offset] = i;      // B
        bmpHeader[offset + 1] = i;  // G
        bmpHeader[offset + 2] = i;  // R
        bmpHeader[offset + 3] = 0;
    }

    WiFiClient client = server.client();
    client.write("HTTP/1.1 200 OK\r\nContent-Type: image/bmp\r\nConnection: close\r\n\r\n");
    client.write(bmpHeader, 54 + 1024);
    client.write(fb->buf, fb->len);
    
  esp_camera_fb_return(fb);
}

// AI-Thinker pins


// AI-Thinker pins
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

// Helper function to draw a horizontal line on the frame buffer
void drawHLine(uint8_t* buf, int width, int x1, int x2, int y, uint8_t color) {
  if (y < 0 || y >= 120) return; // Adjusted for QQVGA
  for (int x = max(0, x1); x <= min(width-1, x2); x++) {
    buf[y * width + x] = color;
  }
}

// Helper function to draw a vertical line on the frame buffer
void drawVLine(uint8_t* buf, int width, int x, int y1, int y2, uint8_t color) {
  if (x < 0 || x >= width) return;
  for (int y = max(0, y1); y <= min(119, y2); y++) {
    buf[y * width + x] = color;
  }
}

// Draw rectangle on frame buffer
void drawRect(uint8_t* buf, int width, int x1, int y1, int x2, int y2, uint8_t color) {
  drawHLine(buf, width, x1, x2, y1, color);  // Top
  drawHLine(buf, width, x1, x2, y2, color);  // Bottom
  drawVLine(buf, width, x1, y1, y2, color);  // Left
  drawVLine(buf, width, x2, y1, y2, color);  // Right
}

// Draw arrow pattern for direction indication
// ENTER (L→R): draws >>> pattern
// EXIT (R→L): draws <<< pattern
void drawDirectionArrow(uint8_t* buf, int width, bool isEnter) {
  int startX = isEnter ? 5 : 140;  // Position based on direction (scaled for 160)
  int y = 8;
  uint8_t color = 255;  // White
  
  for (int i = 0; i < 3; i++) {  // 3 arrows
    int baseX = isEnter ? (startX + i * 20) : (startX - i * 20);
    if (isEnter) {
      // Draw > arrow
      for (int j = 0; j < 8; j++) {
        int px = baseX + j;
        int py1 = y - j;
        int py2 = y + j;
        if (px >= 0 && px < width) {
          if (py1 >= 0 && py1 < 120) buf[py1 * width + px] = color;
          if (py2 >= 0 && py2 < 120) buf[py2 * width + px] = color;
        }
      }
    } else {
      // Draw < arrow
      for (int j = 0; j < 8; j++) {
        int px = baseX - j;
        int py1 = y - j;
        int py2 = y + j;
        if (px >= 0 && px < width) {
          if (py1 >= 0 && py1 < 120) buf[py1 * width + px] = color;
          if (py2 >= 0 && py2 < 120) buf[py2 * width + px] = color;
        }
      }
    }
  }
}

// Flip image 180 degrees (upside down correction)
void flipImage(uint8_t* buf, int width, int height) {
  for (int y = 0; y < height / 2; y++) {
    for (int x = 0; x < width; x++) {
      int topIdx = y * width + x;
      int botIdx = (height - 1 - y) * width + (width - 1 - x);
      uint8_t temp = buf[topIdx];
      buf[topIdx] = buf[botIdx];
      buf[botIdx] = temp;
    }
  }
}

// LED control functions
void ledOn() {
  digitalWrite(DETECT_LED, HIGH);
}

void ledOff() {
  digitalWrite(DETECT_LED, LOW);
}

// Non-blocking triggers (1 second duration)
void triggerRedLed() {
  digitalWrite(LED_RED_PIN, HIGH);
  redLedOffTime = millis() + 1000;
}

void triggerGreenLed() {
  digitalWrite(LED_GREEN_PIN, HIGH);
  greenLedOffTime = millis() + 1000;
}

void handleLeds() {
  if (redLedOffTime > 0 && millis() > redLedOffTime) {
    digitalWrite(LED_RED_PIN, LOW);
    redLedOffTime = 0;
  }
  if (greenLedOffTime > 0 && millis() > greenLedOffTime) {
    digitalWrite(LED_GREEN_PIN, LOW);
    greenLedOffTime = 0;
  }
}

// Rapid blink LED for 3 seconds (WiFi success indication)
void rapidBlinkLED(int durationMs) {
  unsigned long endTime = millis() + durationMs;
  while (millis() < endTime) {
    digitalWrite(DETECT_LED, HIGH);
    delay(50);
    digitalWrite(DETECT_LED, LOW);
    delay(50);
  }
}

// Ring bell function - beep pattern for passenger notification
// ACTIVE HIGH: HIGH = beep, LOW = silent
void ringBell() {
  Serial.println("🔔 RING BELL TRIGGERED!");
  
  // 0.5 second long beep
  digitalWrite(BUZZER_PIN, HIGH);
  delay(500);
  digitalWrite(BUZZER_PIN, LOW);
  
  delay(150);  // Short pause
  
  // 0.25 second short beep
  digitalWrite(BUZZER_PIN, HIGH);
  delay(250);
  digitalWrite(BUZZER_PIN, LOW);
  
  Serial.println("🔔 Ring complete");
}

// MQTT callback for receiving commands
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());
  
  // Check for ring command
  if (String(topic).indexOf("ring") >= 0) {
    ringBell();
  }
  
  // Check for OTA update command
  #ifdef OTA_ENABLED
  if (String(topic).indexOf("ota") >= 0) {
    // Parse JSON to get URL and version
    // Simple parsing without ArduinoJson to save memory
    int urlStart = message.indexOf("\"url\":\"");
    int versionStart = message.indexOf("\"version\":\"");
    
    if (urlStart >= 0 && versionStart >= 0) {
      urlStart += 7;  // Skip "url":"
      int urlEnd = message.indexOf("\"", urlStart);
      
      versionStart += 11;  // Skip "version":"
      int versionEnd = message.indexOf("\"", versionStart);
      
      if (urlEnd > urlStart && versionEnd > versionStart) {
        otaUrl = message.substring(urlStart, urlEnd);
        otaVersion = message.substring(versionStart, versionEnd);
        
        Serial.printf("📥 OTA Update requested: v%s\n", otaVersion.c_str());
        Serial.printf("📥 Firmware URL: %s\n", otaUrl.c_str());
        
        // Check if we need to update (skip if same version unless forced)
        bool forceUpdate = message.indexOf("\"force\":true") >= 0;
        if (otaVersion == FIRMWARE_VERSION && !forceUpdate) {
          Serial.println("ℹ️ Already on this version, skipping update");
          return;
        }
        
        // Set flag to perform OTA in main loop (not in callback!)
        otaPending = true;
      }
    }
  }
  #endif
}

// Function to save image to SD card - accepts frame buffer and bounding box
// Saves as BMP format with rectangle overlay and direction arrow
// Image saving removed for NVS storage mode


void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("🚌 STABLE Bus Counter v1.2 (with SD Card + Timestamp)");
  
  Serial.printf("🔍 Heap: Free=%d MaxAlloc=%d\n", ESP.getFreeHeap(), ESP.getMaxAllocHeap());
  Serial.printf("🔍 PSRAM: Size=%d Free=%d\n", ESP.getPsramSize(), ESP.getFreePsram());
  
  if (ESP.getPsramSize() == 0) {
    Serial.println("⚠️ WARNING: PSRAM not found! Check Tools > PSRAM > Enabled in Arduino IDE.");
  }

  // Initialize LED for detection indicator
  pinMode(LED_RED_PIN, OUTPUT);
  digitalWrite(LED_RED_PIN, LOW);
  
  pinMode(LED_GREEN_PIN, OUTPUT);
  digitalWrite(LED_GREEN_PIN, LOW);
  
  // Initialize Buzzer pin - ACTIVE HIGH (HIGH = beep, LOW = silent)
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);  // Start with buzzer OFF

  // IMPORTANT: Initialize camera FIRST before SD card to avoid I2C conflicts
  // camera config
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
  config.xclk_freq_hz = 16000000;
  config.pixel_format = PIXFORMAT_GRAYSCALE;  // Use grayscale for detection
  config.frame_size = FRAMESIZE_QQVGA; // 160x120 to save memory
  config.jpeg_quality = 12;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("❌ Camera");
    while(1);
  }

  sensor_t * s = esp_camera_sensor_get();
  s->set_contrast(s, 2);
  s->set_vflip(s, 1);   // Flip vertically
  s->set_hmirror(s, 1); // Mirror horizontally (combined with vflip = 180° rotation)
  Serial.println("✅ Camera");

  // NVS Storage Init
  preferences.begin("bus-data", false);
  passengerCount = preferences.getInt("count", 0);
  Serial.printf("💾 Restored Passenger Count: %d\n", passengerCount);
  
  // Initialize SD card removed - using NVS

  // Try default WiFi first (4 second timeout)
  Serial.printf("📡 Trying default WiFi: %s\n", DEFAULT_WIFI_SSID);
  WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
  
  unsigned long startAttempt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < DEFAULT_WIFI_TIMEOUT) {
    delay(100);
    Serial.print(".");
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("\n✅ Default WiFi Connected: " + WiFi.localIP().toString());
    
    // Keep LED on for 3 seconds to indicate success
    ledOn();
    Serial.printf("🎥 View Live Camera at http://%s/\n", WiFi.localIP().toString().c_str());
    delay(3000);
    ledOff();
    
    // Configure NTP time
    configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
    Serial.println("🕐 NTP time configured");
    timeConfigured = true;
  } else {
    Serial.println("\n⚠️ Default WiFi failed - will try fallback networks");
    Serial.println("📱 Detection will work offline, retrying WiFi every 1 minute");
    wifiConnecting = false;
    lastWifiAttempt = millis();
  }

  Serial.println("🛡️ STABLE MODE - 2s cooldown active");
  Serial.println(" NVS Storage Enabled (No SD Card)");

  // Calibration Server
  server.on("/", handleRoot);
  server.on("/capture", handleCapture);
  server.begin();
  Serial.println("🌐 Web Server started");
  if (wifiConnected) {
      Serial.printf("🎥 View Live Camera at http://%s/\n", WiFi.localIP().toString().c_str());
  }
}


// Try to connect to next WiFi network in the list
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

// Handle non-blocking WiFi connection (call in loop)
void handleWiFiConnection() {
  // Check if connected
  if (WiFi.status() == WL_CONNECTED) {
    if (!wifiConnected) {
      wifiConnected = true;
      wifiConnecting = false;
      Serial.println("\n✅ WiFi Connected: " + WiFi.localIP().toString());
      Serial.printf("🎥 View Live Camera at http://%s/\n", WiFi.localIP().toString().c_str());
      
      // Configure NTP time
      if (!timeConfigured) {
        configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
        Serial.println("🕐 NTP time configured");
        timeConfigured = true;
      }
    }
    return;
  }
  
  // WiFi disconnected
  if (wifiConnected) {
    wifiConnected = false;
    Serial.println("⚠️ WiFi Disconnected");
  }
  
  // If currently trying to connect, check timeout
  if (wifiConnecting) {
    if (millis() - wifiConnectStart > WIFI_CONNECT_TIMEOUT) {
      Serial.printf("⏱️ Timeout on %s\n", wifiNetworks[currentWifiIndex].ssid);
      wifiConnecting = false;
      // Move to next network
      currentWifiIndex = (currentWifiIndex + 1) % wifiNetworkCount;
      // Try next network immediately
      tryConnectWiFi();
    }
    return;
  }
  
  // If not connecting and interval passed, try again
  if (millis() - lastWifiAttempt > WIFI_RETRY_INTERVAL) {
    tryConnectWiFi();
  }
}

void loop() {
  // Handle LEDs (non-blocking)
  handleLeds();

  // Handle WiFi connection (non-blocking)
  handleWiFiConnection();
  server.handleClient(); // Handle web requests

  
  // Only handle MQTT if WiFi is connected
  if (wifiConnected) {
    if (!mqttClient.connected()) reconnectMQTT();
    mqttClient.loop();
    
    // Check if OTA update is pending
    #ifdef OTA_ENABLED
    if (otaPending) {
      performOTA();
    }
    #endif
  }

  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) return;

  // ROI scan (door area) - track bounding box of dark pixels
  int motion = 0, dark = 0, blobX = 0;
  int blobMinX = 160, blobMaxX = 0, blobMinY = 120, blobMaxY = 0;
  int roiIdx = 0;
  
  for (int y = 40; y < 70; y++) {
    for (int x = 0; x < 160; x++) {
      int idx = y * 160 + x;
      uint8_t p = fb->buf[idx];
      
      int diff = abs((int)p - (int)roiPrev[roiIdx]);
      if (diff > 25) motion++;
      
      if (p < 90) {
        dark++;
        blobX += x;
        // Track bounding box
        if (x < blobMinX) blobMinX = x;
        if (x > blobMaxX) blobMaxX = x;
        if (y < blobMinY) blobMinY = y;
        if (y > blobMaxY) blobMaxY = y;
      }
      roiPrev[roiIdx++] = p;
    }
  }
  
  blobX /= max(1, dark);
  
  // Ensure valid bounding box (add padding)
  if (blobMinX > blobMaxX) { blobMinX = blobX - 15; blobMaxX = blobX + 15; }
  if (blobMinY > blobMaxY) { blobMinY = 40; blobMaxY = 70; }
  blobMinX = max(0, blobMinX - 3);
  blobMaxX = min(159, blobMaxX + 3);
  blobMinY = max(0, blobMinY - 3);
  blobMaxY = min(119, blobMaxY + 3);

  // Debug output every 2 seconds to monitor detection
  static unsigned long lastDebugTime = 0;
  if (millis() - lastDebugTime > 2000) {
    Serial.printf("📊 motion:%d dark:%d blobX:%d state:%d\n", motion, dark, blobX, state);
    lastDebugTime = millis();
  }

  // stable logic with cooldown (adjusted for smaller area/counts)
  // Increased dark threshold from 80 to 300 to avoid noise triggers
  if (motion > MOTION_THRESHOLD && dark > 300 && 
      millis() - lastCountTime > COOLDOWN_MS) {
    
    int newState = (blobX < LEFT_ZONE) ? 1 : 
                   (blobX > RIGHT_ZONE) ? 2 : state;
    
    // only count on state change   
    if (newState != state) {
      if (state == 1 && newState == 2) {  // LEFT to RIGHT = EXIT
        if (passengerCount > 0) passengerCount--;
        preferences.putInt("count", passengerCount); // Save to NVS
        sendMQTT("exit");
        Serial.printf("✅ EXIT   C:%d (x:%d→%d)\n", passengerCount, LEFT_ZONE, RIGHT_ZONE);
        
        // Red LED for Exit
        triggerRedLed();
        
      } else if (state == 2 && newState == 1) {  // RIGHT to LEFT = ENTER
        passengerCount++;
        preferences.putInt("count", passengerCount); // Save to NVS
        sendMQTT("enter");
        Serial.printf("✅ ENTER  C:%d (x:%d→%d)\n", passengerCount, RIGHT_ZONE, LEFT_ZONE);
        
        // Green LED for Enter
        triggerGreenLed();
      }
      state = newState;
      lastCountTime = millis();
    }
  }
  
  esp_camera_fb_return(fb);

  // --- MERGED: RSSI STATUS HEARTBEAT ---
  // Send status every 5 seconds if connected
  if (wifiConnected) {
    static unsigned long lastStatusTime = 0;
    if (millis() - lastStatusTime > 5000) {
      publishStatus();
      lastStatusTime = millis();
    }
  }

  delay(30);
}

void sendMQTT(String dir) {
  if (!wifiConnected) return;  // Skip MQTT if no WiFi
  char buf[80];
  snprintf(buf, 80, "{\"dir\":\"%s\",\"count\":%d,\"t\":%ld}", 
           dir.c_str(), passengerCount, millis()/1000);
  mqttClient.publish(mqtt_topic, buf);
}

// --- MERGED: PUBLISH STATUS FUNCTION ---
void publishStatus() {
  if (!mqttClient.connected()) return;
  
  long rssi = WiFi.RSSI();
  char buf[100];
  // Include count in status so server syncs it
  snprintf(buf, 100, "{\"rssi\":%ld, \"uptime\":%lu, \"count\":%d}", rssi, millis()/1000, passengerCount);
  
  // Topic: sut/bus/ESP32-CAM-01/status (from config.h)
  mqttClient.publish(MQTT_TOPIC_STATUS, buf);
}

void reconnectMQTT() {
  static unsigned long lastMqttAttempt = 0;
  if (millis() - lastMqttAttempt < 10000) return;
  lastMqttAttempt = millis();
  
  // Skip empty hosts
  while (strlen(mqttServers[currentMqttIndex].host) == 0) {
    currentMqttIndex = (currentMqttIndex + 1) % mqttServerCount;
  }
  
  Serial.printf("🔌 MQTT trying %d/%d: %s:%d\n", 
                currentMqttIndex + 1, mqttServerCount,
                mqttServers[currentMqttIndex].host, 
                mqttServers[currentMqttIndex].port);
  
  mqttClient.setServer(mqttServers[currentMqttIndex].host, 
                       mqttServers[currentMqttIndex].port);
  mqttClient.setCallback(mqttCallback);  // Set callback for incoming messages
  
  if (mqttClient.connect("BusCamStable")) {
    Serial.println("✅ MQTT Connected");
    // Subscribe to ring command topic
    mqttClient.subscribe(MQTT_TOPIC_RING);
    mqttClient.subscribe("sut/bus/+/ring");  // Also listen for bus-specific ring
    Serial.println("🔔 Subscribed to ring topics");
    
    // Subscribe to OTA topic
    #ifdef OTA_ENABLED
    mqttClient.subscribe(MQTT_TOPIC_OTA);
    Serial.printf("📥 Subscribed to OTA topic: %s\n", MQTT_TOPIC_OTA);
    Serial.printf("📌 Current firmware version: %s\n", FIRMWARE_VERSION);
    #endif
  } else {
    Serial.println("❌ MQTT Failed, trying next server");
    currentMqttIndex = (currentMqttIndex + 1) % mqttServerCount;
  }
}

// =============================================================================
// OTA (Over-The-Air) Update Functions
// =============================================================================

#ifdef OTA_ENABLED
void performOTA() {
  otaPending = false;  // Reset flag
  
  if (otaUrl.length() == 0) {
    Serial.println("❌ OTA URL is empty");
    return;
  }
  
  Serial.println("🔄 Starting OTA update...");
  Serial.printf("📥 Downloading: %s\n", otaUrl.c_str());
  
  // Blink LED rapidly to indicate OTA in progress
  for (int i = 0; i < 5; i++) {
    digitalWrite(DETECT_LED, HIGH);
    delay(100);
    digitalWrite(DETECT_LED, LOW);
    delay(100);
  }
  
  // Publish OTA status to MQTT
  char statusBuf[150];
  snprintf(statusBuf, sizeof(statusBuf), 
           "{\"status\":\"downloading\",\"version\":\"%s\",\"current\":\"%s\"}", 
           otaVersion.c_str(), FIRMWARE_VERSION);
  mqttClient.publish(MQTT_TOPIC_STATUS, statusBuf);
  
  // Keep LED on during download
  digitalWrite(DETECT_LED, HIGH);
  
  // Perform HTTP OTA update
  WiFiClient updateClient;
  httpUpdate.setLedPin(DETECT_LED, LOW);  // LED on during update
  httpUpdate.rebootOnUpdate(false);  // Don't auto-reboot, we'll do it manually
  
  t_httpUpdate_return ret = httpUpdate.update(updateClient, otaUrl);
  
  switch (ret) {
    case HTTP_UPDATE_FAILED:
      Serial.printf("❌ OTA Failed! Error (%d): %s\n", 
                    httpUpdate.getLastError(), 
                    httpUpdate.getLastErrorString().c_str());
      
      // Publish failure status
      snprintf(statusBuf, sizeof(statusBuf), 
               "{\"status\":\"failed\",\"error\":\"%s\",\"code\":%d}", 
               httpUpdate.getLastErrorString().c_str(),
               httpUpdate.getLastError());
      mqttClient.publish(MQTT_TOPIC_STATUS, statusBuf);
      
      // Blink LED to indicate failure
      for (int i = 0; i < 10; i++) {
        digitalWrite(DETECT_LED, HIGH);
        delay(50);
        digitalWrite(DETECT_LED, LOW);
        delay(50);
      }
      break;
      
    case HTTP_UPDATE_NO_UPDATES:
      Serial.println("ℹ️ No updates available");
      snprintf(statusBuf, sizeof(statusBuf), 
               "{\"status\":\"no_update\",\"version\":\"%s\"}", 
               FIRMWARE_VERSION);
      mqttClient.publish(MQTT_TOPIC_STATUS, statusBuf);
      digitalWrite(DETECT_LED, LOW);
      break;
      
    case HTTP_UPDATE_OK:
      Serial.println("✅ OTA Update successful! Rebooting...");
      
      // Publish success status
      snprintf(statusBuf, sizeof(statusBuf), 
               "{\"status\":\"success\",\"version\":\"%s\",\"rebooting\":true}", 
               otaVersion.c_str());
      mqttClient.publish(MQTT_TOPIC_STATUS, statusBuf);
      mqttClient.loop();  // Ensure message is sent
      
      // Keep LED on for 2 seconds before reboot
      digitalWrite(DETECT_LED, HIGH);
      delay(2000);
      
      // Reboot to apply new firmware
      ESP.restart();
      break;
  }
  
  // Clear OTA variables
  otaUrl = "";
  otaVersion = "";
}
#endif
