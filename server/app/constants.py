# Topics
TOPIC_ESP32_GPS = "sut/bus/gps"
TOPIC_ESP32_GPS_FAST = "sut/bus/gps/fast"
TOPIC_APP_LOCATION = "sut/app/bus/location"
TOPIC_IR_TRIGGER = "sut/bus/ir/triggered"
TOPIC_BUS_DOOR_COUNT = "bus/door/count"
TOPIC_BUS_STATUS = "sut/bus/+/status"
TOPIC_RING = "sut/bus/ring"
TOPIC_OTA_ESP32_CAM = "sut/ota/esp32_cam"
TOPIC_OTA_PM = "sut/ota/pm"

# App Compatibility
TOPIC_PERSON_DETECTION = "sut/person-detection"

# Bus Config
TOTAL_SEATS = 33
BUS_MAC_MOCK = "DEBUG-MAC-01"

# Bus-Route Mapping
BUS_ROUTE_MAPPING = {
    "version": 1,
    "lastUpdated": "2025-12-19T09:00:00+07:00",
    "mappings": [
        {
            "bus_mac": "28:56:2F:49:F7:00",
            "bus_name": "SUT-BUS-01",
            "route_id": "route_1765852937753_9hdm9wd76",
            "route_name": "Red routes"
        }
    ],
    "routes": [
        {
            "route_id": "route_1765852937753_9hdm9wd76",
            "route_name": "Red routes",
            "route_color": "#e11d48",
            "file": "red_routes.json"
        }
    ]
}

ROUTES_DIR = "routes"
