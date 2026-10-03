/*
 * uno_vehicle_input - Arduino UNO vehicle-input module for the BBB vehicle hub.
 *
 * Emits ONE text line every ~100 ms at 115200 baud 8N1 in the format documented in
 * docs/serial_vehicle_input_protocol.md (every field on every line):
 *
 *   left=0,right=0,high_beam=0,brake=0,oil=0,charge=0,door=0,a0=512,a1=430,speed_hz=48.2,rpm_hz=37.5
 *
 * The UNO sends RAW values only. The hub converts a0/a1 counts and speed_hz/rpm_hz with
 * tools/bbb_hub/config/sensor_calibration.json (VEHICLE_SENSOR_CALIBRATION).
 *
 * Pins (proposal - differs from the legacy pinmap because D2/D3 must carry the pulse inputs):
 *   D2 speed pulse (INT0)   D3 rpm pulse (INT1)
 *   D4 high_beam  D5 brake  D6 oil  D7 charge  D8 door  D9 left  D10 right
 *   A0 fuel sender (raw)    A1 coolant sender (raw)
 * Digital lamp inputs are expected to come from optocouplers (never 12 V straight onto a pin).
 *
 * NOT run on hardware yet. Compile-only checked with arduino-cli (see README.md).
 *
 * Build-time options (-D on the arduino-cli command line, or edit below):
 *   BENCH_SIM=1          ignore A0/A1/D2/D3 and send stepped synthetic values (bench use only)
 *   INPUT_ACTIVE_LOW=0   lamp inputs active-high (default 1: optocoupler output pulls the pin low)
 *   PULSE_EDGE=RISING    count rising edges instead of FALLING (default FALLING)
 */

#ifndef BENCH_SIM
#define BENCH_SIM 0
#endif
#ifndef INPUT_ACTIVE_LOW
#define INPUT_ACTIVE_LOW 1
#endif
#ifndef PULSE_EDGE
#define PULSE_EDGE FALLING
#endif

static const unsigned long BAUD = 115200UL;
static const unsigned long PRINT_PERIOD_MS = 100;   // one line per ~100 ms (10 Hz)
static const unsigned long WINDOW_MS = 200;         // pulse-frequency window (100-250 ms)
static const unsigned long MIN_PULSE_GAP_US = 100;  // ignore edges closer than this (glitch/bounce filter, max ~10 kHz)

static const uint8_t PIN_SPEED = 2;
static const uint8_t PIN_RPM = 3;
static const uint8_t PIN_HIGH_BEAM = 4;
static const uint8_t PIN_BRAKE = 5;
static const uint8_t PIN_OIL = 6;
static const uint8_t PIN_CHARGE = 7;
static const uint8_t PIN_DOOR = 8;
static const uint8_t PIN_LEFT = 9;
static const uint8_t PIN_RIGHT = 10;

// ---- pulse counting (ISR) -------------------------------------------------
volatile unsigned long speedCount = 0;
volatile unsigned long rpmCount = 0;
volatile unsigned long speedLastUs = 0;
volatile unsigned long rpmLastUs = 0;

void onSpeedPulse() {
  unsigned long now = micros();
  if (now - speedLastUs >= MIN_PULSE_GAP_US) {
    speedCount++;
    speedLastUs = now;
  }
}

void onRpmPulse() {
  unsigned long now = micros();
  if (now - rpmLastUs >= MIN_PULSE_GAP_US) {
    rpmCount++;
    rpmLastUs = now;
  }
}

float speedHz = 0.0f;
float rpmHz = 0.0f;
unsigned long windowStartUs = 0;
unsigned long lastPrintMs = 0;

// Close the current window and compute Hz. Called from loop() once WINDOW_MS has elapsed.
void closeWindow(unsigned long nowUs) {
  noInterrupts();
  unsigned long s = speedCount;
  unsigned long r = rpmCount;
  speedCount = 0;
  rpmCount = 0;
  interrupts();
  unsigned long elapsedUs = nowUs - windowStartUs;
  windowStartUs = nowUs;
  if (elapsedUs == 0) return;
  speedHz = (float)s * 1000000.0f / (float)elapsedUs;
  rpmHz = (float)r * 1000000.0f / (float)elapsedUs;
}

// ---- helpers -----------------------------------------------------------------
int lamp(uint8_t pin) {
  int level = digitalRead(pin);
#if INPUT_ACTIVE_LOW
  return level == LOW ? 1 : 0;
#else
  return level == HIGH ? 1 : 0;
#endif
}

#if BENCH_SIM
// Stepped synthetic values, each held BENCH_STEP_MS. a0 raw = round(V / 5 * 1023) for
// V = 0, 1.25, 2.5, 3.75, 5 V -> 0, 256, 512, 767, 1023. a1 steps the other way round, rpm_hz reversed
// so the four fields are distinguishable on the hub.
static const unsigned long BENCH_STEP_MS = 5000;
static const int BENCH_STEPS = 5;
static const int BENCH_A0[BENCH_STEPS] = {0, 256, 512, 767, 1023};
static const int BENCH_A1[BENCH_STEPS] = {1023, 767, 512, 256, 0};
static const float BENCH_SPEED_HZ[BENCH_STEPS] = {0.0f, 10.0f, 50.0f, 100.0f, 200.0f};
static const float BENCH_RPM_HZ[BENCH_STEPS] = {200.0f, 100.0f, 50.0f, 10.0f, 0.0f};
#endif

void setup() {
  Serial.begin(BAUD);
  const uint8_t lampMode = INPUT_ACTIVE_LOW ? INPUT_PULLUP : INPUT;
  pinMode(PIN_HIGH_BEAM, lampMode);
  pinMode(PIN_BRAKE, lampMode);
  pinMode(PIN_OIL, lampMode);
  pinMode(PIN_CHARGE, lampMode);
  pinMode(PIN_DOOR, lampMode);
  pinMode(PIN_LEFT, lampMode);
  pinMode(PIN_RIGHT, lampMode);
  pinMode(PIN_SPEED, INPUT_PULLUP);  // optocoupler/open-collector output; a driven 5 V source also works
  pinMode(PIN_RPM, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_SPEED), onSpeedPulse, PULSE_EDGE);
  attachInterrupt(digitalPinToInterrupt(PIN_RPM), onRpmPulse, PULSE_EDGE);
  windowStartUs = micros();
  lastPrintMs = millis();
}

void loop() {
  unsigned long nowUs = micros();
  if (nowUs - windowStartUs >= WINDOW_MS * 1000UL) {
    closeWindow(nowUs);
  }

  unsigned long nowMs = millis();
  if (nowMs - lastPrintMs < PRINT_PERIOD_MS) return;
  lastPrintMs += PRINT_PERIOD_MS;
  if (nowMs - lastPrintMs >= PRINT_PERIOD_MS) lastPrintMs = nowMs;  // fell behind: do not burst

  int a0, a1;
  float sHz, rHz;
#if BENCH_SIM
  int step = (int)((nowMs / BENCH_STEP_MS) % BENCH_STEPS);
  a0 = BENCH_A0[step];
  a1 = BENCH_A1[step];
  sHz = BENCH_SPEED_HZ[step];
  rHz = BENCH_RPM_HZ[step];
#else
  a0 = analogRead(A0);
  a1 = analogRead(A1);
  sHz = speedHz;
  rHz = rpmHz;
#endif

  Serial.print(F("left="));       Serial.print(lamp(PIN_LEFT));
  Serial.print(F(",right="));     Serial.print(lamp(PIN_RIGHT));
  Serial.print(F(",high_beam=")); Serial.print(lamp(PIN_HIGH_BEAM));
  Serial.print(F(",brake="));     Serial.print(lamp(PIN_BRAKE));
  Serial.print(F(",oil="));       Serial.print(lamp(PIN_OIL));
  Serial.print(F(",charge="));    Serial.print(lamp(PIN_CHARGE));
  Serial.print(F(",door="));      Serial.print(lamp(PIN_DOOR));
  Serial.print(F(",a0="));        Serial.print(a0);
  Serial.print(F(",a1="));        Serial.print(a1);
  Serial.print(F(",speed_hz="));  Serial.print(sHz, 1);
  Serial.print(F(",rpm_hz="));    Serial.print(rHz, 1);
  Serial.print('\n');
}
