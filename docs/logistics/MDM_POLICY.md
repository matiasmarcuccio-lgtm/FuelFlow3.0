# Política MDM y Auditoría de Dispositivos (Kiosco)

Este documento define la topología de seguridad obligatoria para todas las tablets y pantallas rugerizadas desplegadas en la línea de acarreo. Las vulnerabilidades de manipulación humana (Time-Spoofing) y distracciones operativas quedan selladas a nivel de sistema operativo (MDM - Mobile Device Management).

> [!IMPORTANT]
> **Cadena de Distribución CI/CD:** Este archivo `.md` es la única fuente de verdad para el equipo de Ingeniería. A través de nuestro *pipeline*, este documento se compila automáticamente a PDF inmutable y se distribuye en tiempo real a SharePoint/Confluence corporativo y a los administradores de flota. **Bajo ninguna circunstancia un operador en terreno dependerá del acceso a Git.**

## 1. Single App Mode (Modo Kiosco Estricto)
* Todas las tablets arrancarán automáticamente en la aplicación FuelFlow 3.0 JITSite.
* **Bloqueo Periférico:** Se desactivarán el botón de inicio (Home), el acceso a aplicaciones recientes (Recents) y la barra de notificaciones descendente. El operador no puede abandonar la aplicación bajo ninguna circunstancia.

## 2. Prevención de Time-Spoofing (Auditoría Forense)
El fraude de horas de trabajo y fechas de caducidad de pólizas a través del reloj del sistema queda clausurado:
* **Bloqueo del Sistema:** Acceso a `Configuración > Fecha y Hora` está terminantemente prohibido.
* **NTP Inyectado:** La sincronización de reloj será forzada y bloqueada de manera centralizada hacia un servidor NTP autorizado por la compañía minera.
* Cualquier discrepancia detectada por el servidor PostgreSQL (AEST) que indique que el dispositivo perdió sincronización y regresó a una época manual, será inyectada en la tabla `ocr_audit_logs` con bandera de anomalía transaccional.

## 3. Restricciones de Telemetría y Red
* **Radiofrecuencia Aislada:** El operador no podrá habilitar el "Modo Avión", ni alternar entre Wi-Fi, 4G, 5G o Bluetooth.
* El MDM forzará la persistencia de conexión en la banda de frecuencia dedicada a la telemetría de la mina.

## 4. Gestión de Energía (Always-On)
* Para evitar la hibernación de los *sockets* del *pool* transaccional, las pantallas rugerizadas mantendrán un estado *Always-On* (Nunca Apagar).
* En periodos de inactividad o espera en pala, la interfaz atenuará el brillo para ahorrar batería, pero el procesador de red y el lazo del navegador se mantendrán despiertos para absorber alertas instantáneas (WebSockets/Realtime) sin el peaje de la reconexión en frío.
