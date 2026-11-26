# Heat logger

Arduino Nano logger that records the temperature a stored AED would see. It feeds the heat model in `storage/` with measured inside and outside temperatures instead of weather data alone.

## Parts

- Arduino Nano
- 2 x DS18B20 waterproof probes (probe 0 inside the car or cabinet, probe 1 outside in shade) with one 4.7 kohm pull-up from D2 to 5 V
- DS3231 real-time clock (SDA to A4, SCL to A5)
- microSD card module (CS D10, MOSI D11, MISO D12, SCK D13)
- USB power bank, kept outside the car

Wiring and placement are shown in `wiring_and_placement.png`.

## Use

1. Install the OneWire, DallasTemperature and RTClib (Adafruit) libraries from the Arduino IDE Library Manager.
2. Upload `heat_logger.ino`. The clock is set from the laptop time on the first upload.
3. The logger writes `temps.csv` (datetime, inside_C, outside_C) every 5 minutes.
4. Run 3 days in a closed car, then 3 days in a closed cabinet. Record car colour, sun or shade parking and cabinet type, and photograph each setup.

Status: code written, not yet built or tested on hardware.
