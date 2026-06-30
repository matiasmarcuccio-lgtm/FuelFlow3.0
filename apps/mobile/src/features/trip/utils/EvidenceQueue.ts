import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system';

export interface PendingEvidence {
  id: string; // Unique ID for the queue item
  load_offer_id: string;
  image_data: string; // file:// local path
  captured_at_local: string; // ISO timestamp
}

const QUEUE_KEY = '@fuelflow_evidence_queue';

export class EvidenceQueue {
  /**
   * Pushes a new compressed image to the offline queue
   */
  static async enqueue(load_offer_id: string, localImageUri: string): Promise<void> {
    try {
      // 1. Move file to a permanent document directory so it survives temp cache purges
      const filename = localImageUri.split('/').pop() || `evidence_${Date.now()}.jpg`;
      const permanentPath = `${FileSystem.documentDirectory}${filename}`;
      
      await FileSystem.moveAsync({
        from: localImageUri,
        to: permanentPath
      });

      // 2. Read existing queue
      const existingQueueStr = await AsyncStorage.getItem(QUEUE_KEY);
      const queue: PendingEvidence[] = existingQueueStr ? JSON.parse(existingQueueStr) : [];

      // 3. Add to queue
      const newItem: PendingEvidence = {
        id: Math.random().toString(36).substring(7) + Date.now().toString(),
        load_offer_id,
        image_data: permanentPath,
        captured_at_local: new Date().toISOString()
      };

      queue.push(newItem);

      // 4. Save queue
      await AsyncStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
      console.log(`[EvidenceQueue] Enqueued docket for load ${load_offer_id}`);
    } catch (error) {
      console.error('[EvidenceQueue] Failed to enqueue evidence:', error);
      throw error;
    }
  }

  /**
   * Gets all pending evidence items
   */
  static async getQueue(): Promise<PendingEvidence[]> {
    try {
      const queueStr = await AsyncStorage.getItem(QUEUE_KEY);
      return queueStr ? JSON.parse(queueStr) : [];
    } catch (error) {
      console.error('[EvidenceQueue] Failed to get queue:', error);
      return [];
    }
  }

  /**
   * Removes an item from the queue after successful upload and deletes the local file
   */
  static async dequeue(id: string): Promise<void> {
    try {
      const queue = await this.getQueue();
      const itemToRemove = queue.find(item => item.id === id);
      
      if (itemToRemove) {
        // Delete physical file
        try {
          await FileSystem.deleteAsync(itemToRemove.image_data, { idempotent: true });
        } catch (fsError) {
          console.warn('[EvidenceQueue] Could not delete physical file, it might be already gone:', fsError);
        }
      }

      // Remove from AsyncStorage
      const updatedQueue = queue.filter(item => item.id !== id);
      await AsyncStorage.setItem(QUEUE_KEY, JSON.stringify(updatedQueue));
      console.log(`[EvidenceQueue] Dequeued item ${id}`);
    } catch (error) {
      console.error('[EvidenceQueue] Failed to dequeue:', error);
    }
  }
}
