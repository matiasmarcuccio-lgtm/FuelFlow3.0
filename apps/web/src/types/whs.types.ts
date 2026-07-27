export type OverrideReason = 'OPERARIO AUSENTE' | 'EMERGENCIA OPERATIVA' | 'FALLO DE TERMINAL';

export interface EmergencyOverridePayload {
  p_asset_id: string;
  p_override_reason: OverrideReason;
  p_manager_pin: string;
}

export interface BreakGlassResponse {
  success: boolean;
  action: string;
  asset_id: string;
  victim_uid: string;
  reason: OverrideReason;
}

export interface BillingProjectSite {
  id: string;
  name: string;
  status: 'ACTIVE' | 'ARCHIVED';
  vault_status: 'OPERATIONAL' | 'VAULT_ACTIVE' | 'VAULT_DELINQUENT' | 'PURGE_SCHEDULED' | 'PURGED';
  purge_scheduled_for?: string | null;
}
