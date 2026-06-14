/*
 * glove_ble.ino — Lectura de sensor flex y envío por BLE (HM-10)
 *
 * Este sketch lee un sensor flex conectado al pin analógico A0,
 * suaviza la lectura con un promedio móvil de 5 muestras,
 * mapea el valor a un porcentaje (0-100%) y lo envía por
 * Serial al módulo HM-10 que lo retransmite por BLE.
 *
 * Formato de envío: "FLEX:XX\n"
 * Frecuencia: 20 Hz (cada 50ms)
 *
 * Conexiones:
 *   - Sensor flex: A0 (con divisor de voltaje)
 *   - HM-10 TX -> Arduino pin 10 (RX del SoftwareSerial)
 *   - HM-10 RX -> Arduino pin 11 (TX del SoftwareSerial)
 *   - HM-10 VCC -> 3.3V
 *   - HM-10 GND -> GND
 */

#include <SoftwareSerial.h>

// ============================================================
// CONFIGURACIÓN DE PINES
// ============================================================
const int PIN_FLEX = A0;       // Pin analógico del sensor flex
const int PIN_BLE_RX = 10;    // RX del SoftwareSerial (conectar a TX del HM-10)
const int PIN_BLE_TX = 11;    // TX del SoftwareSerial (conectar a RX del HM-10)

// ============================================================
// CONSTANTES DE CALIBRACIÓN
// ============================================================
// Ajustar estos valores según tu sensor flex específico.
// Para calibrar:
//   1. Subir el sketch con Serial.println(analogRead(A0))
//   2. Anotar el valor con el sensor recto (FLEX_MIN)
//   3. Anotar el valor con el sensor completamente doblado (FLEX_MAX)
//   4. Actualizar los valores aquí
const int FLEX_MIN = 200;     // Valor analógico con sensor recto (0% flexión)
const int FLEX_MAX = 800;     // Valor analógico con sensor totalmente doblado (100% flexión)

// ============================================================
// CONFIGURACIÓN DE SUAVIZADO
// ============================================================
// Promedio móvil simple para reducir ruido en las lecturas
const int NUM_MUESTRAS = 5;         // Cantidad de muestras para el promedio móvil
int lecturas[NUM_MUESTRAS];         // Buffer circular de lecturas
int indiceMuestra = 0;              // Índice actual en el buffer
long sumaLecturas = 0;              // Suma acumulada para cálculo rápido del promedio
bool bufferLleno = false;           // Indica si el buffer ya tiene todas las muestras

// ============================================================
// CONFIGURACIÓN DE TIMING
// ============================================================
const unsigned long INTERVALO_ENVIO_MS = 50;  // 50ms = 20 Hz de actualización
unsigned long ultimoEnvio = 0;                 // Timestamp del último envío

// ============================================================
// COMUNICACIÓN BLE
// ============================================================
SoftwareSerial bleSerial(PIN_BLE_RX, PIN_BLE_TX);

// ============================================================
// SETUP
// ============================================================
void setup() {
  // Serial para debug por monitor serie (opcional)
  Serial.begin(9600);
  Serial.println("=== Guante Flex BLE ===");
  Serial.println("Inicializando...");

  // Inicializar comunicación con HM-10
  bleSerial.begin(9600);

  // Inicializar el buffer de lecturas en cero
  for (int i = 0; i < NUM_MUESTRAS; i++) {
    lecturas[i] = 0;
  }

  // Configurar pin del sensor como entrada
  pinMode(PIN_FLEX, INPUT);

  Serial.println("Listo. Enviando datos por BLE...");
}

// ============================================================
// LOOP PRINCIPAL
// ============================================================
void loop() {
  unsigned long ahora = millis();

  // Verificar si es momento de tomar una lectura y enviar
  if (ahora - ultimoEnvio >= INTERVALO_ENVIO_MS) {
    ultimoEnvio = ahora;

    // Leer el valor crudo del sensor flex
    int valorCrudo = analogRead(PIN_FLEX);

    // Aplicar suavizado con promedio móvil
    int valorSuavizado = suavizar(valorCrudo);

    // Mapear al rango 0-100%
    int porcentaje = map(valorSuavizado, FLEX_MIN, FLEX_MAX, 0, 100);

    // Limitar al rango válido (por si el sensor da valores fuera de calibración)
    porcentaje = constrain(porcentaje, 0, 100);

    // Enviar por BLE al dispositivo Android
    bleSerial.print("FLEX:");
    bleSerial.println(porcentaje);

    // También imprimir por Serial para debug
    Serial.print("Crudo: ");
    Serial.print(valorCrudo);
    Serial.print(" | Suavizado: ");
    Serial.print(valorSuavizado);
    Serial.print(" | Flex: ");
    Serial.print(porcentaje);
    Serial.println("%");
  }
}

// ============================================================
// FUNCIONES AUXILIARES
// ============================================================

/**
 * Aplica un promedio móvil simple sobre las últimas NUM_MUESTRAS lecturas.
 * Usa un buffer circular para eficiencia.
 *
 * @param nuevaLectura  Valor crudo del sensor (0-1023)
 * @return              Valor suavizado (promedio de las últimas N lecturas)
 */
int suavizar(int nuevaLectura) {
  // Restar la lectura antigua de la suma
  sumaLecturas -= lecturas[indiceMuestra];

  // Guardar la nueva lectura en el buffer
  lecturas[indiceMuestra] = nuevaLectura;

  // Sumar la nueva lectura
  sumaLecturas += nuevaLectura;

  // Avanzar el índice circular
  indiceMuestra = (indiceMuestra + 1) % NUM_MUESTRAS;

  // Marcar el buffer como lleno después de la primera vuelta completa
  if (!bufferLleno && indiceMuestra == 0) {
    bufferLleno = true;
  }

  // Calcular el promedio
  // Si el buffer no está lleno todavía, dividir por las muestras que hay
  int divisor = bufferLleno ? NUM_MUESTRAS : indiceMuestra;
  if (divisor == 0) divisor = 1; // Evitar división por cero en la primera lectura

  return (int)(sumaLecturas / divisor);
}
