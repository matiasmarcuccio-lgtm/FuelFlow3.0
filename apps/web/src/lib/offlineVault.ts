export interface OutboxPayload {
  id: string;
  rpc_name: string;
  payload: any;
  client_timestamp: string;
  retry_count: number;
}

const DB_NAME = 'jitsite_offline_vault';
const DB_VERSION = 1;
const STORE_NAME = 'rpc_outbox';

const openVault = (): Promise<IDBDatabase> => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      }
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
};

export const enqueueRpcPayload = async (rpcName: string, payload: any): Promise<string> => {
  const db = await openVault();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  const store = tx.objectStore(STORE_NAME);

  const outboxItem: OutboxPayload = {
    id: crypto.randomUUID(),
    rpc_name: rpcName,
    // Inyectamos la marca de tiempo exacta en que el guante tocó la pantalla
    payload: { ...payload, p_client_timestamp: new Date().toISOString() },
    client_timestamp: new Date().toISOString(),
    retry_count: 0,
  };

  return new Promise((resolve, reject) => {
    const request = store.add(outboxItem);
    request.onsuccess = () => resolve(outboxItem.id);
    request.onerror = () => reject(request.error);
  });
};

export const getOutboxQueue = async (): Promise<OutboxPayload[]> => {
  const db = await openVault();
  const tx = db.transaction(STORE_NAME, 'readonly');
  const store = tx.objectStore(STORE_NAME);

  return new Promise((resolve, reject) => {
    const request = store.getAll();
    request.onsuccess = () => {
      // Orden cronológico estricto: El primero en entrar es el primero en salir (FIFO)
      const sorted = (request.result as OutboxPayload[]).sort(
        (a, b) => new Date(a.client_timestamp).getTime() - new Date(b.client_timestamp).getTime()
      );
      resolve(sorted);
    };
    request.onerror = () => reject(request.error);
  });
};

export const removeOutboxItem = async (id: string): Promise<void> => {
  const db = await openVault();
  const tx = db.transaction(STORE_NAME, 'readwrite');
  const store = tx.objectStore(STORE_NAME);
  store.delete(id);
};
