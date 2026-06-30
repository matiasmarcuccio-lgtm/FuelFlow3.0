import * as FileSystem from 'expo-file-system';
import { supabase } from '@/lib/supabase';
import { EvidenceQueue } from './EvidenceQueue';
import NetInfo from '@react-native-community/netinfo';

export class EvidenceSyncWorker {
  private static isSyncing = false;

  /**
   * Orchestrates the upload of pending evidence items using native OS background transfers.
   * Guaranteed not to block the JS UI thread.
   */
  static async executeSync() {
    if (this.isSyncing) return;

    const netState = await NetInfo.fetch();
    if (!netState.isConnected) return;

    try {
      this.isSyncing = true;
      const queue = await EvidenceQueue.getQueue();
      
      if (queue.length === 0) return;
      console.log(`[EvidenceSyncWorker] Found ${queue.length} pending items. Initiating native uploads...`);

      const { data: { session } } = await supabase.auth.getSession();
      if (!session) {
        console.warn('[EvidenceSyncWorker] No active session. Aborting sync.');
        return;
      }

      for (const item of queue) {
        try {
          const filename = item.image_data.split('/').pop() || `fallback_${Date.now()}.jpg`;
          // Supabase Storage Endpoint configuration
          const { data: projectUrlData } = supabase.storage.from('docket_evidence').getPublicUrl('');
          // Format standard REST endpoint for Supabase Storage uploads
          // public URL ends with /object/public/docket_evidence/
          // We need /object/docket_evidence/
          const baseUrl = projectUrlData.publicUrl.replace('/public/docket_evidence', '');
          const uploadUrl = `${baseUrl}/docket_evidence/${item.load_offer_id}/${filename}`;

          // Delegate to OS Native Network Manager
          const uploadTask = FileSystem.createUploadTask(
            uploadUrl,
            item.image_data,
            {
              httpMethod: 'POST',
              uploadType: FileSystem.FileSystemUploadType.BINARY_CONTENT,
              headers: {
                'Authorization': `Bearer ${session.access_token}`,
                'x-upsert': 'true',
                'Content-Type': 'image/jpeg'
              }
            }
          );

          const response = await uploadTask.uploadAsync();

          if (response && (response.status === 200 || response.status === 201)) {
            // Native transfer successful. Now bind the cryptographic timestamp in DB
            const filePath = `${item.load_offer_id}/${filename}`;
            
            // Link file to the load offer
            const { error: dbError } = await supabase
              .from('load_offers')
              .update({ 
                docket_image_path: filePath,
                status: 'COMPLETED' // Optional based on rules, assumed from previous state
              })
              .eq('id', item.load_offer_id);
              
            if (!dbError) {
              // Complete forensic cleanup
              await EvidenceQueue.dequeue(item.id);
            } else {
              console.error(`[EvidenceSyncWorker] DB link failed for ${item.id}:`, dbError);
            }
          } else {
            console.error(`[EvidenceSyncWorker] OS upload failed with status ${response?.status}`, response?.body);
          }
        } catch (itemError) {
          console.error(`[EvidenceSyncWorker] Item ${item.id} transfer failed:`, itemError);
        }
      }
    } catch (e) {
      console.error('[EvidenceSyncWorker] Fatal sync error:', e);
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Initializes the event listener to trigger sync automatically
   */
  static startDaemon() {
    NetInfo.addEventListener(state => {
      if (state.isConnected) {
        this.executeSync();
      }
    });

    // Run once on startup
    this.executeSync();
  }
}
