# WHS Incident Playbook: Respuesta a Alertas Forenses (CoR)

Este manual traduce las alertas automatizadas del orquestador n8n (originadas en la base de datos de FuelFlow 3.0) a acciones legales y operativas ejecutables por el **Gerente de Salud y Seguridad (WHS)** o el **Gerente de Turno**.

> [!IMPORTANT]
> **Cadena de Distribución CI/CD:** Este archivo `.md` es la única fuente de verdad para el equipo de Ingeniería. A través de nuestro *pipeline*, este documento se compila automáticamente a PDF inmutable y se distribuye en tiempo real a SharePoint/Confluence corporativo. **Bajo ninguna circunstancia un gerente WHS dependerá del acceso a Git durante una crisis.**

## 1. Triaje de la Alerta: Identificación de Gravedad

Cuando recibas una alerta en tu bandeja de entrada o panel de n8n, el sistema te entregará un *Payload* con el tipo de incidente. Identifica la categoría:

*   🟡 **Nivel 1: Anomalía Técnica (`TECHNICAL_ERROR` / `MANUAL_AUDIT_REQUIRED`)**
    *   **Causa:** El motor OCR no pudo leer el documento porque la cámara del operador usó un formato no soportado (ej. HEIC en iPhones de terceros), estaba manchado de barro, desenfocado o subexpuesto por la luz del sol.
    *   **Acción Requerida:** Esto **no** es un fraude. El operador actuó de buena fe pero la tecnología falló. El Gerente WHS debe abrir el panel web, revisar la foto manualmente con el ojo humano, y aprobar/rechazar el documento.
    *   **Impacto Operativo:** El camión **no** debe ser detenido en la rampa mientras se hace esta revisión visual en la oficina.

*   🔴 **Nivel 2: Fraude Flagrante o Caducidad Vencida (`is_fraud_flagged = true`)**
    *   **Causa:** El modelo de visión por computadora detectó con alta confianza matemática que la póliza subida pertenece a otra persona, la fecha fue alterada (Photoshop) o el seguro ha expirado oficialmente.
    *   **Acción Requerida:** Violación crítica de la Cadena de Responsabilidad (CoR). Proceder inmediatamente a la "Intervención Operativa".

*   ⚫ **Nivel 3: Evasión de Auditoría (`DLQ_ORPHAN_ALERT`)**
    *   **Causa:** Un operador fue autorizado por un supervisor en la mina, pero la infraestructura transaccional de auditoría colapsó y el documento nunca fue procesado por el OCR después de 15 minutos (detectado por `pg_cron`).
    *   **Acción Requerida:** Esto es un quiebre en nuestra Cadena de Custodia. No es culpa del operador. Informar de inmediato a Ingeniería (IT) para restaurar el procesador de *Edge Functions* y revisar manualmente la póliza del operador.

## 2. Intervención Operativa (Alerta Nivel 2 - Fraude)

Si la alerta confirmada es de **Nivel 2 (Fraude)**, el Gerente WHS debe ejecutar el siguiente protocolo:

1.  **Aislar la Operación:** Contactar por radio de dos vías (Canal Primario) al Supervisor de Rampa (Shift Boss) o al Despachador de Flota.
2.  **Orden de Detención Legal:** Ordenar que el vehículo del operador infractor (identificado por `driver_id`) sea escoltado fuera del circuito principal de acarreo y parqueado en zona segura (Safe Park). **No** se le debe permitir abandonar la cabina ni reanudar la marcha.
3.  **Auditoría Física:** El Supervisor de Rampa confiscará temporalmente la identificación del conductor para corroborarla con la evidencia legal sellada en `ocr_audit_logs`.
4.  **Expulsión o Sanción:** Si se comprueba falsificación deliberada de documentos, activar el protocolo disciplinario de expulsión del campamento bajo el marco de la Cadena de Responsabilidad (CoR).

## 3. Preservación Legal (CoR)
Bajo ninguna circunstancia intentes "borrar" o "resetear" el registro transaccional en la aplicación. FuelFlow 3.0 JITSite aplica seguridad de nivel de fila (RLS). Tu acción forense quedará registrada de por vida, lo que exonera a la gerencia minera de responsabilidad penal si el caso escala a tribunales.
