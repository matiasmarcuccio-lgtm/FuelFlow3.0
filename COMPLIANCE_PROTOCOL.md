COMPLIANCE_PROTOCOL.md
1. Declaración de Intención
Este documento detalla la arquitectura de integridad de FuelFlow, diseñada específicamente para cumplir con los estándares de la National Heavy Vehicle Law (HVNL) y los requisitos de la Cadena de Responsabilidad (CoR) en proyectos de infraestructura Tier-1. FuelFlow no es simplemente una plataforma de contratación de transportes; es un Sistema de Debida Diligencia Automatizada.

2. Marco Legal de Referencia
FuelFlow está diseñado para asistir a los contratistas principales en la gestión de su responsabilidad bajo el CoR (Chain of Responsibility), garantizando que todos los actores de la cadena —desde el cargador hasta el conductor— cumplan con sus deberes legales.

3. Arquitectura de Integridad (Inmutabilidad)
Para evitar la negligencia y la alteración de datos tras la contratación, FuelFlow implementa mecanismos de bloqueo a nivel de motor de base de datos (PostgreSQL):

Bloqueo de Estado del Contrato: Una vez que un contrato alcanza el estado BIDDING_LOCKED, el sistema impide físicamente cualquier edición a los elementos estructurales (structural_elements) mediante triggers de integridad.

Auditoría de Cambios: Cualquier intento de alteración de un contrato en curso dispara una excepción de seguridad que es registrada para auditoría interna.

4. Trazabilidad de Ingeniería (Gemelo Digital)
La plataforma vincula cada elemento de carga a su GUID de diseño original (BIM) proveniente de software de ingeniería (Revit/Civil 3D). Esto asegura que:

El transportista sepa exactamente qué elemento estructural está moviendo.

El coordinador de obra pueda verificar, tras la entrega, que el elemento físico recibido corresponde al GUID especificado en el modelo del proyecto, cerrando el ciclo de certificación digital.

5. Protocolo de Debida Diligencia en Fatiga
Para mitigar la responsabilidad ante la gestión de la fatiga (HVNL), FuelFlow no confía en declaraciones verbales:

Evidencia Física: Se exige a los transportistas tradicionales subir una copia digitalizada del Diario Nacional de Trabajo antes de la adjudicación de cualquier carga.

Hashing Criptográfico: Cada imagen subida es vinculada mediante un hash SHA-256 a la oferta, creando una prueba inalterable de que, al momento del contrato, el transportista declaró su capacidad legal.

Cierre Auditado: Cada entrega finaliza con una declaración jurada digital firmada por ambas partes, sellada con telemetría GPS y timestamp del servidor.

6. Transparencia y Auditoría
Todos los registros en FuelFlow son Append-Only (solo inserción) para la tabla de manifiestos (cor_manifests), proporcionando un historial inmutable que puede presentarse ante investigadores de la NHVR en caso de un incidente de tráfico.
