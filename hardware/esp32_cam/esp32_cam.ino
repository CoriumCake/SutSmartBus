#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiClientSecure.h> // For WSS
#include <PsychicMqttClient.h>
#include <HTTPUpdate.h>  // For HTTP-based OTA updates
#include <WebServer.h> // Add WebServer include
#include <Preferences.h> // INTERNAL STORAGE
#include "time.h"
#include "config.h"  // ⚠️ Create from config.h.example with your credentials

// Baltimore CyberTrust Root CA for Cloudflare WSS connections
const char* BALTIMORE_CYBERTRUST_ROOT_CA = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDzTCCArWgAwIBAgIQCjeHZF5ftIwiTv0b7RQMPDANBgkqhkiG9w0BAQsFADBa
MQswCQYDVQQGEwJJRTESMBAGA1UEChMJQmFsdGltb3JlMRMwEQYDVQQLEwpDeWJl
clRydXN0MSIwIAYgA1UEAxMZQmFsdGltb3JlIEN5YmVyVHJ1c3QgUm9vdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKMEyE0lTz+g/SJXQ7vTQ1unBuCJN0yJV0ReFEQPaA1IwQvZW+cwdFD1
9Ae8zFnWSfda9J1CZMRJCQUzym+5iPDuI9yP+kHyCREU3qzuWFloUwOxkgAyXVjB
YdwRVKD05WdRerw6DEdfgkfCv4+3ao8XnTSrLE=
-----END CERTIFICATE-----
)EOF";

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

// Tuning settings (loaded from preferences)
int LEFT_ZONE = 70;   
int RIGHT_ZONE = 90;  
int MOTION_THRESHOLD = 25; 
unsigned long COOLDOWN_MS = 2000;
int PIXEL_DARK_THRESHOLD = 90;
int DARK_PIXELS_THRESHOLD = 300;
int PIXEL_MOTION_THRESHOLD = 25;
bool INVERT_DIRECTION = false;
int ACTIVE_PROFILE = 0; // 0=Day, 1=Night

// Internal Storage (Preferences)
Preferences preferences;

void loadProfile(int profile) {
  String p = String(profile);
  PIXEL_DARK_THRESHOLD = preferences.getInt(("pdt"+p).c_str(), profile == 0 ? 90 : 50);
  DARK_PIXELS_THRESHOLD = preferences.getInt(("dpt"+p).c_str(), profile == 0 ? 300 : 80);
  PIXEL_MOTION_THRESHOLD = preferences.getInt(("pmt"+p).c_str(), profile == 0 ? 25 : 40);
  MOTION_THRESHOLD = preferences.getInt(("mt"+p).c_str(), profile == 0 ? 25 : 60);
  LEFT_ZONE = preferences.getInt(("lz"+p).c_str(), 70);
  RIGHT_ZONE = preferences.getInt(("rz"+p).c_str(), 90);
  COOLDOWN_MS = preferences.getInt(("cd"+p).c_str(), 2000);
  INVERT_DIRECTION = preferences.getBool(("inv"+p).c_str(), false);
}

void saveProfile(int profile) {
  String p = String(profile);
  preferences.putInt(("pdt"+p).c_str(), PIXEL_DARK_THRESHOLD);
  preferences.putInt(("dpt"+p).c_str(), DARK_PIXELS_THRESHOLD);
  preferences.putInt(("pmt"+p).c_str(), PIXEL_MOTION_THRESHOLD);
  preferences.putInt(("mt"+p).c_str(), MOTION_THRESHOLD);
  preferences.putInt(("lz"+p).c_str(), LEFT_ZONE);
  preferences.putInt(("rz"+p).c_str(), RIGHT_ZONE);
  preferences.putInt(("cd"+p).c_str(), COOLDOWN_MS);
  preferences.putBool(("inv"+p).c_str(), INVERT_DIRECTION);
  preferences.putInt("prof", ACTIVE_PROFILE);
}

// WiFi connection settings (non-blocking)
bool wifiConnected = false;
unsigned long lastWifiAttempt = 0;
const unsigned long WIFI_RETRY_INTERVAL = 10000;  // 1 minute
const unsigned long WIFI_CONNECT_TIMEOUT = 4000;  // 4s per network (non-blocking)
unsigned long wifiConnectStart = 0;
bool wifiConnecting = false;

WiFiClientSecure espClient; // Use WiFiClientSecure for WSS
PsychicMqttClient mqttClient;
int passengerCount = 0;
int state = 0;  // 0=none, 1=left, 2=right
unsigned long lastCountTime = 0;
uint8_t roiPrev[4800] = {0}; // 160 width * 30 height

WebServer server(80);

void handleRoot() {
  String html = "<html><head><title>SUT Bus Camera Calibration</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:Arial;text-align:center;margin:0;padding:20px;background:#222;color:#eee;}";
  html += "img{width:95%;max-width:800px;height:auto;border:2px solid #fff;image-rendering:pixelated;image-rendering:-moz-crisp-edges;}";
  html += "button{padding:10px 20px;font-size:16px;cursor:pointer;background:#007bff;color:white;border:none;border-radius:5px;margin-top:10px;width:100%;max-width:400px;}";
  html += ".control-group{margin: 10px auto; max-width: 400px; text-align: left; background: #333; padding: 15px; border-radius: 8px;}";
  html += "label{display:block; margin-bottom: 5px; font-weight: bold;}";
  html += "input[type=range]{width: 100%;}";
  html += ".val{float: right; color: #00ffcc;}";
  html += "</style>";
  html += "<script>";
  html += "function updateVal(id, val) { document.getElementById(id+'_val').innerText = val; }";
  html += "var saveTimer;";
  html += "function saveConfig() {";
  html += "  clearTimeout(saveTimer);";
  html += "  saveTimer = setTimeout(function() {";
  html += "    var pdt = document.getElementById('pdt').value;";
  html += "    var dpt = document.getElementById('dpt').value;";
  html += "    var mt = document.getElementById('mt').value;";
  html += "    var pmt = document.getElementById('pmt').value;";
  html += "    var lz = document.getElementById('lz').value;";
  html += "    var rz = document.getElementById('rz').value;";
  html += "    var cd = document.getElementById('cd').value;";
  html += "    var inv = document.getElementById('inv').checked ? 1 : 0;";
  html += "    var xhr = new XMLHttpRequest();";
  html += "    xhr.open('GET', '/update?pdt='+pdt+'&dpt='+dpt+'&mt='+mt+'&pmt='+pmt+'&lz='+lz+'&rz='+rz+'&cd='+cd+'&inv='+inv, true);";
  html += "    xhr.send();";
  html += "    var sts = document.getElementById('save_status'); if(sts) { sts.innerText = 'Settings Auto-Saved!'; setTimeout(function(){sts.innerText='';}, 2000); }";
  html += "  }, 100);";
  html += "}";
  html += "function resetDefaults() {";
  html += "  if (ACTIVE_PROFILE == 0) {";
  html += "    document.getElementById('pdt').value = 90; updateVal('pdt', 90);";
  html += "    document.getElementById('dpt').value = 300; updateVal('dpt', 300);";
  html += "    document.getElementById('pmt').value = 25; updateVal('pmt', 25);";
  html += "    document.getElementById('mt').value = 25; updateVal('mt', 25);";
  html += "  } else {";
  html += "    document.getElementById('pdt').value = 50; updateVal('pdt', 50);";
  html += "    document.getElementById('dpt').value = 80; updateVal('dpt', 80);";
  html += "    document.getElementById('pmt').value = 40; updateVal('pmt', 40);";
  html += "    document.getElementById('mt').value = 60; updateVal('mt', 60);";
  html += "  }";
  html += "  document.getElementById('lz').value = 70; updateVal('lz', 70);";
  html += "  document.getElementById('rz').value = 90; updateVal('rz', 90);";
  html += "  document.getElementById('cd').value = 2000; updateVal('cd', 2000);";
  html += "  saveConfig();";
  html += "}";
  html += "function permanentSave() {";
  html += "  saveConfig();";
  html += "  var sts = document.getElementById('save_status'); if(sts) { sts.innerText = 'Profile Permanently Saved!'; setTimeout(function(){sts.innerText='';}, 2000); }";
  html += "}";
  html += "</script>";
  html += "</head><body>";
  html += "<h1>Bus Camera Calibration</h1>";
  html += "<div style='margin-bottom: 15px;'>";
  html += "<button onclick='window.location=\"/switch?p=0\"' style='background:";
  html += (ACTIVE_PROFILE==0?"#4CAF50":"#555");
  html += "; width:48%; padding: 15px; margin:0 2px;'>☀️ Day Profile</button>";
  html += "<button onclick='window.location=\"/switch?p=1\"' style='background:";
  html += (ACTIVE_PROFILE==1?"#2196F3":"#555");
  html += "; width:48%; padding: 15px; margin:0 2px;'>🌙 Night Profile</button>";
  html += "</div>";
  html += "<h2>Total Passengers: <span id='pcount' style='color:#ffeb3b;'>"+String(passengerCount)+"</span></h2>";
  html += "<div><img src='/capture' id='cam' onload='setTimeout(refresh, 500)'></div>";
  html += "<br><p>Refreshes automatically for positioning. <a href='/capture' target='_blank'>Snapshot</a></p>";
  
  html += "<div class='control-group'><label title='Grayscale value (0-255) below which a pixel is considered part of a passenger (dark)'>Pixel Darkness Threshold (0-255) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='pdt_val'>"+String(PIXEL_DARK_THRESHOLD)+"</span></label>";
  html += "<input type='range' id='pdt' min='0' max='255' value='"+String(PIXEL_DARK_THRESHOLD)+"' oninput='updateVal(\"pdt\", this.value); saveConfig();'></div>";

  html += "<div class='control-group'><label title='How many total dark pixels must exist in the frame to count as a passenger mass (Lower if room is bright/target is small)'>Required Dark Pixels (0-4800) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='dpt_val'>"+String(DARK_PIXELS_THRESHOLD)+"</span></label>";
  html += "<input type='range' id='dpt' min='0' max='4800' step='10' value='"+String(DARK_PIXELS_THRESHOLD)+"' oninput='updateVal(\"dpt\", this.value); saveConfig();'></div>";
  
  html += "<div class='control-group'><label title='How much a pixel must change in brightness from the last frame to be considered in motion'>Pixel Motion Diff (>X) (0-255) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='pmt_val'>"+String(PIXEL_MOTION_THRESHOLD)+"</span></label>";
  html += "<input type='range' id='pmt' min='0' max='255' value='"+String(PIXEL_MOTION_THRESHOLD)+"' oninput='updateVal(\"pmt\", this.value); saveConfig();'></div>";

  html += "<div class='control-group'><label title='Total number of changed pixels required to trigger motion tracking logic'>Total Motion Pixels (0-4800) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='mt_val'>"+String(MOTION_THRESHOLD)+"</span></label>";
  html += "<input type='range' id='mt' min='0' max='4800' step='10' value='"+String(MOTION_THRESHOLD)+"' oninput='updateVal(\"mt\", this.value); saveConfig();'></div>";

  html += "<div class='control-group'><label title='Horizontal threshold for entering. Blob must move left of this line. (160=Right edge, 0=Left edge)'>Left Zone (X coord) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='lz_val'>"+String(LEFT_ZONE)+"</span></label>";
  html += "<input type='range' id='lz' min='0' max='160' value='"+String(LEFT_ZONE)+"' oninput='updateVal(\"lz\", this.value); saveConfig();'></div>";

  html += "<div class='control-group'><label title='Horizontal threshold for exiting. Blob must move right of this line. (160=Right edge, 0=Left edge)'>Right Zone (X coord) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='rz_val'>"+String(RIGHT_ZONE)+"</span></label>";
  html += "<input type='range' id='rz' min='0' max='160' value='"+String(RIGHT_ZONE)+"' oninput='updateVal(\"rz\", this.value); saveConfig();'></div>";

  html += "<div class='control-group'><label title='Minimum time to wait after counting a passenger before allowing another count'>Cooldown (ms) <span style='cursor:help; color:#aaa; font-weight:normal; font-size:12px;'>[?]</span> <span class='val' id='cd_val'>"+String(COOLDOWN_MS)+"</span></label>";
  html += "<input type='range' id='cd' min='0' max='10000' step='100' value='"+String(COOLDOWN_MS)+"' oninput='updateVal(\"cd\", this.value); saveConfig();'></div>";

  html += "<div class='control-group' style='text-align:center;'><label title='Swap Left and Right zones for entering/exiting based on camera mount orientation.' style='display:inline-block; font-size:18px;'>Invert Direction <span style='cursor:help; color:#aaa; font-weight:normal; font-size:14px;'>[?]</span></label>";
  html += "<input type='checkbox' id='inv' style='width:25px; height:25px; vertical-align:middle; margin-left:10px;' "+String(INVERT_DIRECTION ? "checked" : "")+" onchange='saveConfig()'></div>";

  html += "<button onclick='permanentSave()' style='background:#008CBA; margin-bottom: 10px; padding:15px; font-weight:bold;'>💾 Save "+String(ACTIVE_PROFILE==0?"Day":"Night")+" Profile</button><br>";
  html += "<button onclick='resetDefaults()' style='background:#f44336; margin-bottom: 20px;'>Reset to Factory Defaults</button>";

  html += "<div id='save_status' style='color:#00ffcc; font-weight:bold; height:20px; margin-top:5px;'></div>";
  html += "<script>var ACTIVE_PROFILE = "+String(ACTIVE_PROFILE)+";</script>";
  html += "<script>function refresh(){ document.getElementById('cam').src = '/capture?t=' + new Date().getTime(); }</script>";
  html += "<script>setInterval(function(){ var x = new XMLHttpRequest(); x.onreadystatechange=function(){ if(x.readyState==4&&x.status==200){ document.getElementById('pcount').innerText=x.responseText; } }; x.open('GET','/count',true); x.send(); }, 1000);</script>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

void handleCount() {
  server.send(200, "text/plain", String(passengerCount));
}

void handleUpdate() {
  if (server.hasArg("pdt")) PIXEL_DARK_THRESHOLD = server.arg("pdt").toInt();
  if (server.hasArg("dpt")) DARK_PIXELS_THRESHOLD = server.arg("dpt").toInt();
  if (server.hasArg("mt")) MOTION_THRESHOLD = server.arg("mt").toInt();
  if (server.hasArg("pmt")) PIXEL_MOTION_THRESHOLD = server.arg("pmt").toInt();
  if (server.hasArg("lz")) LEFT_ZONE = server.arg("lz").toInt();
  if (server.hasArg("rz")) RIGHT_ZONE = server.arg("rz").toInt();
  if (server.hasArg("cd")) COOLDOWN_MS = server.arg("cd").toInt();
  if (server.hasArg("inv")) INVERT_DIRECTION = (server.arg("inv") == "1");

  // Save via new global schema
  saveProfile(ACTIVE_PROFILE);
  
  server.send(200, "text/plain", "OK");
}

void handleSwitch() {
  if (server.hasArg("p")) {
    ACTIVE_PROFILE = server.arg("p").toInt();
    loadProfile(ACTIVE_PROFILE);
  }
  // Redirect back to root
  server.sendHeader("Location", "/");
  server.send(303);
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

    size_t width = fb->width;
    size_t height = fb->height;
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

void performOTA();
void handleWiFiConnection();
void tryConnectWiFi();
void reconnectMQTT();
void publishStatus();
void sendMQTT(String dir);

// MQTT callback for receiving commands
void mqttCallback(char* topic, char* payload, int qos, int retain, bool dup) {
  String message = String(payload);
  Serial.printf("📨 MQTT [%s]: %s\n", topic, message.c_str());
  
  // Check for ring command
  if (String(topic).indexOf("ring") >= 0) {
    ringBell();
  }
  
  // Check for OTA update command
  #ifdef OTA_ENABLED
  if (String(topic).indexOf("ota") >= 0) {
    // Parse JSON to get URL and version
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
        otaPending = true;
      }
    }
  }
  #endif
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("🚌 STABLE Bus Counter v1.2 (WSS Mode)");
  
  // Initialize pins
  pinMode(LED_RED_PIN, OUTPUT);
  digitalWrite(LED_RED_PIN, LOW);
  pinMode(LED_GREEN_PIN, OUTPUT);
  digitalWrite(LED_GREEN_PIN, LOW);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // Camera config
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
  config.pixel_format = PIXFORMAT_GRAYSCALE;
  config.frame_size = FRAMESIZE_QVGA; // Use QVGA (320x240) to avoid OV2640 144x120 corruption bug
  config.jpeg_quality = 12;
  config.fb_count = 1;

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("❌ Camera Init Failed");
    while(1);
  }

  // Fetch the sensor to correct orientation
  sensor_t * s = esp_camera_sensor_get();
  if (s) {
    s->set_vflip(s, 1);    // Rotate vertically (upside down fix)
    s->set_hmirror(s, 1);  // Rotate horizontally (fix mirroring from vflip)
  }

  // MQTT Callback Setup
  mqttClient.onMessage(mqttCallback);
  mqttClient.onConnect([](bool sessionPresent) {
    Serial.println("✅ MQTT Connected (WSS)");
    mqttClient.subscribe(MQTT_TOPIC_RING, 1);
    mqttClient.subscribe("sut/bus/+/ring", 1);
    #ifdef OTA_ENABLED
    mqttClient.subscribe(MQTT_TOPIC_OTA, 1);
    #endif
  });

  // NVS Storage Init
  preferences.begin("bus-data", false);
  passengerCount = preferences.getInt("count", 0);
  
  ACTIVE_PROFILE = preferences.getInt("prof", 0);
  loadProfile(ACTIVE_PROFILE);
  
  // WiFi Init
  WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
  
  // Calibration Server
  server.on("/", handleRoot);
  server.on("/update", handleUpdate);
  server.on("/switch", handleSwitch);
  server.on("/count", handleCount);
  server.on("/capture", handleCapture);
  server.begin();
}

void loop() {
  handleLeds();
  handleWiFiConnection();
  server.handleClient();

  if (wifiConnected) {
    if (!mqttClient.connected()) reconnectMQTT();
    #ifdef OTA_ENABLED
    if (otaPending) performOTA();
    #endif
  }

  camera_fb_t * fb = esp_camera_fb_get();
  if (!fb) return;

  // ... (Detection logic remains same) ...
  // Handle larger resolutions by processing a scaled-down grid
  int motion = 0, dark = 0, blobX = 0;
  int roiIdx = 0;
  
  // To simulate 160x120 from 320x240, step size is 2
  int stepX = (fb->width == 320) ? 2 : 1;
  int stepY = (fb->height == 240) ? 2 : 1;
  
  // Focus on the center/lower half of the door (y=40 to y=70 when unscaled)
  int startY = 40 * stepY;
  int endY = 70 * stepY;
  
  for (int y = startY; y < endY; y += stepY) {
    for (int x = 0; x < fb->width; x += stepX) {
      if (roiIdx >= 4800) break; // Buffer overflow protection
      
      int idx = y * fb->width + x;
      uint8_t p = fb->buf[idx];
      
      int diff = abs((int)p - (int)roiPrev[roiIdx]);
      if (diff > PIXEL_MOTION_THRESHOLD) motion++; // Threshold for motion
      
      // Look for the passengers (dark blobs in grayscale, adjust threshold if needed)
      if (p < PIXEL_DARK_THRESHOLD) { 
        dark++; 
        blobX += (x / stepX); // Normalize x back to 0-160 scale for evaluation
      }
      
      roiPrev[roiIdx++] = p;
    }
  }
  
  blobX /= max(1, dark);

  static unsigned long lastDebugTime = 0;
  if (millis() - lastDebugTime > 1500) {
    Serial.printf("📊 [DEBUG] motion: %d (needs > %d), dark: %d (needs > %d), blobX: %d, state: %d\n", 
                  motion, MOTION_THRESHOLD, dark, DARK_PIXELS_THRESHOLD, blobX, state);
    lastDebugTime = millis();
  }

  if (motion > MOTION_THRESHOLD && dark > DARK_PIXELS_THRESHOLD && millis() - lastCountTime > COOLDOWN_MS) {
    int newState = (blobX < LEFT_ZONE) ? 1 : (blobX > RIGHT_ZONE) ? 2 : state;
    if (newState != state) {
      if (state == 1 && newState == 2) {
        // Moved from left to right
        if (INVERT_DIRECTION) {
            passengerCount++;
            sendMQTT("enter");
            triggerGreenLed();
        } else {
            if (passengerCount > 0) passengerCount--;
            sendMQTT("exit");
            triggerRedLed();
        }
        preferences.putInt("count", passengerCount);
      } else if (state == 2 && newState == 1) {
        // Moved from right to left
        if (INVERT_DIRECTION) {
            if (passengerCount > 0) passengerCount--;
            sendMQTT("exit");
            triggerRedLed();
        } else {
            passengerCount++;
            sendMQTT("enter");
            triggerGreenLed();
        }
        preferences.putInt("count", passengerCount);
      }
      state = newState;
      lastCountTime = millis();
    }
  }
  esp_camera_fb_return(fb);

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
  Serial.printf("🚀 DETECTED: %s! Passenger count: %d\n", dir.c_str(), passengerCount);
  if (!mqttClient.connected()) return;
  char buf[80];
  snprintf(buf, 80, "{\"dir\":\"%s\",\"count\":%d,\"t\":%ld}", 
           dir.c_str(), passengerCount, millis()/1000);
  mqttClient.publish(mqtt_topic, 1, false, buf);
}

void publishStatus() {
  if (!mqttClient.connected()) return;
  long rssi = WiFi.RSSI();
  Serial.printf("📡 Status -> RSSI: %ld, Count: %d\n", rssi, passengerCount);
  char buf[100];
  snprintf(buf, 100, "{\"rssi\":%ld, \"uptime\":%lu, \"count\":%d}", rssi, millis()/1000, passengerCount);
  mqttClient.publish(MQTT_TOPIC_STATUS, 1, false, buf);
}

void reconnectMQTT() {
  static unsigned long lastMqttAttempt = 0;
  if (millis() - lastMqttAttempt < 5000) return;
  lastMqttAttempt = millis();

  const char* mqttHost = mqttServers[currentMqttIndex].host;
  if (strlen(mqttHost) == 0) {
    currentMqttIndex = (currentMqttIndex + 1) % mqttServerCount;
    lastMqttAttempt = millis() - 5000; // retry immediately
    return;
  }

  // Build wss:// URI for PsychicMqttClient
  char uri[128];
  snprintf(uri, sizeof(uri), "wss://%s:443/mqtt", mqttHost);
  
  Serial.printf("🔌 MQTT trying: %s\n", uri);

  mqttClient.setServer(uri);
  mqttClient.setClientId(MQTT_CLIENT_ID);
  mqttClient.attachArduinoCACertBundle(true);
  mqttClient.connect(); 
  // Note: connect() is void, status handled by onConnect callback
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
  mqttClient.publish(MQTT_TOPIC_STATUS, 1, false, statusBuf);
  
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
      mqttClient.publish(MQTT_TOPIC_STATUS, 1, false, statusBuf);
      
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
      mqttClient.publish(MQTT_TOPIC_STATUS, 1, false, statusBuf);
      digitalWrite(DETECT_LED, LOW);
      break;
      
    case HTTP_UPDATE_OK:
      Serial.println("✅ OTA Update successful! Rebooting...");
      
      // Publish success status
      snprintf(statusBuf, sizeof(statusBuf), 
               "{\"status\":\"success\",\"version\":\"%s\",\"rebooting\":true}", 
               otaVersion.c_str());
      mqttClient.publish(MQTT_TOPIC_STATUS, 1, false, statusBuf);
      
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

void tryConnectWiFi() {
  if (wifiNetworkCount == 0) return;
  wifiConnecting = true;
  wifiConnectStart = millis();
  
  const char* ssid = wifiNetworks[currentWifiIndex].ssid;
  const char* password = wifiNetworks[currentWifiIndex].password;
  
  Serial.printf("📡 Connecting to WiFi: %s\n", ssid);
  WiFi.disconnect();
  WiFi.begin(ssid, password);
  lastWifiAttempt = millis();
}

// Handle non-blocking WiFi connection
void handleWiFiConnection() {
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
