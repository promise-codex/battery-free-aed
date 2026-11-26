// Heat logger for the defibrillator study.
// Logs two DS18B20 probes (probe 0 = inside car or cabinet, probe 1 = outside in shade)
// every 5 minutes to temps.csv on a microSD card, with time from a DS3231 clock.
// Wiring (Arduino Nano):
//   DS18B20 probes: red -> 5V, black -> GND, yellow -> D2, plus one 4.7k resistor from D2 to 5V.
//   DS3231 RTC:     VCC -> 5V, GND -> GND, SDA -> A4, SCL -> A5.
//   microSD module: VCC -> 5V, GND -> GND, MOSI -> D11, MISO -> D12, SCK -> D13, CS -> D10.
// Libraries (Arduino IDE > Library Manager): OneWire, DallasTemperature, RTClib (Adafruit).

#include <OneWire.h>
#include <DallasTemperature.h>
#include <RTClib.h>
#include <SPI.h>
#include <SD.h>

const uint8_t ONE_WIRE_PIN = 2;
const uint8_t SD_CS = 10;
const unsigned long LOG_EVERY_MS = 300000UL;   // 5 minutes

OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature probes(&oneWire);
RTC_DS3231 rtc;
unsigned long lastLog = 0;

void setup() {
  Serial.begin(9600);
  probes.begin();
  probes.setResolution(12);                     // 0.0625 C steps
  if (!rtc.begin()) { Serial.println("RTC not found"); while (1); }
  if (rtc.lostPower()) rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));  // set clock once from the laptop
  if (!SD.begin(SD_CS)) { Serial.println("SD card not found"); while (1); }
  File f = SD.open("temps.csv", FILE_WRITE);
  if (f) { f.println("datetime,inside_C,outside_C"); f.close(); }
  Serial.print("Probes found: "); Serial.println(probes.getDeviceCount());
  lastLog = millis() - LOG_EVERY_MS;            // log immediately on start
}

void loop() {
  if (millis() - lastLog >= LOG_EVERY_MS) {
    lastLog = millis();
    probes.requestTemperatures();
    float tIn  = probes.getTempCByIndex(0);
    float tOut = probes.getTempCByIndex(1);
    DateTime now = rtc.now();
    char ts[20];
    sprintf(ts, "%04d-%02d-%02d %02d:%02d:%02d", now.year(), now.month(), now.day(),
            now.hour(), now.minute(), now.second());
    File f = SD.open("temps.csv", FILE_WRITE);
    if (f) {
      f.print(ts); f.print(','); f.print(tIn, 2); f.print(','); f.println(tOut, 2);
      f.close();
    }
    Serial.print(ts); Serial.print("  in "); Serial.print(tIn); Serial.print("  out "); Serial.println(tOut);
  }
}
