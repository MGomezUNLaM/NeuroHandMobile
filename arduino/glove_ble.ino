/*
 * glove_ble.ino — Lectura multi-sensor del guante háptico y envío por BLE (HM-10)
 *
 * Lee los 5 sensores de flexión de los dedos, el sensor de presión (FSR)
 * y la orientación IMU (Pitch y Roll), emitiendo la trama estructurada:
 * 
 * Formato de envío: 
 *   "pulgar:XX,indice:XX,medio:XX,anular:XX,menique:XX,pitch:XX,roll:XX,presion:XX\n"
 * 
 * Frecuencia: 20 Hz (cada 50ms)
 *
 * Conexiones sugeridas:
 *   - Sensores Flex: A0 (Pulgar), A1 (Índice), A2 (Medio), A3 (Anular), A4 (Meñique)
 *   - Sensor FSR (Presión): A5
 *   - HM-10 TX -> Arduino pin 10 (RX del SoftwareSerial)
 *   - HM-10 RX -> Arduino pin 11 (TX del SoftwareSerial)
 *   - IMU MPU6050 (opcional por I2C): SDA -> A4/SDA, SCL -> A5/SCL
 */

#include <SoftwareSerial.h>
#include <Wire.h>

// ============================================================
// CONFIGURACIÓN DE PINES
// ============================================================
const int PIN_FLEX_PULGAR  = A0;
const int PIN_FLEX_INDICE  = A1;
const int PIN_FLEX_MEDIO   = A2;
const int PIN_FLEX_ANULAR  = A3;
const int PIN_FLEX_MENIQUE = A4;
const int PIN_FSR_PRESION  = A5;

const int PIN_BLE_RX = 10;    // RX del SoftwareSerial (conectar a TX del HM-10)
const int PIN_BLE_TX = 11;    // TX del SoftwareSerial (conectar a RX del HM-10)

// ============================================================
// CONSTANTES DE CALIBRACIÓN (0% recto, 100% doblado)
// ============================================================
const int CALIB_MIN[5] = { 200, 200, 200, 200, 200 };
const int CALIB_MAX[5] = { 800, 800, 800, 800, 800 };

const int FSR_MIN = 50;
const int FSR_MAX = 900;

// ============================================================
// TIMING (40 Hz = menor delay de respuesta)
// ============================================================
const unsigned long INTERVALO_ENVIO_MS = 25;  // 25ms = 40 Hz de actualización
unsigned long ultimoEnvio = 0;

SoftwareSerial bleSerial(PIN_BLE_RX, PIN_BLE_TX);

void setup() {
  Serial.begin(9600);
  bleSerial.begin(9600);
  
  pinMode(PIN_FLEX_PULGAR, INPUT);
  pinMode(PIN_FLEX_INDICE, INPUT);
  pinMode(PIN_FLEX_MEDIO, INPUT);
  pinMode(PIN_FLEX_ANULAR, INPUT);
  pinMode(PIN_FLEX_MENIQUE, INPUT);
  pinMode(PIN_FSR_PRESION, INPUT);

  Serial.println("=== Guante Multi-Sensor BLE Inicializado ===");
}

int leerPorcentajeFlex(int pin, int minVal, int maxVal) {
  int raw = analogRead(pin);
  int pct = map(raw, minVal, maxVal, 0, 100);
  return constrain(pct, 0, 100);
}

void loop() {
  unsigned long ahora = millis();

  if (ahora - ultimoEnvio >= INTERVALO_ENVIO_MS) {
    ultimoEnvio = ahora;

    // 1. Leer sensores de flexión
    int valPulgar  = leerPorcentajeFlex(PIN_FLEX_PULGAR,  CALIB_MIN[0], CALIB_MAX[0]);
    int valIndice  = leerPorcentajeFlex(PIN_FLEX_INDICE,  CALIB_MIN[1], CALIB_MAX[1]);
    int valMedio   = leerPorcentajeFlex(PIN_FLEX_MEDIO,   CALIB_MIN[2], CALIB_MAX[2]);
    int valAnular  = leerPorcentajeFlex(PIN_FLEX_ANULAR,  CALIB_MIN[3], CALIB_MAX[3]);
    int valMenique = leerPorcentajeFlex(PIN_FLEX_MENIQUE, CALIB_MIN[4], CALIB_MAX[4]);

    // 2. Leer sensor FSR
    int rawFSR = analogRead(PIN_FSR_PRESION);
    int valPresion = constrain(map(rawFSR, FSR_MIN, FSR_MAX, 0, 100), 0, 100);

    // 3. Orientación IMU (Pitch y Roll en grados)
    // Nota: Si usas MPU6050, calcular los ángulos aquí. Por defecto 0 si no está conectado.
    int valPitch = 0;
    int valRoll = 0;

    // 4. Armar y transmitir trama completa
    String trama = "pulgar:" + String(valPulgar) + 
                   ",indice:" + String(valIndice) + 
                   ",medio:" + String(valMedio) + 
                   ",anular:" + String(valAnular) + 
                   ",menique:" + String(valMenique) + 
                   ",pitch:" + String(valPitch) + 
                   ",roll:" + String(valRoll) + 
                   ",presion:" + String(valPresion);

    // Enviar por BLE al teléfono
    bleSerial.println(trama);

    // Salida serie para depuración en PC
    Serial.println(trama);
  }
}
