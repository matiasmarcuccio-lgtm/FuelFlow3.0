# PROTOCOLO DE SIMULACRO DESTRUCTIVO DE HARDWARE (HDT-1)

## 1. DOCTRINA OPERATIVA
El software está matemáticamente cerrado, pero el silicio no excava la tierra. Este protocolo rige la validación final entre la interfaz digital de FuelFlow y la cruda realidad termodinámica y humana del campamento minero. Una interfaz táctil inoperable con Equipo de Protección Personal (PPE) o bajo estrés térmico anula instantáneamente toda la criptografía subyacente.

## 2. CONDICIONES DE LA PRUEBA (VECTOR DE ESTRÉS FÍSICO)
El sistema será sometido a un simulacro destructivo (*Hardware Death Test*) antes de autorizar el despliegue del 100% de la flota.

### 2.1. Estrés Táctil y Biométrico (Guantes y Frío)
- **El Desafío TOTP AAL2:** El administrador de garita deberá ingresar el código MFA de 6 dígitos utilizando guantes de nitrilo o cuero grueso estandarizados por WHS (Impact Gloves), simulando el entumecimiento de las manos en turnos nocturnos bajo cero.
- **Métrica de Falla:** Si el operador ingresa más de 3 errores tipográficos en el desafío MFA debido al tamaño de la fuente o al área táctil de los botones, la interfaz visual del TOTP será rechazada y el tamaño de los inputs deberá incrementarse en un 200%.

### 2.2. Interferencia de Lúmenes (Ceguera Solar)
- **El Desafío del Escáner OCR:** Los conductores deben posicionar los *dockets* de papel bajo la lente de la tablet en ángulos de 45° con iluminación solar directa y reflejos de polvo de sílice en el cristal de la cabina.
- **Métrica de Falla:** Si el OCR de la tablet falla en 3 intentos consecutivos debido al exceso de brillo o al contraste deficiente de la pantalla (washout visual), se aborta la prueba. (Contramedida: La interfaz debe estar en un Dark Mode de altísimo contraste con tipografía amarilla/verde neón, y el OCR debe tolerar sombras duras).

### 2.3. Asfixia de Espectro (Física de Radiofrecuencia)
- **Micro-cortes en Rampa:** Se simulará la pérdida del enlace microondas (Line of Sight) conduciendo el camión detrás del banco principal de excavación (sombra de radio) al momento exacto de transmitir el payload del OCR.
- **Métrica de Falla:** Si la UI se queda congelada sin mostrar el estado local de "Encolado Offline" o si el payload se destruye en el DOM antes de llegar al *Dead Letter Queue* en IndexedDB, la resiliencia offline es declarada deficiente.

## 3. REGLAS DE ENFRENTAMIENTO Y ABORTO
- **El Supervisor No Ayuda:** Durante la prueba HDT-1, está estrictamente prohibido que el personal de TI asista al operador a encuadrar la cámara o dictar códigos TOTP.
- **Tolerancia Cero a la Culpa Humana:** Si el operador falla en el uso del sistema debido a la fatiga, se registrará como un fracaso del *diseño ergonómico de la UI*, jamás como un error del operario. El operador en terreno tiene la prioridad cognitiva; el software debe someterse a su capacidad, no al revés.

## 4. VEREDICTO
Si el sistema sobrevive a la interferencia lumínica, los guantes PPE, y el estrangulamiento de la radiofrecuencia sin pérdida de tonelaje, la fase de simulación concluirá. Procederemos con la inyección del binario final en las MDM y el despliegue físico.
