// Toxina de Chaos Engineering
const random = Math.random();

if (random < 0.4) {
  // 40% de probabilidad: Simulacro de estrangulamiento de API (Rate Limit)
  throw new Error("HTTP 429: Too Many Requests - Xero API Throttling");
} else if (random < 0.7) {
  // 30% de probabilidad: Simulacro de latencia destructiva
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      reject(new Error("HTTP 504: Gateway Timeout - Xero Core Unresponsive"));
    }, 15000); // Mantiene el hilo de Deno colgando 15 segundos
  });
}

// 30% de probabilidad: El paquete sobrevive y pasa
return $input.item;
