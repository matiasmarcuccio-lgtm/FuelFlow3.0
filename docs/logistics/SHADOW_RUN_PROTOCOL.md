# Protocolo de Aborto y Reglas de Enfrentamiento (Shadow Run)

Este documento establece los parámetros operativos y matemáticos innegociables para la ejecución del piloto físico en terreno (Shadow Run) de FuelFlow 3.0 JITSite. 

El objetivo es proteger la cadena de producción, garantizando que ninguna falla de software o de conectividad impacte la métrica primaria de la mina (BCM/hr).

> [!IMPORTANT]
> **Cadena de Distribución CI/CD:** Este archivo `.md` es la única fuente de verdad para el equipo de Ingeniería. A través de nuestro *pipeline*, este documento se compila automáticamente a PDF inmutable y se distribuye en tiempo real a SharePoint/Confluence corporativo y a las tablets MDM de los Supervisores de Turno. **Bajo ninguna circunstancia un operador en terreno dependerá del acceso a Git.**

## 1. Métrica de Aborto Automático (El Umbral de Bloqueo)
La parálisis en la línea de acarreo es inaceptable. Se prohíbe delegar la decisión de aborto al pánico o a la intuición del momento. Se aplicará la siguiente fórmula matemática estricta:

El **Shadow Run será abortado de manera inmediata** y se ordenará la transición a operaciones manuales en papel (Fallback) si se cumple **cualquiera** de las siguientes condiciones:
1. **El 3% de la flota activa** está bloqueada simultáneamente por errores del sistema o latencia de red.
2. **2 camiones** de acarreo están bloqueados en fila india.
3. Un solo camión permanece bloqueado en la rampa, en la pala, o en cualquier punto crítico durante un máximo de **10 minutos**.

## 2. Ejecución del Fallback a Papel
Si se cruza el umbral de aborto:
1. El Supervisor de Rampa (Shift Boss) o el Despachador de Flota tiene la **autoridad unilateral** para declarar el Aborto del Piloto por radio de dos vías (Canal Primario de Operaciones).
2. Se activa inmediatamente el uso de planillas físicas de *Safe Work Checklist*.
3. **Regla de Cero Detención:** Ninguna excavadora principal ni equipo de carguío detendrá sus operaciones. Los despachos seguirán fluyendo con acreditación por radio y validación de papel.

## 3. Cadena de Responsabilidad y Auditoría Post-Incidente
* Quien autorice el aborto deberá registrar la hora exacta y el síntoma visual reportado (ej. "Pantalla atorada en 'Sincronizando...' por 10 minutos").
* Ingeniería congelará el análisis de logs de `pg_net` y `pg_cron` en PostgreSQL, aislando las ventanas de tiempo previas al aborto para identificar desconexiones de red, latencia de OCR o caídas de Edge Functions.
