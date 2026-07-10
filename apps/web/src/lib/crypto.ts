export const verifyOfflinePin = async (inputPin: string, storedSalt: string, storedHash: string): Promise<boolean> => {
  const encoder = new TextEncoder();
  
  // 1. Importar el PIN ingresado como material criptográfico base
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw',
    encoder.encode(inputPin),
    { name: 'PBKDF2' },
    false,
    ['deriveBits']
  );

  // 2. Derivar los bits usando la sal almacenada y 100,000 iteraciones (Estándar OWASP)
  const derivedBits = await window.crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt: encoder.encode(storedSalt),
      iterations: 100000,
      hash: 'SHA-256'
    },
    keyMaterial,
    256
  );

  // 3. Convertir el resultado a Hex para comparar de forma segura
  const hashArray = Array.from(new Uint8Array(derivedBits));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

  return hashHex === storedHash;
};
