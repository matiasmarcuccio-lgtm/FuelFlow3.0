export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      access_logs: {
        Row: {
          action: string
          id: string
          row_id: string
          table_name: string
          timestamp: string | null
          user_id: string | null
        }
        Insert: {
          action: string
          id?: string
          row_id: string
          table_name: string
          timestamp?: string | null
          user_id?: string | null
        }
        Update: {
          action?: string
          id?: string
          row_id?: string
          table_name?: string
          timestamp?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "access_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_assignments: {
        Row: {
          asset_id: string
          assigned_by: string
          created_at: string | null
          driver_id: string
          fatigue_override_reason: string | null
          fleet_id: string
          id: string
          override_approved_by: string | null
          prestart_commenced_at: string | null
          shift_end: string | null
          shift_start: string
          status: Database["public"]["Enums"]["assignment_status"]
        }
        Insert: {
          asset_id: string
          assigned_by: string
          created_at?: string | null
          driver_id: string
          fatigue_override_reason?: string | null
          fleet_id: string
          id?: string
          override_approved_by?: string | null
          prestart_commenced_at?: string | null
          shift_end?: string | null
          shift_start?: string
          status?: Database["public"]["Enums"]["assignment_status"]
        }
        Update: {
          asset_id?: string
          assigned_by?: string
          created_at?: string | null
          driver_id?: string
          fatigue_override_reason?: string | null
          fleet_id?: string
          id?: string
          override_approved_by?: string | null
          prestart_commenced_at?: string | null
          shift_end?: string | null
          shift_start?: string
          status?: Database["public"]["Enums"]["assignment_status"]
        }
        Relationships: [
          {
            foreignKeyName: "asset_assignments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_assignments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "asset_assignments_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
          {
            foreignKeyName: "asset_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_assignments_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_assignments_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_assignments_override_approved_by_fkey"
            columns: ["override_approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_lockouts: {
        Row: {
          asset_id: string
          created_at: string | null
          fleet_id: string
          id: string
          locked_by_operator_uid: string
          lockout_reason: string
          prestart_log_id: string | null
          released_at: string | null
          released_by_fitter_uid: string | null
          resolution_notes: string | null
          status: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string | null
          fleet_id: string
          id?: string
          locked_by_operator_uid: string
          lockout_reason: string
          prestart_log_id?: string | null
          released_at?: string | null
          released_by_fitter_uid?: string | null
          resolution_notes?: string | null
          status?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string | null
          fleet_id?: string
          id?: string
          locked_by_operator_uid?: string
          lockout_reason?: string
          prestart_log_id?: string | null
          released_at?: string | null
          released_by_fitter_uid?: string | null
          resolution_notes?: string | null
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asset_lockouts_prestart_log_id_fkey"
            columns: ["prestart_log_id"]
            isOneToOne: false
            referencedRelation: "whs_prestart_logs"
            referencedColumns: ["id"]
          },
        ]
      }
      asset_telemetry_logs: {
        Row: {
          asset_id: string
          client_timestamp: string
          created_at: string | null
          event_type: string
          id: string
          payload: Json
          recorded_by: string
        }
        Insert: {
          asset_id: string
          client_timestamp: string
          created_at?: string | null
          event_type: string
          id?: string
          payload: Json
          recorded_by: string
        }
        Update: {
          asset_id?: string
          client_timestamp?: string
          created_at?: string | null
          event_type?: string
          id?: string
          payload?: Json
          recorded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "asset_telemetry_logs_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      assets: {
        Row: {
          baseline_burn_rate_lph: number | null
          category: Database["public"]["Enums"]["asset_category"]
          current_engine_hours: number | null
          current_odometer: number | null
          fleet_id: string
          hopper_capacity_m3: number | null
          id: string
          internal_code: string
          last_prestart_at: string | null
          last_prestart_by_uid: string | null
          required_license_id: string
          status: Database["public"]["Enums"]["asset_status"]
          updated_at: string | null
        }
        Insert: {
          baseline_burn_rate_lph?: number | null
          category: Database["public"]["Enums"]["asset_category"]
          current_engine_hours?: number | null
          current_odometer?: number | null
          fleet_id: string
          hopper_capacity_m3?: number | null
          id?: string
          internal_code: string
          last_prestart_at?: string | null
          last_prestart_by_uid?: string | null
          required_license_id: string
          status?: Database["public"]["Enums"]["asset_status"]
          updated_at?: string | null
        }
        Update: {
          baseline_burn_rate_lph?: number | null
          category?: Database["public"]["Enums"]["asset_category"]
          current_engine_hours?: number | null
          current_odometer?: number | null
          fleet_id?: string
          hopper_capacity_m3?: number | null
          id?: string
          internal_code?: string
          last_prestart_at?: string | null
          last_prestart_by_uid?: string | null
          required_license_id?: string
          status?: Database["public"]["Enums"]["asset_status"]
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assets_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assets_required_license_id_fkey"
            columns: ["required_license_id"]
            isOneToOne: false
            referencedRelation: "license_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      assignments: {
        Row: {
          assigned_at: string | null
          id: string
          load_offer_id: string | null
          operator_id: string
        }
        Insert: {
          assigned_at?: string | null
          id?: string
          load_offer_id?: string | null
          operator_id: string
        }
        Update: {
          assigned_at?: string | null
          id?: string
          load_offer_id?: string | null
          operator_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "assignments_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: true
            referencedRelation: "load_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: true
            referencedRelation: "view_cor_audit_timeline"
            referencedColumns: ["load_id"]
          },
        ]
      }
      billing_contracts: {
        Row: {
          asset_id: string
          currency: string | null
          erp_contact_id: string | null
          hourly_rate_asset: number
          hourly_rate_operator: number | null
          id: string
          is_active: boolean | null
          model: Database["public"]["Enums"]["hire_model_type"]
          overtime_multiplier: number | null
          overtime_threshold_hours: number | null
          updated_at: string | null
        }
        Insert: {
          asset_id: string
          currency?: string | null
          erp_contact_id?: string | null
          hourly_rate_asset: number
          hourly_rate_operator?: number | null
          id?: string
          is_active?: boolean | null
          model: Database["public"]["Enums"]["hire_model_type"]
          overtime_multiplier?: number | null
          overtime_threshold_hours?: number | null
          updated_at?: string | null
        }
        Update: {
          asset_id?: string
          currency?: string | null
          erp_contact_id?: string | null
          hourly_rate_asset?: number
          hourly_rate_operator?: number | null
          id?: string
          is_active?: boolean | null
          model?: Database["public"]["Enums"]["hire_model_type"]
          overtime_multiplier?: number | null
          overtime_threshold_hours?: number | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "billing_contracts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: true
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_contracts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: true
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "billing_contracts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: true
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      billing_ledger: {
        Row: {
          amount_aud: number
          created_at: string | null
          executed_by_uid: string
          fleet_id: string
          id: string
          payment_method: string | null
          status: string | null
          stripe_charge_id: string
        }
        Insert: {
          amount_aud: number
          created_at?: string | null
          executed_by_uid: string
          fleet_id: string
          id?: string
          payment_method?: string | null
          status?: string | null
          stripe_charge_id: string
        }
        Update: {
          amount_aud?: number
          created_at?: string | null
          executed_by_uid?: string
          fleet_id?: string
          id?: string
          payment_method?: string | null
          status?: string | null
          stripe_charge_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_ledger_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          abn_number: string | null
          billing_email: string
          created_at: string | null
          fleet_id: string
          id: string
          legal_name: string
          payment_terms: string | null
        }
        Insert: {
          abn_number?: string | null
          billing_email: string
          created_at?: string | null
          fleet_id: string
          id?: string
          legal_name: string
          payment_terms?: string | null
        }
        Update: {
          abn_number?: string | null
          billing_email?: string
          created_at?: string | null
          fleet_id?: string
          id?: string
          legal_name?: string
          payment_terms?: string | null
        }
        Relationships: []
      }
      compliance_documents: {
        Row: {
          created_at: string | null
          doc_type: string
          expiry_date: string
          file_url: string
          id: string
          is_verified: boolean | null
          profile_id: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string | null
          doc_type: string
          expiry_date: string
          file_url: string
          id?: string
          is_verified?: boolean | null
          profile_id?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string | null
          doc_type?: string
          expiry_date?: string
          file_url?: string
          id?: string
          is_verified?: boolean | null
          profile_id?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "compliance_documents_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cor_incidents: {
        Row: {
          created_at: string
          description: string
          gps_location: unknown
          id: string
          load_offer_id: string
          operator_id: string
        }
        Insert: {
          created_at?: string
          description: string
          gps_location: unknown
          id?: string
          load_offer_id: string
          operator_id: string
        }
        Update: {
          created_at?: string
          description?: string
          gps_location?: unknown
          id?: string
          load_offer_id?: string
          operator_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "cor_incidents_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "load_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cor_incidents_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "view_cor_audit_timeline"
            referencedColumns: ["load_id"]
          },
          {
            foreignKeyName: "cor_incidents_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cor_manifests: {
        Row: {
          action: string
          driver_signature_hash: string
          gps_location: unknown
          id: string
          load_offer_id: string | null
          loader_signature_hash: string
          operator_id: string
          server_timestamp: string | null
        }
        Insert: {
          action: string
          driver_signature_hash: string
          gps_location: unknown
          id?: string
          load_offer_id?: string | null
          loader_signature_hash: string
          operator_id: string
          server_timestamp?: string | null
        }
        Update: {
          action?: string
          driver_signature_hash?: string
          gps_location?: unknown
          id?: string
          load_offer_id?: string | null
          loader_signature_hash?: string
          operator_id?: string
          server_timestamp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "cor_manifests_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "load_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cor_manifests_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "view_cor_audit_timeline"
            referencedColumns: ["load_id"]
          },
        ]
      }
      dead_letter_queue: {
        Row: {
          event_type: string
          failed_at: string | null
          id: string
          last_error: string | null
          original_event_id: string
          payload: Json
        }
        Insert: {
          event_type: string
          failed_at?: string | null
          id?: string
          last_error?: string | null
          original_event_id: string
          payload: Json
        }
        Update: {
          event_type?: string
          failed_at?: string | null
          id?: string
          last_error?: string | null
          original_event_id?: string
          payload?: Json
        }
        Relationships: []
      }
      driver_fatigue_evidence: {
        Row: {
          evidence_hash: string
          evidence_url: string
          gps_location: unknown
          id: string
          load_offer_id: string | null
          operator_id: string
          rejection_reason: string | null
          reviewer_id: string | null
          status: string | null
          upload_timestamp: string | null
        }
        Insert: {
          evidence_hash: string
          evidence_url: string
          gps_location: unknown
          id?: string
          load_offer_id?: string | null
          operator_id: string
          rejection_reason?: string | null
          reviewer_id?: string | null
          status?: string | null
          upload_timestamp?: string | null
        }
        Update: {
          evidence_hash?: string
          evidence_url?: string
          gps_location?: unknown
          id?: string
          load_offer_id?: string | null
          operator_id?: string
          rejection_reason?: string | null
          reviewer_id?: string | null
          status?: string | null
          upload_timestamp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "driver_fatigue_evidence_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "load_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_fatigue_evidence_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "view_cor_audit_timeline"
            referencedColumns: ["load_id"]
          },
        ]
      }
      driver_licenses: {
        Row: {
          created_at: string | null
          driver_id: string
          expiry_date: string
          id: string
          issued_date: string
          license_category_id: string
        }
        Insert: {
          created_at?: string | null
          driver_id: string
          expiry_date: string
          id?: string
          issued_date: string
          license_category_id: string
        }
        Update: {
          created_at?: string | null
          driver_id?: string
          expiry_date?: string
          id?: string
          issued_date?: string
          license_category_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "driver_licenses_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "driver_licenses_license_category_id_fkey"
            columns: ["license_category_id"]
            isOneToOne: false
            referencedRelation: "license_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      erp_outbox: {
        Row: {
          certificate_id: string | null
          created_at: string | null
          id: string
          last_error: string | null
          next_retry_at: string | null
          payload: Json
          retry_count: number | null
          status: string | null
          updated_at: string | null
        }
        Insert: {
          certificate_id?: string | null
          created_at?: string | null
          id?: string
          last_error?: string | null
          next_retry_at?: string | null
          payload: Json
          retry_count?: number | null
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          certificate_id?: string | null
          created_at?: string | null
          id?: string
          last_error?: string | null
          next_retry_at?: string | null
          payload?: Json
          retry_count?: number | null
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "erp_outbox_certificate_id_fkey"
            columns: ["certificate_id"]
            isOneToOne: true
            referencedRelation: "execution_certificates"
            referencedColumns: ["id"]
          },
        ]
      }
      excavator_states: {
        Row: {
          asset_id: string
          current_material: string
          geological_block: string | null
          operational_status: Database["public"]["Enums"]["excavator_status"]
          updated_at: string
        }
        Insert: {
          asset_id: string
          current_material?: string
          geological_block?: string | null
          operational_status?: Database["public"]["Enums"]["excavator_status"]
          updated_at?: string
        }
        Update: {
          asset_id?: string
          current_material?: string
          geological_block?: string | null
          operational_status?: Database["public"]["Enums"]["excavator_status"]
          updated_at?: string
        }
        Relationships: []
      }
      execution_certificates: {
        Row: {
          asset_subtotal: number
          assignment_id: string
          billed_to_erp_id: string | null
          contract_id: string
          forensic_pdf_hash: string | null
          forensic_pdf_url: string | null
          generated_at: string
          hardware_engine_hours: number | null
          id: string
          operator_subtotal: number
          overtime_hours: number
          regular_hours: number
          sync_status: string | null
          telemetry_confidence: number
          telemetry_source: string
          total_billable: number
          total_hours: number
        }
        Insert: {
          asset_subtotal: number
          assignment_id: string
          billed_to_erp_id?: string | null
          contract_id: string
          forensic_pdf_hash?: string | null
          forensic_pdf_url?: string | null
          generated_at?: string
          hardware_engine_hours?: number | null
          id?: string
          operator_subtotal: number
          overtime_hours: number
          regular_hours: number
          sync_status?: string | null
          telemetry_confidence?: number
          telemetry_source?: string
          total_billable: number
          total_hours: number
        }
        Update: {
          asset_subtotal?: number
          assignment_id?: string
          billed_to_erp_id?: string | null
          contract_id?: string
          forensic_pdf_hash?: string | null
          forensic_pdf_url?: string | null
          generated_at?: string
          hardware_engine_hours?: number | null
          id?: string
          operator_subtotal?: number
          overtime_hours?: number
          regular_hours?: number
          sync_status?: string | null
          telemetry_confidence?: number
          telemetry_source?: string
          total_billable?: number
          total_hours?: number
        }
        Relationships: [
          {
            foreignKeyName: "execution_certificates_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: true
            referencedRelation: "asset_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "execution_certificates_contract_id_fkey"
            columns: ["contract_id"]
            isOneToOne: false
            referencedRelation: "billing_contracts"
            referencedColumns: ["id"]
          },
        ]
      }
      expense_quarantine: {
        Row: {
          created_at: string | null
          driver_uid: string
          expense_category: string | null
          extracted_amount: number | null
          extracted_vendor: string | null
          id: string
          ocr_confidence: number | null
          raw_image_url: string
          review_notes: string | null
          reviewed_by_uid: string | null
          shift_id: string
          status: string | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          driver_uid: string
          expense_category?: string | null
          extracted_amount?: number | null
          extracted_vendor?: string | null
          id?: string
          ocr_confidence?: number | null
          raw_image_url: string
          review_notes?: string | null
          reviewed_by_uid?: string | null
          shift_id: string
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          driver_uid?: string
          expense_category?: string | null
          extracted_amount?: number | null
          extracted_vendor?: string | null
          id?: string
          ocr_confidence?: number | null
          raw_image_url?: string
          review_notes?: string | null
          reviewed_by_uid?: string | null
          shift_id?: string
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "expense_quarantine_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "asset_assignments"
            referencedColumns: ["id"]
          },
        ]
      }
      expenses: {
        Row: {
          driver_id: string | null
          expense_category: string
          fleet_id: string
          id: string
          incurred_at: string
          is_tax_deductible: boolean | null
          receipt_url: string | null
          total_amount: number
          trip_id: string | null
        }
        Insert: {
          driver_id?: string | null
          expense_category: string
          fleet_id: string
          id?: string
          incurred_at: string
          is_tax_deductible?: boolean | null
          receipt_url?: string | null
          total_amount: number
          trip_id?: string | null
        }
        Update: {
          driver_id?: string | null
          expense_category?: string
          fleet_id?: string
          id?: string
          incurred_at?: string
          is_tax_deductible?: boolean | null
          receipt_url?: string | null
          total_amount?: number
          trip_id?: string | null
        }
        Relationships: []
      }
      fatigue_logs: {
        Row: {
          digital_signature_hash: string
          driver_id: string
          event_type: string
          fleet_id: string
          id: string
          latitude: number | null
          logged_at: string | null
          longitude: number | null
        }
        Insert: {
          digital_signature_hash: string
          driver_id: string
          event_type: string
          fleet_id: string
          id?: string
          latitude?: number | null
          logged_at?: string | null
          longitude?: number | null
        }
        Update: {
          digital_signature_hash?: string
          driver_id?: string
          event_type?: string
          fleet_id?: string
          id?: string
          latitude?: number | null
          logged_at?: string | null
          longitude?: number | null
        }
        Relationships: []
      }
      fleet_invites: {
        Row: {
          consumed_at: string | null
          consumed_by_uid: string | null
          created_at: string | null
          created_by: string
          expires_at: string
          fleet_id: string
          id: string
          role: string | null
          token: string
        }
        Insert: {
          consumed_at?: string | null
          consumed_by_uid?: string | null
          created_at?: string | null
          created_by: string
          expires_at?: string
          fleet_id: string
          id?: string
          role?: string | null
          token: string
        }
        Update: {
          consumed_at?: string | null
          consumed_by_uid?: string | null
          created_at?: string | null
          created_by?: string
          expires_at?: string
          fleet_id?: string
          id?: string
          role?: string | null
          token?: string
        }
        Relationships: [
          {
            foreignKeyName: "fleet_invites_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
        ]
      }
      fleets: {
        Row: {
          created_at: string | null
          id: string
          name: string | null
          status: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          tier: Database["public"]["Enums"]["subscription_tier"]
          trial_end_date: string | null
          trial_start_date: string | null
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          id?: string
          name?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          tier?: Database["public"]["Enums"]["subscription_tier"]
          trial_end_date?: string | null
          trial_start_date?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          id?: string
          name?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          tier?: Database["public"]["Enums"]["subscription_tier"]
          trial_end_date?: string | null
          trial_start_date?: string | null
          updated_at?: string | null
        }
        Relationships: []
      }
      fuel_logs: {
        Row: {
          asset_id: string
          burn_rate_lph: number
          cost_per_liter: number
          created_at: string | null
          engine_hours_at_fill: number
          fleet_id: string
          haul_cycles_since_last_fill: number
          hours_elapsed: number
          id: string
          liters_filled: number
          notes: string | null
          operator_uid: string
          previous_engine_hours: number
          shift_id: string | null
          status: string
          tonnage_moved_since_last_fill: number
          total_cost: number
        }
        Insert: {
          asset_id: string
          burn_rate_lph: number
          cost_per_liter?: number
          created_at?: string | null
          engine_hours_at_fill: number
          fleet_id: string
          haul_cycles_since_last_fill?: number
          hours_elapsed: number
          id?: string
          liters_filled: number
          notes?: string | null
          operator_uid: string
          previous_engine_hours: number
          shift_id?: string | null
          status: string
          tonnage_moved_since_last_fill?: number
          total_cost: number
        }
        Update: {
          asset_id?: string
          burn_rate_lph?: number
          cost_per_liter?: number
          created_at?: string | null
          engine_hours_at_fill?: number
          fleet_id?: string
          haul_cycles_since_last_fill?: number
          hours_elapsed?: number
          id?: string
          liters_filled?: number
          notes?: string | null
          operator_uid?: string
          previous_engine_hours?: number
          shift_id?: string | null
          status?: string
          tonnage_moved_since_last_fill?: number
          total_cost?: number
        }
        Relationships: [
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
          {
            foreignKeyName: "fuel_logs_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shift_logs"
            referencedColumns: ["id"]
          },
        ]
      }
      handover_logs: {
        Row: {
          id: string
          incoming_user_id: string | null
          open_incidents_count: number | null
          outgoing_user_id: string | null
          project_id: string | null
          signature_timestamp: string | null
          signed_by_pin: boolean | null
        }
        Insert: {
          id?: string
          incoming_user_id?: string | null
          open_incidents_count?: number | null
          outgoing_user_id?: string | null
          project_id?: string | null
          signature_timestamp?: string | null
          signed_by_pin?: boolean | null
        }
        Update: {
          id?: string
          incoming_user_id?: string | null
          open_incidents_count?: number | null
          outgoing_user_id?: string | null
          project_id?: string | null
          signature_timestamp?: string | null
          signed_by_pin?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "handover_logs_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      haul_cycles: {
        Row: {
          asset_id: string
          completed_at: string | null
          cycle_duration_seconds: number | null
          dumped_at: string | null
          fleet_id: string
          id: string
          loaded_at: string | null
          material_id: string | null
          operator_uid: string
          route_id: string | null
          shift_id: string
          started_at: string
          state: string
          tonnage_moved: number | null
        }
        Insert: {
          asset_id: string
          completed_at?: string | null
          cycle_duration_seconds?: number | null
          dumped_at?: string | null
          fleet_id: string
          id?: string
          loaded_at?: string | null
          material_id?: string | null
          operator_uid: string
          route_id?: string | null
          shift_id: string
          started_at?: string
          state: string
          tonnage_moved?: number | null
        }
        Update: {
          asset_id?: string
          completed_at?: string | null
          cycle_duration_seconds?: number | null
          dumped_at?: string | null
          fleet_id?: string
          id?: string
          loaded_at?: string | null
          material_id?: string | null
          operator_uid?: string
          route_id?: string | null
          shift_id?: string
          started_at?: string
          state?: string
          tonnage_moved?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "haul_cycles_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "haul_cycles_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "haul_cycles_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
          {
            foreignKeyName: "haul_cycles_material_id_fkey"
            columns: ["material_id"]
            isOneToOne: false
            referencedRelation: "materials"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "haul_cycles_route_id_fkey"
            columns: ["route_id"]
            isOneToOne: false
            referencedRelation: "routes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "haul_cycles_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shift_logs"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          client_id: string
          created_at: string | null
          due_date: string
          fleet_id: string
          gst_amount: number
          id: string
          invoice_number: string
          status: string | null
          total_amount: number
          trip_id: string
        }
        Insert: {
          client_id: string
          created_at?: string | null
          due_date: string
          fleet_id: string
          gst_amount: number
          id?: string
          invoice_number: string
          status?: string | null
          total_amount: number
          trip_id: string
        }
        Update: {
          client_id?: string
          created_at?: string | null
          due_date?: string
          fleet_id?: string
          gst_amount?: number
          id?: string
          invoice_number?: string
          status?: string | null
          total_amount?: number
          trip_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_client"
            columns: ["client_id"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_trip"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      jit_active_queues: {
        Row: {
          asset_id: string
          id: string
          joined_queue_at: string | null
          project_id: string
          status: string | null
        }
        Insert: {
          asset_id: string
          id?: string
          joined_queue_at?: string | null
          project_id: string
          status?: string | null
        }
        Update: {
          asset_id?: string
          id?: string
          joined_queue_at?: string | null
          project_id?: string
          status?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "jit_active_queues_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      license_categories: {
        Row: {
          code: string
          description: string
          id: string
        }
        Insert: {
          code: string
          description: string
          id?: string
        }
        Update: {
          code?: string
          description?: string
          id?: string
        }
        Relationships: []
      }
      load_cycles: {
        Row: {
          asset_id: string
          completed_at: string | null
          created_at: string
          driver_id: string | null
          geological_block: string | null
          gross_weight: number | null
          id: string
          loading_started_at: string
          material_type: string
          net_weight: number | null
          project_id: string
          reconciled_by: string | null
          status: Database["public"]["Enums"]["cycle_status"]
          tare_weight: number | null
          transit_started_at: string | null
          updated_at: string
          weighbridge_operator_id: string | null
        }
        Insert: {
          asset_id: string
          completed_at?: string | null
          created_at?: string
          driver_id?: string | null
          geological_block?: string | null
          gross_weight?: number | null
          id?: string
          loading_started_at?: string
          material_type?: string
          net_weight?: number | null
          project_id: string
          reconciled_by?: string | null
          status?: Database["public"]["Enums"]["cycle_status"]
          tare_weight?: number | null
          transit_started_at?: string | null
          updated_at?: string
          weighbridge_operator_id?: string | null
        }
        Update: {
          asset_id?: string
          completed_at?: string | null
          created_at?: string
          driver_id?: string | null
          geological_block?: string | null
          gross_weight?: number | null
          id?: string
          loading_started_at?: string
          material_type?: string
          net_weight?: number | null
          project_id?: string
          reconciled_by?: string | null
          status?: Database["public"]["Enums"]["cycle_status"]
          tare_weight?: number | null
          transit_started_at?: string | null
          updated_at?: string
          weighbridge_operator_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "load_cycles_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "load_cycles_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "load_cycles_weighbridge_operator_id_fkey"
            columns: ["weighbridge_operator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      load_offers: {
        Row: {
          active_excavation: unknown
          anomaly_flag: string | null
          anomaly_resolution_reason: string | null
          anomaly_resolution_tags: string[] | null
          anomaly_resolved_at: string | null
          anomaly_resolved_by: string | null
          bypassed_by: string | null
          completed_at_local: string | null
          contractor_id: string
          crane_window_end: string
          crane_window_start: string
          created_at: string | null
          destination_lat: number
          destination_lng: number
          digital_bypass: boolean | null
          docket_image_path: string | null
          driver_id: string | null
          exclusion_zone: unknown
          id: string
          is_hazardous: boolean | null
          loaded_gross_mass: number | null
          master_order_id: string | null
          material_type: string | null
          max_turn_radius_m: number | null
          ocr_mass_extracted: number | null
          paper_docket_ref: string | null
          requires_4x4_traction: boolean | null
          staging_area: unknown
          status: string | null
          waste_certificate_id: string | null
        }
        Insert: {
          active_excavation?: unknown
          anomaly_flag?: string | null
          anomaly_resolution_reason?: string | null
          anomaly_resolution_tags?: string[] | null
          anomaly_resolved_at?: string | null
          anomaly_resolved_by?: string | null
          bypassed_by?: string | null
          completed_at_local?: string | null
          contractor_id: string
          crane_window_end: string
          crane_window_start: string
          created_at?: string | null
          destination_lat: number
          destination_lng: number
          digital_bypass?: boolean | null
          docket_image_path?: string | null
          driver_id?: string | null
          exclusion_zone?: unknown
          id?: string
          is_hazardous?: boolean | null
          loaded_gross_mass?: number | null
          master_order_id?: string | null
          material_type?: string | null
          max_turn_radius_m?: number | null
          ocr_mass_extracted?: number | null
          paper_docket_ref?: string | null
          requires_4x4_traction?: boolean | null
          staging_area?: unknown
          status?: string | null
          waste_certificate_id?: string | null
        }
        Update: {
          active_excavation?: unknown
          anomaly_flag?: string | null
          anomaly_resolution_reason?: string | null
          anomaly_resolution_tags?: string[] | null
          anomaly_resolved_at?: string | null
          anomaly_resolved_by?: string | null
          bypassed_by?: string | null
          completed_at_local?: string | null
          contractor_id?: string
          crane_window_end?: string
          crane_window_start?: string
          created_at?: string | null
          destination_lat?: number
          destination_lng?: number
          digital_bypass?: boolean | null
          docket_image_path?: string | null
          driver_id?: string | null
          exclusion_zone?: unknown
          id?: string
          is_hazardous?: boolean | null
          loaded_gross_mass?: number | null
          master_order_id?: string | null
          material_type?: string | null
          max_turn_radius_m?: number | null
          ocr_mass_extracted?: number | null
          paper_docket_ref?: string | null
          requires_4x4_traction?: boolean | null
          staging_area?: unknown
          status?: string | null
          waste_certificate_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "load_offers_anomaly_resolved_by_fkey"
            columns: ["anomaly_resolved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "load_offers_master_order_id_fkey"
            columns: ["master_order_id"]
            isOneToOne: false
            referencedRelation: "master_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_logs: {
        Row: {
          asset_id: string
          id: string
          issue_description: string
          locked_at: string
          locked_by_uid: string | null
          released_at: string | null
          released_by_uid: string | null
          resolution_notes: string | null
          status: Database["public"]["Enums"]["maintenance_status"]
        }
        Insert: {
          asset_id: string
          id?: string
          issue_description: string
          locked_at?: string
          locked_by_uid?: string | null
          released_at?: string | null
          released_by_uid?: string | null
          resolution_notes?: string | null
          status?: Database["public"]["Enums"]["maintenance_status"]
        }
        Update: {
          asset_id?: string
          id?: string
          issue_description?: string
          locked_at?: string
          locked_by_uid?: string | null
          released_at?: string | null
          released_by_uid?: string | null
          resolution_notes?: string | null
          status?: Database["public"]["Enums"]["maintenance_status"]
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "maintenance_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      maintenance_schedules: {
        Row: {
          asset_id: string
          created_at: string | null
          fleet_id: string
          id: string
          interval_km: number
          last_service_km: number
          service_type: string
          updated_at: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string | null
          fleet_id: string
          id?: string
          interval_km: number
          last_service_km: number
          service_type: string
          updated_at?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string | null
          fleet_id?: string
          id?: string
          interval_km?: number
          last_service_km?: number
          service_type?: string
          updated_at?: string | null
        }
        Relationships: []
      }
      master_orders: {
        Row: {
          created_at: string | null
          created_by: string | null
          destination_geofence: Json
          id: string
          material_type: string
          max_turn_radius_m: number | null
          origin_geofence: Json
          requires_4x4_traction: boolean | null
          status: string | null
          target_tonnage: number
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          destination_geofence: Json
          id?: string
          material_type: string
          max_turn_radius_m?: number | null
          origin_geofence: Json
          requires_4x4_traction?: boolean | null
          status?: string | null
          target_tonnage: number
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          destination_geofence?: Json
          id?: string
          material_type?: string
          max_turn_radius_m?: number | null
          origin_geofence?: Json
          requires_4x4_traction?: boolean | null
          status?: string | null
          target_tonnage?: number
        }
        Relationships: []
      }
      materials: {
        Row: {
          created_at: string | null
          density_kg_m3: number
          fleet_id: string
          id: string
          is_active: boolean | null
          name: string
        }
        Insert: {
          created_at?: string | null
          density_kg_m3: number
          fleet_id: string
          id?: string
          is_active?: boolean | null
          name: string
        }
        Update: {
          created_at?: string | null
          density_kg_m3?: number
          fleet_id?: string
          id?: string
          is_active?: boolean | null
          name?: string
        }
        Relationships: []
      }
      nhvr_compliance_logs: {
        Row: {
          asset_id: string
          declaration_timestamp: string | null
          defect_notes: string | null
          driver_id: string
          fleet_id: string
          id: string
          is_roadworthy: boolean
          manual_odometer_reading: number
        }
        Insert: {
          asset_id: string
          declaration_timestamp?: string | null
          defect_notes?: string | null
          driver_id: string
          fleet_id: string
          id?: string
          is_roadworthy: boolean
          manual_odometer_reading: number
        }
        Update: {
          asset_id?: string
          declaration_timestamp?: string | null
          defect_notes?: string | null
          driver_id?: string
          fleet_id?: string
          id?: string
          is_roadworthy?: boolean
          manual_odometer_reading?: number
        }
        Relationships: []
      }
      nodes: {
        Row: {
          created_at: string | null
          fleet_id: string | null
          has_diesel_active: boolean | null
          id: string
          latitude: number
          longitude: number
          name: string
          node_type: string
        }
        Insert: {
          created_at?: string | null
          fleet_id?: string | null
          has_diesel_active?: boolean | null
          id?: string
          latitude: number
          longitude: number
          name: string
          node_type: string
        }
        Update: {
          created_at?: string | null
          fleet_id?: string | null
          has_diesel_active?: boolean | null
          id?: string
          latitude?: number
          longitude?: number
          name?: string
          node_type?: string
        }
        Relationships: []
      }
      ocr_audit_logs: {
        Row: {
          created_at: string | null
          detected_document_type: string | null
          detected_expiry_date: string | null
          id: string
          is_fraud_flagged: boolean
          ocr_confidence_score: number | null
          override_id: string
          raw_ocr_dump: Json | null
          vision_model_version: string
        }
        Insert: {
          created_at?: string | null
          detected_document_type?: string | null
          detected_expiry_date?: string | null
          id?: string
          is_fraud_flagged?: boolean
          ocr_confidence_score?: number | null
          override_id: string
          raw_ocr_dump?: Json | null
          vision_model_version: string
        }
        Update: {
          created_at?: string | null
          detected_document_type?: string | null
          detected_expiry_date?: string | null
          id?: string
          is_fraud_flagged?: boolean
          ocr_confidence_score?: number | null
          override_id?: string
          raw_ocr_dump?: Json | null
          vision_model_version?: string
        }
        Relationships: [
          {
            foreignKeyName: "ocr_audit_logs_override_id_fkey"
            columns: ["override_id"]
            isOneToOne: false
            referencedRelation: "whs_overrides"
            referencedColumns: ["id"]
          },
        ]
      }
      plant_defects: {
        Row: {
          asset_id: string
          category: Database["public"]["Enums"]["defect_category"] | null
          created_at: string
          defect_description: string
          id: string
          project_id: string
          rectified_at: string | null
          rectified_by: string | null
          reported_at: string
          reported_by: string
          resolution_notes: string | null
          status: Database["public"]["Enums"]["defect_status"]
          updated_at: string
        }
        Insert: {
          asset_id: string
          category?: Database["public"]["Enums"]["defect_category"] | null
          created_at?: string
          defect_description: string
          id?: string
          project_id: string
          rectified_at?: string | null
          rectified_by?: string | null
          reported_at?: string
          reported_by: string
          resolution_notes?: string | null
          status?: Database["public"]["Enums"]["defect_status"]
          updated_at?: string
        }
        Update: {
          asset_id?: string
          category?: Database["public"]["Enums"]["defect_category"] | null
          created_at?: string
          defect_description?: string
          id?: string
          project_id?: string
          rectified_at?: string | null
          rectified_by?: string | null
          reported_at?: string
          reported_by?: string
          resolution_notes?: string | null
          status?: Database["public"]["Enums"]["defect_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "plant_defects_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plant_defects_rectified_by_fkey"
            columns: ["rectified_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plant_defects_reported_by_fkey"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prestart_checks: {
        Row: {
          assignment_id: string
          brakes_checked: boolean
          defect_notes: string | null
          fluids_checked: boolean
          id: string
          inspection_completed_at: string
          inspection_started_at: string
          is_safe_to_operate: boolean
          operator_id: string
          structural_checked: boolean
        }
        Insert: {
          assignment_id: string
          brakes_checked?: boolean
          defect_notes?: string | null
          fluids_checked?: boolean
          id?: string
          inspection_completed_at?: string
          inspection_started_at: string
          is_safe_to_operate: boolean
          operator_id: string
          structural_checked?: boolean
        }
        Update: {
          assignment_id?: string
          brakes_checked?: boolean
          defect_notes?: string | null
          fluids_checked?: boolean
          id?: string
          inspection_completed_at?: string
          inspection_started_at?: string
          is_safe_to_operate?: boolean
          operator_id?: string
          structural_checked?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "prestart_checks_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "asset_assignments"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          created_at: string | null
          fleet_id: string
          full_name: string | null
          hashed_pin: string | null
          id: string
          insurance_expiry_date: string | null
          insurance_policy_number: string | null
          is_verified: boolean | null
          operational_pin_hash: string | null
          operational_pin_salt: string | null
          pin_failed_attempts: number | null
          pin_hash: string | null
          pin_locked_until: string | null
          role: string
          status: string | null
          updated_at: string | null
          insurance_compliant: boolean | null
        }
        Insert: {
          created_at?: string | null
          fleet_id?: string
          full_name?: string | null
          hashed_pin?: string | null
          id: string
          insurance_expiry_date?: string | null
          insurance_policy_number?: string | null
          is_verified?: boolean | null
          operational_pin_hash?: string | null
          operational_pin_salt?: string | null
          pin_failed_attempts?: number | null
          pin_hash?: string | null
          pin_locked_until?: string | null
          role: string
          status?: string | null
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          fleet_id?: string
          full_name?: string | null
          hashed_pin?: string | null
          id?: string
          insurance_expiry_date?: string | null
          insurance_policy_number?: string | null
          is_verified?: boolean | null
          operational_pin_hash?: string | null
          operational_pin_salt?: string | null
          pin_failed_attempts?: number | null
          pin_hash?: string | null
          pin_locked_until?: string | null
          role?: string
          status?: string | null
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_profiles_fleet_id"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
        ]
      }
      project_members: {
        Row: {
          project_id: string
          role: string | null
          user_id: string
        }
        Insert: {
          project_id: string
          role?: string | null
          user_id: string
        }
        Update: {
          project_id?: string
          role?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "project_members_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          client_name: string | null
          created_at: string | null
          estimated_end_date: string | null
          hrcw_polygon: unknown
          id: string
          loading_pad_buffered: unknown
          loading_pad_geometry: unknown
          name: string
          project_type: string | null
          start_date: string | null
          status: string | null
        }
        Insert: {
          client_name?: string | null
          created_at?: string | null
          estimated_end_date?: string | null
          hrcw_polygon?: unknown
          id?: string
          loading_pad_buffered?: unknown
          loading_pad_geometry?: unknown
          name: string
          project_type?: string | null
          start_date?: string | null
          status?: string | null
        }
        Update: {
          client_name?: string | null
          created_at?: string | null
          estimated_end_date?: string | null
          hrcw_polygon?: unknown
          id?: string
          loading_pad_buffered?: unknown
          loading_pad_geometry?: unknown
          name?: string
          project_type?: string | null
          start_date?: string | null
          status?: string | null
        }
        Relationships: []
      }
      role_audit_logs: {
        Row: {
          action_type: string | null
          granted_at: string | null
          granted_by_user_id: string
          id: string
          justification: string
          new_role: string
          previous_role: string
          target_user_id: string
        }
        Insert: {
          action_type?: string | null
          granted_at?: string | null
          granted_by_user_id: string
          id?: string
          justification: string
          new_role: string
          previous_role: string
          target_user_id: string
        }
        Update: {
          action_type?: string | null
          granted_at?: string | null
          granted_by_user_id?: string
          id?: string
          justification?: string
          new_role?: string
          previous_role?: string
          target_user_id?: string
        }
        Relationships: []
      }
      routes: {
        Row: {
          created_at: string | null
          destination_zone: string
          est_duration_minutes: number | null
          fleet_id: string
          id: string
          is_active: boolean | null
          name: string
          origin_zone: string
        }
        Insert: {
          created_at?: string | null
          destination_zone: string
          est_duration_minutes?: number | null
          fleet_id: string
          id?: string
          is_active?: boolean | null
          name: string
          origin_zone: string
        }
        Update: {
          created_at?: string | null
          destination_zone?: string
          est_duration_minutes?: number | null
          fleet_id?: string
          id?: string
          is_active?: boolean | null
          name?: string
          origin_zone?: string
        }
        Relationships: []
      }
      service_logs: {
        Row: {
          asset_id: string
          created_at: string | null
          fleet_id: string
          id: string
          invoice_url: string | null
          is_verified: boolean | null
          mechanic_node_id: string
          service_date: string
          updated_at: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string | null
          fleet_id: string
          id?: string
          invoice_url?: string | null
          is_verified?: boolean | null
          mechanic_node_id: string
          service_date: string
          updated_at?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string | null
          fleet_id?: string
          id?: string
          invoice_url?: string | null
          is_verified?: boolean | null
          mechanic_node_id?: string
          service_date?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_mechanic_node"
            columns: ["mechanic_node_id"]
            isOneToOne: false
            referencedRelation: "nodes"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_assignments: {
        Row: {
          assigned_by: string | null
          created_at: string | null
          detach_reason: string | null
          driver_id: string | null
          id: string
          intent_to_detach: boolean | null
          master_order_id: string | null
          status: string | null
          vehicle_id: string | null
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string | null
          detach_reason?: string | null
          driver_id?: string | null
          id?: string
          intent_to_detach?: boolean | null
          master_order_id?: string | null
          status?: string | null
          vehicle_id?: string | null
        }
        Update: {
          assigned_by?: string | null
          created_at?: string | null
          detach_reason?: string | null
          driver_id?: string | null
          id?: string
          intent_to_detach?: boolean | null
          master_order_id?: string | null
          status?: string | null
          vehicle_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shift_assignments_master_order_id_fkey"
            columns: ["master_order_id"]
            isOneToOne: false
            referencedRelation: "master_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      shift_logs: {
        Row: {
          accumulated_break_seconds: number
          accumulated_work_seconds: number
          asset_id: string | null
          continuous_work_seconds: number
          created_at: string | null
          ended_at: string | null
          fleet_id: string
          id: string
          last_state_change_at: string
          operator_uid: string
          started_at: string
          status: string
        }
        Insert: {
          accumulated_break_seconds?: number
          accumulated_work_seconds?: number
          asset_id?: string | null
          continuous_work_seconds?: number
          created_at?: string | null
          ended_at?: string | null
          fleet_id: string
          id?: string
          last_state_change_at?: string
          operator_uid: string
          started_at?: string
          status: string
        }
        Update: {
          accumulated_break_seconds?: number
          accumulated_work_seconds?: number
          asset_id?: string | null
          continuous_work_seconds?: number
          created_at?: string | null
          ended_at?: string | null
          fleet_id?: string
          id?: string
          last_state_change_at?: string
          operator_uid?: string
          started_at?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "shift_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "shift_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      sos_alerts: {
        Row: {
          asset_id: string
          created_at: string | null
          diagnostic_type: string
          fleet_id: string
          id: string
          latitude: number
          longitude: number
          status: string | null
          trip_id: string
          updated_at: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string | null
          diagnostic_type: string
          fleet_id: string
          id?: string
          latitude: number
          longitude: number
          status?: string | null
          trip_id: string
          updated_at?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string | null
          diagnostic_type?: string
          fleet_id?: string
          id?: string
          latitude?: number
          longitude?: number
          status?: string | null
          trip_id?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_trip"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      spatial_ref_sys: {
        Row: {
          auth_name: string | null
          auth_srid: number | null
          proj4text: string | null
          srid: number
          srtext: string | null
        }
        Insert: {
          auth_name?: string | null
          auth_srid?: number | null
          proj4text?: string | null
          srid: number
          srtext?: string | null
        }
        Update: {
          auth_name?: string | null
          auth_srid?: number | null
          proj4text?: string | null
          srid?: number
          srtext?: string | null
        }
        Relationships: []
      }
      structural_elements: {
        Row: {
          bim_guid: string
          element_type: string
          id: string
          length_mm: number
          load_offer_id: string | null
          weight_kg: number
          width_mm: number
        }
        Insert: {
          bim_guid: string
          element_type: string
          id?: string
          length_mm: number
          load_offer_id?: string | null
          weight_kg: number
          width_mm: number
        }
        Update: {
          bim_guid?: string
          element_type?: string
          id?: string
          length_mm?: number
          load_offer_id?: string | null
          weight_kg?: number
          width_mm?: number
        }
        Relationships: [
          {
            foreignKeyName: "structural_elements_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "load_offers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "structural_elements_load_offer_id_fkey"
            columns: ["load_offer_id"]
            isOneToOne: false
            referencedRelation: "view_cor_audit_timeline"
            referencedColumns: ["load_id"]
          },
        ]
      }
      system_audit_logs: {
        Row: {
          action_type: string
          actor_role: string | null
          actor_uid: string | null
          client_ip: string | null
          created_at: string | null
          id: string
          payload_after: Json | null
          payload_before: Json | null
          target_record_id: string | null
          target_table: string
        }
        Insert: {
          action_type: string
          actor_role?: string | null
          actor_uid?: string | null
          client_ip?: string | null
          created_at?: string | null
          id?: string
          payload_after?: Json | null
          payload_before?: Json | null
          target_record_id?: string | null
          target_table: string
        }
        Update: {
          action_type?: string
          actor_role?: string | null
          actor_uid?: string | null
          client_ip?: string | null
          created_at?: string | null
          id?: string
          payload_after?: Json | null
          payload_before?: Json | null
          target_record_id?: string | null
          target_table?: string
        }
        Relationships: []
      }
      system_config: {
        Row: {
          key: string
          updated_at: string | null
          value: Json
        }
        Insert: {
          key: string
          updated_at?: string | null
          value: Json
        }
        Update: {
          key?: string
          updated_at?: string | null
          value?: Json
        }
        Relationships: []
      }
      telemetry_dead_letter_logs: {
        Row: {
          asset_id: string | null
          client_timestamp: string | null
          created_at: string | null
          error_code: string | null
          error_message: string | null
          event_type: string | null
          id: string
          payload: Json | null
          recorded_by: string | null
        }
        Insert: {
          asset_id?: string | null
          client_timestamp?: string | null
          created_at?: string | null
          error_code?: string | null
          error_message?: string | null
          event_type?: string | null
          id?: string
          payload?: Json | null
          recorded_by?: string | null
        }
        Update: {
          asset_id?: string | null
          client_timestamp?: string | null
          created_at?: string | null
          error_code?: string | null
          error_message?: string | null
          event_type?: string | null
          id?: string
          payload?: Json | null
          recorded_by?: string | null
        }
        Relationships: []
      }
      telemetry_inbox: {
        Row: {
          asset_id: string
          client_timestamp: string
          created_at: string | null
          id: string
          payload: Json
          recorded_by: string
        }
        Insert: {
          asset_id: string
          client_timestamp: string
          created_at?: string | null
          id?: string
          payload: Json
          recorded_by: string
        }
        Update: {
          asset_id?: string
          client_timestamp?: string
          created_at?: string | null
          id?: string
          payload?: Json
          recorded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "telemetry_inbox_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      telemetry_logs: {
        Row: {
          asset_id: string
          coolant_temp_celsius: number | null
          created_at: string | null
          engine_hours: number
          fuel_level_percent: number | null
          id: string
          is_engine_running: boolean
          recorded_at: string
        }
        Insert: {
          asset_id: string
          coolant_temp_celsius?: number | null
          created_at?: string | null
          engine_hours: number
          fuel_level_percent?: number | null
          id?: string
          is_engine_running?: boolean
          recorded_at?: string
        }
        Update: {
          asset_id?: string
          coolant_temp_celsius?: number | null
          created_at?: string | null
          engine_hours?: number
          fuel_level_percent?: number | null
          id?: string
          is_engine_running?: boolean
          recorded_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "telemetry_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "telemetry_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "telemetry_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      trip_waypoints: {
        Row: {
          estimated_arrival: string
          fleet_id: string
          id: string
          node_id: string
          trip_id: string
          waypoint_order: number
          waypoint_type: string
        }
        Insert: {
          estimated_arrival: string
          fleet_id: string
          id?: string
          node_id: string
          trip_id: string
          waypoint_order: number
          waypoint_type: string
        }
        Update: {
          estimated_arrival?: string
          fleet_id?: string
          id?: string
          node_id?: string
          trip_id?: string
          waypoint_order?: number
          waypoint_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_node"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "nodes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_trip"
            columns: ["trip_id"]
            isOneToOne: false
            referencedRelation: "trips"
            referencedColumns: ["id"]
          },
        ]
      }
      trips: {
        Row: {
          asset_id: string
          created_at: string | null
          driver_id: string | null
          estimated_fuel_required: number
          fleet_id: string
          id: string
          scheduled_start: string
          status: string | null
          total_distance_km: number
          updated_at: string | null
        }
        Insert: {
          asset_id: string
          created_at?: string | null
          driver_id?: string | null
          estimated_fuel_required: number
          fleet_id: string
          id?: string
          scheduled_start: string
          status?: string | null
          total_distance_km: number
          updated_at?: string | null
        }
        Update: {
          asset_id?: string
          created_at?: string | null
          driver_id?: string | null
          estimated_fuel_required?: number
          fleet_id?: string
          id?: string
          scheduled_start?: string
          status?: string | null
          total_distance_km?: number
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_driver"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      vehicles: {
        Row: {
          created_at: string | null
          gvm_limit: number
          id: string
          profile_id: string
          registration_plate: string
          tare_weight: number
        }
        Insert: {
          created_at?: string | null
          gvm_limit: number
          id?: string
          profile_id: string
          registration_plate: string
          tare_weight: number
        }
        Update: {
          created_at?: string | null
          gvm_limit?: number
          id?: string
          profile_id?: string
          registration_plate?: string
          tare_weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "vehicles_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_endpoints: {
        Row: {
          auth_secret: string | null
          created_at: string | null
          event_type: string
          fleet_id: string
          id: string
          is_active: boolean | null
          target_url: string
        }
        Insert: {
          auth_secret?: string | null
          created_at?: string | null
          event_type: string
          fleet_id: string
          id?: string
          is_active?: boolean | null
          target_url: string
        }
        Update: {
          auth_secret?: string | null
          created_at?: string | null
          event_type?: string
          fleet_id?: string
          id?: string
          is_active?: boolean | null
          target_url?: string
        }
        Relationships: [
          {
            foreignKeyName: "webhook_endpoints_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
        ]
      }
      webhook_events: {
        Row: {
          created_at: string | null
          error_message: string | null
          event_type: string
          id: string
          next_retry_at: string | null
          payload: Json
          request_id: number | null
          retry_count: number | null
          status: string | null
        }
        Insert: {
          created_at?: string | null
          error_message?: string | null
          event_type: string
          id?: string
          next_retry_at?: string | null
          payload?: Json
          request_id?: number | null
          retry_count?: number | null
          status?: string | null
        }
        Update: {
          created_at?: string | null
          error_message?: string | null
          event_type?: string
          id?: string
          next_retry_at?: string | null
          payload?: Json
          request_id?: number | null
          retry_count?: number | null
          status?: string | null
        }
        Relationships: []
      }
      whs_overrides: {
        Row: {
          document_path: string
          driver_id: string
          id: string
          new_expiry_date: string
          override_timestamp: string | null
          supervisor_id: string
        }
        Insert: {
          document_path: string
          driver_id: string
          id?: string
          new_expiry_date: string
          override_timestamp?: string | null
          supervisor_id: string
        }
        Update: {
          document_path?: string
          driver_id?: string
          id?: string
          new_expiry_date?: string
          override_timestamp?: string | null
          supervisor_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "whs_overrides_driver_id_fkey"
            columns: ["driver_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whs_overrides_supervisor_id_fkey"
            columns: ["supervisor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      whs_prestart_logs: {
        Row: {
          asset_id: string
          checklist_data: Json
          client_timestamp: string
          defect_notes: Json | null
          fleet_id: string
          id: string
          operator_uid: string
          passed: boolean
          server_timestamp: string | null
        }
        Insert: {
          asset_id: string
          checklist_data: Json
          client_timestamp: string
          defect_notes?: Json | null
          fleet_id: string
          id?: string
          operator_uid: string
          passed: boolean
          server_timestamp?: string | null
        }
        Update: {
          asset_id?: string
          checklist_data?: Json
          client_timestamp?: string
          defect_notes?: Json | null
          fleet_id?: string
          id?: string
          operator_uid?: string
          passed?: boolean
          server_timestamp?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "whs_prestart_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whs_prestart_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "whs_prestart_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      whs_prestarts: {
        Row: {
          asset_id: string
          checklist_data: Json
          client_timestamp: string
          created_at: string | null
          defect_notes: Json | null
          id: string
          operator_id: string
          passed: boolean
        }
        Insert: {
          asset_id: string
          checklist_data: Json
          client_timestamp: string
          created_at?: string | null
          defect_notes?: Json | null
          id?: string
          operator_id: string
          passed: boolean
        }
        Update: {
          asset_id?: string
          checklist_data?: Json
          client_timestamp?: string
          created_at?: string | null
          defect_notes?: Json | null
          id?: string
          operator_id?: string
          passed?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "whs_prestarts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "whs_prestarts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "whs_prestarts_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
          {
            foreignKeyName: "whs_prestarts_operator_id_fkey"
            columns: ["operator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      geography_columns: {
        Row: {
          coord_dimension: number | null
          f_geography_column: unknown
          f_table_catalog: unknown
          f_table_name: unknown
          f_table_schema: unknown
          srid: number | null
          type: string | null
        }
        Relationships: []
      }
      geometry_columns: {
        Row: {
          coord_dimension: number | null
          f_geometry_column: unknown
          f_table_catalog: string | null
          f_table_name: unknown
          f_table_schema: unknown
          srid: number | null
          type: string | null
        }
        Insert: {
          coord_dimension?: number | null
          f_geometry_column?: unknown
          f_table_catalog?: string | null
          f_table_name?: unknown
          f_table_schema?: unknown
          srid?: number | null
          type?: string | null
        }
        Update: {
          coord_dimension?: number | null
          f_geometry_column?: unknown
          f_table_catalog?: string | null
          f_table_name?: unknown
          f_table_schema?: unknown
          srid?: number | null
          type?: string | null
        }
        Relationships: []
      }
      mv_ato_fuel_rebate_ledger: {
        Row: {
          asset_id: string | null
          asset_name: string | null
          asset_type: Database["public"]["Enums"]["asset_category"] | null
          avg_burn_rate_lph: number | null
          estimated_ato_rebate_aud: number | null
          fleet_id: string | null
          last_refuel_timestamp: string | null
          total_aud_spent: number | null
          total_liters_injected: number | null
          total_refuels: number | null
          total_tonnage_associated: number | null
        }
        Relationships: [
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "mv_predictive_maintenance_roster"
            referencedColumns: ["asset_id"]
          },
          {
            foreignKeyName: "fuel_logs_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
      }
      mv_daily_cycle_efficiency: {
        Row: {
          asset_id: string | null
          avg_loading_minutes: number | null
          date: string | null
          project_id: string | null
          total_cycles: number | null
        }
        Relationships: [
          {
            foreignKeyName: "load_cycles_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_daily_fleet_downtime: {
        Row: {
          asset_id: string | null
          date: string | null
          project_id: string | null
          total_defects: number | null
          total_downtime_hours: number | null
        }
        Relationships: [
          {
            foreignKeyName: "plant_defects_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_daily_production_tonnage: {
        Row: {
          date: string | null
          geological_block: string | null
          material_type: string | null
          project_id: string | null
          total_loads: number | null
          total_net_weight: number | null
        }
        Relationships: [
          {
            foreignKeyName: "load_cycles_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_predictive_maintenance_roster: {
        Row: {
          active_danger_tags_count: number | null
          asset_id: string | null
          asset_name: string | null
          current_engine_hours: number | null
          current_whs_status: Database["public"]["Enums"]["asset_status"] | null
          fleet_id: string | null
          hours_until_next_service: number | null
          maintenance_priority: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assets_fleet_id_fkey"
            columns: ["fleet_id"]
            isOneToOne: false
            referencedRelation: "fleets"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_whs_compliance_audit: {
        Row: {
          avg_continuous_drive_hours: number | null
          fatigue_lockouts_triggered: number | null
          fleet_id: string | null
          last_shift_start: string | null
          operator_name: string | null
          operator_uid: string | null
          total_shifts_worked: number | null
          total_work_hours: number | null
        }
        Relationships: []
      }
      secure_daily_cycle_efficiency: {
        Row: {
          asset_id: string | null
          avg_loading_minutes: number | null
          date: string | null
          project_id: string | null
          total_cycles: number | null
        }
        Relationships: [
          {
            foreignKeyName: "load_cycles_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      secure_daily_fleet_downtime: {
        Row: {
          asset_id: string | null
          date: string | null
          project_id: string | null
          total_defects: number | null
          total_downtime_hours: number | null
        }
        Relationships: [
          {
            foreignKeyName: "plant_defects_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      secure_daily_production_tonnage: {
        Row: {
          date: string | null
          geological_block: string | null
          material_type: string | null
          project_id: string | null
          total_loads: number | null
          total_net_weight: number | null
        }
        Relationships: [
          {
            foreignKeyName: "load_cycles_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
        ]
      }
      view_cor_audit_timeline: {
        Row: {
          anomaly_flag: string | null
          anomaly_resolution_reason: string | null
          anomaly_resolution_tags: string[] | null
          bypassed_by_name: string | null
          completed_at_local: string | null
          created_at: string | null
          digital_bypass: boolean | null
          docket_image_path: string | null
          load_id: string | null
          operator_id: string | null
          paper_docket_ref: string | null
          resolved_at: string | null
          status: string | null
        }
        Relationships: []
      }
      view_driver_fatigue: {
        Row: {
          driver_id: string | null
          hours_active: number | null
          shift_start: string | null
          trips_today: number | null
        }
        Relationships: []
      }
      view_fleet_matrix: {
        Row: {
          registration_number: string | null
          status: Database["public"]["Enums"]["asset_status"] | null
          vehicle_id: string | null
        }
        Insert: {
          registration_number?: string | null
          status?: Database["public"]["Enums"]["asset_status"] | null
          vehicle_id?: string | null
        }
        Update: {
          registration_number?: string | null
          status?: Database["public"]["Enums"]["asset_status"] | null
          vehicle_id?: string | null
        }
        Relationships: []
      }
      view_project_progress: {
        Row: {
          material_type: string | null
          total_mass_delivered_kg: number | null
          total_trips: number | null
        }
        Relationships: []
      }
      view_site_bottlenecks: {
        Row: {
          active_trucks: number | null
          avg_cycle_time_mins: number | null
          geofence_zone: unknown
        }
        Relationships: []
      }
    }
    Functions: {
      _postgis_deprecate: {
        Args: { newname: string; oldname: string; version: string }
        Returns: undefined
      }
      _postgis_index_extent: {
        Args: { col: string; tbl: unknown }
        Returns: unknown
      }
      _postgis_pgsql_version: { Args: never; Returns: string }
      _postgis_scripts_pgsql_version: { Args: never; Returns: string }
      _postgis_selectivity: {
        Args: { att_name: string; geom: unknown; mode?: string; tbl: unknown }
        Returns: number
      }
      _postgis_stats: {
        Args: { ""?: string; att_name: string; tbl: unknown }
        Returns: string
      }
      _st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_crosses: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_dwithin: {
        Args: {
          geog1: unknown
          geog2: unknown
          tolerance: number
          use_spheroid?: boolean
        }
        Returns: boolean
      }
      _st_equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      _st_intersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown }
        Returns: number
      }
      _st_longestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      _st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      _st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_sortablehash: { Args: { geom: unknown }; Returns: number }
      _st_touches: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      _st_voronoi: {
        Args: {
          clip?: unknown
          g1: unknown
          return_polygons?: boolean
          tolerance?: number
        }
        Returns: unknown
      }
      _st_within: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      active_excavation_geojson: {
        Args: { offer: Database["public"]["Tables"]["load_offers"]["Row"] }
        Returns: Json
      }
      addauth: { Args: { "": string }; Returns: boolean }
      addgeometrycolumn:
        | {
            Args: {
              catalog_name: string
              column_name: string
              new_dim: number
              new_srid_in: number
              new_type: string
              schema_name: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              new_dim: number
              new_srid: number
              new_type: string
              schema_name: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              new_dim: number
              new_srid: number
              new_type: string
              table_name: string
              use_typmod?: boolean
            }
            Returns: string
          }
      audit_the_ocr_auditor: { Args: never; Returns: undefined }
      calculate_fleet_health_scores: {
        Args: { p_fleet_id: string }
        Returns: {
          asset_id: string
          critical_warnings: number
          health_score: number
          internal_code: string
          predicted_failure_days: number
        }[]
      }
      certify_prestart: {
        Args: {
          p_assignment_id: string
          p_brakes: boolean
          p_defect_notes: string
          p_fluids: boolean
          p_is_safe: boolean
          p_structural: boolean
        }
        Returns: undefined
      }
      close_active_shift: { Args: { p_assignment_id: string }; Returns: Json }
      custom_access_token_hook: { Args: { event: Json }; Returns: Json }
      disablelongtransactions: { Args: never; Returns: string }
      dropgeometrycolumn:
        | {
            Args: {
              catalog_name: string
              column_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | {
            Args: {
              column_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | { Args: { column_name: string; table_name: string }; Returns: string }
      dropgeometrytable:
        | {
            Args: {
              catalog_name: string
              schema_name: string
              table_name: string
            }
            Returns: string
          }
        | { Args: { schema_name: string; table_name: string }; Returns: string }
        | { Args: { table_name: string }; Returns: string }
      earth: { Args: never; Returns: number }
      emergency_reset_mfa: {
        Args: { p_target_uid: string }
        Returns: undefined
      }
      enablelongtransactions: { Args: never; Returns: string }
      equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      exclusion_zone_geojson: {
        Args: { offer: Database["public"]["Tables"]["load_offers"]["Row"] }
        Returns: Json
      }
      execute_instant_revocation: {
        Args: { p_forensic_reason: string; p_target_uid: string }
        Returns: Json
      }
      fitter_lock_asset: {
        Args: { p_asset_id: string; p_issue: string }
        Returns: string
      }
      fitter_release_asset: {
        Args: { p_log_id: string; p_resolution: string }
        Returns: undefined
      }
      fn_assign_asset_to_project: {
        Args: {
          p_asset_id: string
          p_driver_id: string
          p_load_offer_id: string
        }
        Returns: boolean
      }
      fn_consume_fleet_invite: { Args: { p_token: string }; Returns: Json }
      fn_dispatch_shift: {
        Args: {
          p_asset_id: string
          p_driver_id: string
          p_master_order_id: string
        }
        Returns: string
      }
      fn_elevate_user_role: {
        Args: {
          p_justification: string
          p_new_role: string
          p_target_id: string
        }
        Returns: string
      }
      fn_execute_haul_transition: {
        Args: {
          p_action: string
          p_asset_id: string
          p_material_id?: string
          p_route_id?: string
        }
        Returns: Json
      }
      fn_execute_shift_action: {
        Args: { p_action: string; p_asset_id?: string }
        Returns: Json
      }
      fn_export_regulatory_report: {
        Args: { p_report_type: string }
        Returns: Json
      }
      fn_generate_fleet_invite: {
        Args: { p_fleet_id: string }
        Returns: string
      }
      fn_get_caller_fleet_id: { Args: never; Returns: string }
      fn_inject_retroactive_docket: {
        Args: {
          p_docket_image_path: string
          p_driver_id: string
          p_loaded_gross_mass: number
          p_master_order_id: string
          p_paper_docket_ref: string
        }
        Returns: string
      }
      fn_override_pin_lockout: {
        Args: { p_target_operator_uid: string }
        Returns: Json
      }
      fn_override_shift_assignment: {
        Args: { p_absent_driver_id: string; p_reserve_driver_id: string }
        Returns: boolean
      }
      fn_release_asset_lockout: {
        Args: {
          p_asset_id: string
          p_fitter_pin: string
          p_resolution_notes: string
        }
        Returns: Json
      }
      fn_request_detach:
        | { Args: { p_reason: string }; Returns: undefined }
        | { Args: { p_reason: string; p_shift_id: string }; Returns: undefined }
      fn_revoke_driver_access: {
        Args: { p_driver_id: string }
        Returns: boolean
      }
      fn_revoke_user_role: {
        Args: {
          p_justification: string
          p_new_role: string
          p_target_id: string
        }
        Returns: string
      }
      fn_set_operator_pin: { Args: { p_pin: string }; Returns: Json }
      fn_simulate_payment_success: {
        Args: { p_amount_due: number; p_fleet_id: string }
        Returns: Json
      }
      fn_submit_fuel_log:
        | {
            Args: {
              p_asset_id: string
              p_cost_per_liter?: number
              p_engine_hours: number
              p_liters_filled: number
              p_location_tag?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_asset_id: string
              p_cost_per_liter?: number
              p_engine_hours: number
              p_liters_filled: number
              p_notes?: string
            }
            Returns: Json
          }
      fn_submit_whs_prestart: {
        Args: {
          p_asset_id: string
          p_checklist_data: Json
          p_client_timestamp: string
          p_defect_notes: Json
          p_passed: boolean
        }
        Returns: Json
      }
      fn_sweep_orphan_evidence: { Args: never; Returns: undefined }
      fn_verify_driver_insurance: {
        Args: {
          p_driver_id: string
          p_expiry_date: string
          p_file_path: string
        }
        Returns: boolean
      }
      fn_verify_operator_pin: { Args: { p_pin: string }; Returns: Json }
      force_close_shift: {
        Args: { p_assignment_id: string; p_reason: string }
        Returns: undefined
      }
      geometry: { Args: { "": string }; Returns: unknown }
      geometry_above: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_below: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_cmp: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_contained_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_contains_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_distance_box: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_distance_centroid: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      geometry_eq: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_ge: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_gt: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_le: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_left: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_lt: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overabove: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overbelow: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overlaps_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overleft: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_overright: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_right: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_same: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_same_3d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geometry_within: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      geomfromewkt: { Args: { "": string }; Returns: unknown }
      get_admin_business_metrics: {
        Args: never
        Returns: {
          active_projects: number
          active_users: number
          projected_mrr: number
        }[]
      }
      get_auth_user_fleet_id: { Args: never; Returns: string }
      get_auth_user_role: { Args: never; Returns: string }
      get_fleet_friction_metrics: {
        Args: { p_fleet_id: string }
        Returns: Json
      }
      get_offer_chronology: {
        Args: { offer_uuid: string }
        Returns: {
          action: string
          id: string
          row_id: string
          table_name: string
          timestamp: string | null
          user_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "access_logs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      gettransactionid: { Args: never; Returns: unknown }
      insurance_compliant: {
        Args: { "": Database["public"]["Tables"]["profiles"]["Row"] }
        Returns: {
          error: true
        } & "the function public.insurance_compliant with parameter or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache"
      }
      join_jit_queue: { Args: { p_asset_id: string }; Returns: undefined }
      leave_jit_queue: { Args: { p_asset_id: string }; Returns: undefined }
      lock_asset_preventively: {
        Args: { p_asset_id: string; p_reason: string }
        Returns: undefined
      }
      longtransactionsenabled: { Args: never; Returns: boolean }
      mark_prestart_commenced: {
        Args: { p_assignment_id: string }
        Returns: undefined
      }
      matches_contractor_profile: {
        Args: { driver_uuid: string; offer_id: string }
        Returns: boolean
      }
      populate_geometry_columns:
        | { Args: { tbl_oid: unknown; use_typmod?: boolean }; Returns: number }
        | { Args: { use_typmod?: boolean }; Returns: string }
      postgis_constraint_dims: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: number
      }
      postgis_constraint_srid: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: number
      }
      postgis_constraint_type: {
        Args: { geomcolumn: string; geomschema: string; geomtable: string }
        Returns: string
      }
      postgis_extensions_upgrade: { Args: never; Returns: string }
      postgis_full_version: { Args: never; Returns: string }
      postgis_geos_version: { Args: never; Returns: string }
      postgis_lib_build_date: { Args: never; Returns: string }
      postgis_lib_revision: { Args: never; Returns: string }
      postgis_lib_version: { Args: never; Returns: string }
      postgis_libjson_version: { Args: never; Returns: string }
      postgis_liblwgeom_version: { Args: never; Returns: string }
      postgis_libprotobuf_version: { Args: never; Returns: string }
      postgis_libxml_version: { Args: never; Returns: string }
      postgis_proj_version: { Args: never; Returns: string }
      postgis_scripts_build_date: { Args: never; Returns: string }
      postgis_scripts_installed: { Args: never; Returns: string }
      postgis_scripts_released: { Args: never; Returns: string }
      postgis_svn_version: { Args: never; Returns: string }
      postgis_type_name: {
        Args: {
          coord_dimension: number
          geomname: string
          use_new_name?: boolean
        }
        Returns: string
      }
      postgis_version: { Args: never; Returns: string }
      postgis_wagyu_version: { Args: never; Returns: string }
      process_quarantined_expense: {
        Args: {
          p_corrected_amount: number
          p_expense_id: string
          p_notes: string
          p_status: string
        }
        Returns: undefined
      }
      process_webhook_responses: { Args: never; Returns: undefined }
      reconcile_load_cycle: {
        Args: {
          p_cycle_id: string
          p_gross_weight: number
          p_tare_weight: number
        }
        Returns: Json
      }
      refresh_managerial_kpis: { Args: never; Returns: undefined }
      release_asset_from_maintenance: {
        Args: { p_asset_id: string; p_release_notes: string }
        Returns: undefined
      }
      report_incident: {
        Args: {
          p_description: string
          p_lat: number
          p_lng: number
          p_offer_id: string
        }
        Returns: undefined
      }
      resolve_plant_defect: {
        Args: {
          p_category: Database["public"]["Enums"]["defect_category"]
          p_defect_id: string
          p_mechanic_pin: string
          p_resolution_notes: string
        }
        Returns: Json
      }
      resurrect_dead_letter: {
        Args: { p_outbox_id: string }
        Returns: undefined
      }
      revoke_pending_shift: {
        Args: { p_assignment_id: string; p_reason: string }
        Returns: undefined
      }
      seed_test_trip: { Args: never; Returns: undefined }
      st_3dclosestpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3ddistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_3dintersects: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_3dlongestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3dmakebox: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_3dmaxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_3dshortestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_addpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_angle:
        | { Args: { line1: unknown; line2: unknown }; Returns: number }
        | {
            Args: { pt1: unknown; pt2: unknown; pt3: unknown; pt4?: unknown }
            Returns: number
          }
      st_area:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number }
      st_asencodedpolyline: {
        Args: { geom: unknown; nprecision?: number }
        Returns: string
      }
      st_asewkt: { Args: { "": string }; Returns: string }
      st_asgeojson:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | {
            Args: {
              geom_column?: string
              maxdecimaldigits?: number
              pretty_bool?: boolean
              r: Record<string, unknown>
            }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_asgml:
        | {
            Args: {
              geog: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
            }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
        | {
            Args: {
              geog: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
              version: number
            }
            Returns: string
          }
        | {
            Args: {
              geom: unknown
              id?: string
              maxdecimaldigits?: number
              nprefix?: string
              options?: number
              version: number
            }
            Returns: string
          }
      st_askml:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; nprefix?: string }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; nprefix?: string }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_aslatlontext: {
        Args: { geom: unknown; tmpl?: string }
        Returns: string
      }
      st_asmarc21: { Args: { format?: string; geom: unknown }; Returns: string }
      st_asmvtgeom: {
        Args: {
          bounds: unknown
          buffer?: number
          clip_geom?: boolean
          extent?: number
          geom: unknown
        }
        Returns: unknown
      }
      st_assvg:
        | {
            Args: { geog: unknown; maxdecimaldigits?: number; rel?: number }
            Returns: string
          }
        | {
            Args: { geom: unknown; maxdecimaldigits?: number; rel?: number }
            Returns: string
          }
        | { Args: { "": string }; Returns: string }
      st_astext: { Args: { "": string }; Returns: string }
      st_astwkb:
        | {
            Args: {
              geom: unknown
              prec?: number
              prec_m?: number
              prec_z?: number
              with_boxes?: boolean
              with_sizes?: boolean
            }
            Returns: string
          }
        | {
            Args: {
              geom: unknown[]
              ids: number[]
              prec?: number
              prec_m?: number
              prec_z?: number
              with_boxes?: boolean
              with_sizes?: boolean
            }
            Returns: string
          }
      st_asx3d: {
        Args: { geom: unknown; maxdecimaldigits?: number; options?: number }
        Returns: string
      }
      st_azimuth:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: number }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
      st_boundingdiagonal: {
        Args: { fits?: boolean; geom: unknown }
        Returns: unknown
      }
      st_buffer:
        | {
            Args: { geom: unknown; options?: string; radius: number }
            Returns: unknown
          }
        | {
            Args: { geom: unknown; quadsegs: number; radius: number }
            Returns: unknown
          }
      st_centroid: { Args: { "": string }; Returns: unknown }
      st_clipbybox2d: {
        Args: { box: unknown; geom: unknown }
        Returns: unknown
      }
      st_closestpoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_collect: { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
      st_concavehull: {
        Args: {
          param_allow_holes?: boolean
          param_geom: unknown
          param_pctconvex: number
        }
        Returns: unknown
      }
      st_contains: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_containsproperly: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_coorddim: { Args: { geometry: unknown }; Returns: number }
      st_coveredby:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_covers:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_crosses: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_curvetoline: {
        Args: { flags?: number; geom: unknown; tol?: number; toltype?: number }
        Returns: unknown
      }
      st_delaunaytriangles: {
        Args: { flags?: number; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_difference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_disjoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_distance:
        | {
            Args: { geog1: unknown; geog2: unknown; use_spheroid?: boolean }
            Returns: number
          }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
      st_distancesphere:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: number }
        | {
            Args: { geom1: unknown; geom2: unknown; radius: number }
            Returns: number
          }
      st_distancespheroid: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_dwithin: {
        Args: {
          geog1: unknown
          geog2: unknown
          tolerance: number
          use_spheroid?: boolean
        }
        Returns: boolean
      }
      st_equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_expand:
        | { Args: { box: unknown; dx: number; dy: number }; Returns: unknown }
        | {
            Args: { box: unknown; dx: number; dy: number; dz?: number }
            Returns: unknown
          }
        | {
            Args: {
              dm?: number
              dx: number
              dy: number
              dz?: number
              geom: unknown
            }
            Returns: unknown
          }
      st_force3d: { Args: { geom: unknown; zvalue?: number }; Returns: unknown }
      st_force3dm: {
        Args: { geom: unknown; mvalue?: number }
        Returns: unknown
      }
      st_force3dz: {
        Args: { geom: unknown; zvalue?: number }
        Returns: unknown
      }
      st_force4d: {
        Args: { geom: unknown; mvalue?: number; zvalue?: number }
        Returns: unknown
      }
      st_generatepoints:
        | { Args: { area: unknown; npoints: number }; Returns: unknown }
        | {
            Args: { area: unknown; npoints: number; seed: number }
            Returns: unknown
          }
      st_geogfromtext: { Args: { "": string }; Returns: unknown }
      st_geographyfromtext: { Args: { "": string }; Returns: unknown }
      st_geohash:
        | { Args: { geog: unknown; maxchars?: number }; Returns: string }
        | { Args: { geom: unknown; maxchars?: number }; Returns: string }
      st_geomcollfromtext: { Args: { "": string }; Returns: unknown }
      st_geometricmedian: {
        Args: {
          fail_if_not_converged?: boolean
          g: unknown
          max_iter?: number
          tolerance?: number
        }
        Returns: unknown
      }
      st_geometryfromtext: { Args: { "": string }; Returns: unknown }
      st_geomfromewkt: { Args: { "": string }; Returns: unknown }
      st_geomfromgeojson:
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": Json }; Returns: unknown }
        | { Args: { "": string }; Returns: unknown }
      st_geomfromgml: { Args: { "": string }; Returns: unknown }
      st_geomfromkml: { Args: { "": string }; Returns: unknown }
      st_geomfrommarc21: { Args: { marc21xml: string }; Returns: unknown }
      st_geomfromtext: { Args: { "": string }; Returns: unknown }
      st_gmltosql: { Args: { "": string }; Returns: unknown }
      st_hasarc: { Args: { geometry: unknown }; Returns: boolean }
      st_hausdorffdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_hexagon: {
        Args: { cell_i: number; cell_j: number; origin?: unknown; size: number }
        Returns: unknown
      }
      st_hexagongrid: {
        Args: { bounds: unknown; size: number }
        Returns: Record<string, unknown>[]
      }
      st_interpolatepoint: {
        Args: { line: unknown; point: unknown }
        Returns: number
      }
      st_intersection: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_intersects:
        | { Args: { geog1: unknown; geog2: unknown }; Returns: boolean }
        | { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_isvaliddetail: {
        Args: { flags?: number; geom: unknown }
        Returns: Database["public"]["CompositeTypes"]["valid_detail"]
        SetofOptions: {
          from: "*"
          to: "valid_detail"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      st_length:
        | { Args: { geog: unknown; use_spheroid?: boolean }; Returns: number }
        | { Args: { "": string }; Returns: number }
      st_letters: { Args: { font?: Json; letters: string }; Returns: unknown }
      st_linecrossingdirection: {
        Args: { line1: unknown; line2: unknown }
        Returns: number
      }
      st_linefromencodedpolyline: {
        Args: { nprecision?: number; txtin: string }
        Returns: unknown
      }
      st_linefromtext: { Args: { "": string }; Returns: unknown }
      st_linelocatepoint: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_linetocurve: { Args: { geometry: unknown }; Returns: unknown }
      st_locatealong: {
        Args: { geometry: unknown; leftrightoffset?: number; measure: number }
        Returns: unknown
      }
      st_locatebetween: {
        Args: {
          frommeasure: number
          geometry: unknown
          leftrightoffset?: number
          tomeasure: number
        }
        Returns: unknown
      }
      st_locatebetweenelevations: {
        Args: { fromelevation: number; geometry: unknown; toelevation: number }
        Returns: unknown
      }
      st_longestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makebox2d: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makeline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_makevalid: {
        Args: { geom: unknown; params: string }
        Returns: unknown
      }
      st_maxdistance: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: number
      }
      st_minimumboundingcircle: {
        Args: { inputgeom: unknown; segs_per_quarter?: number }
        Returns: unknown
      }
      st_mlinefromtext: { Args: { "": string }; Returns: unknown }
      st_mpointfromtext: { Args: { "": string }; Returns: unknown }
      st_mpolyfromtext: { Args: { "": string }; Returns: unknown }
      st_multilinestringfromtext: { Args: { "": string }; Returns: unknown }
      st_multipointfromtext: { Args: { "": string }; Returns: unknown }
      st_multipolygonfromtext: { Args: { "": string }; Returns: unknown }
      st_node: { Args: { g: unknown }; Returns: unknown }
      st_normalize: { Args: { geom: unknown }; Returns: unknown }
      st_offsetcurve: {
        Args: { distance: number; line: unknown; params?: string }
        Returns: unknown
      }
      st_orderingequals: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_overlaps: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: boolean
      }
      st_perimeter: {
        Args: { geog: unknown; use_spheroid?: boolean }
        Returns: number
      }
      st_pointfromtext: { Args: { "": string }; Returns: unknown }
      st_pointm: {
        Args: {
          mcoordinate: number
          srid?: number
          xcoordinate: number
          ycoordinate: number
        }
        Returns: unknown
      }
      st_pointz: {
        Args: {
          srid?: number
          xcoordinate: number
          ycoordinate: number
          zcoordinate: number
        }
        Returns: unknown
      }
      st_pointzm: {
        Args: {
          mcoordinate: number
          srid?: number
          xcoordinate: number
          ycoordinate: number
          zcoordinate: number
        }
        Returns: unknown
      }
      st_polyfromtext: { Args: { "": string }; Returns: unknown }
      st_polygonfromtext: { Args: { "": string }; Returns: unknown }
      st_project: {
        Args: { azimuth: number; distance: number; geog: unknown }
        Returns: unknown
      }
      st_quantizecoordinates: {
        Args: {
          g: unknown
          prec_m?: number
          prec_x: number
          prec_y?: number
          prec_z?: number
        }
        Returns: unknown
      }
      st_reduceprecision: {
        Args: { geom: unknown; gridsize: number }
        Returns: unknown
      }
      st_relate: { Args: { geom1: unknown; geom2: unknown }; Returns: string }
      st_removerepeatedpoints: {
        Args: { geom: unknown; tolerance?: number }
        Returns: unknown
      }
      st_segmentize: {
        Args: { geog: unknown; max_segment_length: number }
        Returns: unknown
      }
      st_setsrid:
        | { Args: { geog: unknown; srid: number }; Returns: unknown }
        | { Args: { geom: unknown; srid: number }; Returns: unknown }
      st_sharedpaths: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_shortestline: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_simplifypolygonhull: {
        Args: { geom: unknown; is_outer?: boolean; vertex_fraction: number }
        Returns: unknown
      }
      st_split: { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
      st_square: {
        Args: { cell_i: number; cell_j: number; origin?: unknown; size: number }
        Returns: unknown
      }
      st_squaregrid: {
        Args: { bounds: unknown; size: number }
        Returns: Record<string, unknown>[]
      }
      st_srid:
        | { Args: { geog: unknown }; Returns: number }
        | { Args: { geom: unknown }; Returns: number }
      st_subdivide: {
        Args: { geom: unknown; gridsize?: number; maxvertices?: number }
        Returns: unknown[]
      }
      st_swapordinates: {
        Args: { geom: unknown; ords: unknown }
        Returns: unknown
      }
      st_symdifference: {
        Args: { geom1: unknown; geom2: unknown; gridsize?: number }
        Returns: unknown
      }
      st_symmetricdifference: {
        Args: { geom1: unknown; geom2: unknown }
        Returns: unknown
      }
      st_tileenvelope: {
        Args: {
          bounds?: unknown
          margin?: number
          x: number
          y: number
          zoom: number
        }
        Returns: unknown
      }
      st_touches: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_transform:
        | {
            Args: { from_proj: string; geom: unknown; to_proj: string }
            Returns: unknown
          }
        | {
            Args: { from_proj: string; geom: unknown; to_srid: number }
            Returns: unknown
          }
        | { Args: { geom: unknown; to_proj: string }; Returns: unknown }
      st_triangulatepolygon: { Args: { g1: unknown }; Returns: unknown }
      st_union:
        | { Args: { geom1: unknown; geom2: unknown }; Returns: unknown }
        | {
            Args: { geom1: unknown; geom2: unknown; gridsize: number }
            Returns: unknown
          }
      st_voronoilines: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_voronoipolygons: {
        Args: { extend_to?: unknown; g1: unknown; tolerance?: number }
        Returns: unknown
      }
      st_within: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      st_wkbtosql: { Args: { wkb: string }; Returns: unknown }
      st_wkttosql: { Args: { "": string }; Returns: unknown }
      st_wrapx: {
        Args: { geom: unknown; move: number; wrap: number }
        Returns: unknown
      }
      staging_area_geojson: {
        Args: { offer: Database["public"]["Tables"]["load_offers"]["Row"] }
        Returns: Json
      }
      submit_telemetry_event: {
        Args: {
          p_asset_id: string
          p_client_timestamp: string
          p_event_type: string
          p_payload: Json
          p_recorded_by: string
        }
        Returns: string
      }
      sweep_stagnant_queues: { Args: never; Returns: undefined }
      sync_watermelondb_push: { Args: { changes: Json }; Returns: undefined }
      unlockrows: { Args: { "": string }; Returns: number }
      update_project_geometry: {
        Args: { p_geojson: Json; p_project_id: string; p_zone_type: string }
        Returns: undefined
      }
      updategeometrysrid: {
        Args: {
          catalogn_name: string
          column_name: string
          new_srid_in: number
          schema_name: string
          table_name: string
        }
        Returns: string
      }
    }
    Enums: {
      asset_category:
        | "heavy_machinery"
        | "light_vehicle"
        | "static_plant"
        | "HAUL_TRUCK"
      asset_status:
        | "operational"
        | "maintenance"
        | "decommissioned"
        | "AVAILABLE"
        | "DISPATCHED"
        | "OUT_OF_SERVICE"
      assignment_status:
        | "active"
        | "completed"
        | "cancelled"
        | "pending_prestart"
        | "in_progress"
        | "revoked"
      cycle_status: "loading" | "in_transit" | "dumped" | "reconciled"
      defect_category:
        | "hydraulic"
        | "electrical"
        | "engine"
        | "wear_and_tear"
        | "false_alarm"
      defect_status: "reported" | "under_repair" | "rectified"
      excavator_status:
        | "ready_to_load"
        | "relocating"
        | "rock_breaking"
        | "standby"
      hire_model_type: "dry_hire" | "wet_hire"
      maintenance_status: "in_progress" | "resolved"
      subscription_status:
        | "trialing"
        | "active"
        | "past_due"
        | "canceled"
        | "suspended"
      subscription_tier: "tier_1" | "tier_2" | "tier_3"
      user_role:
        | "contractor"
        | "operator"
        | "admin"
        | "weighbridge_operator"
        | "heavy_mechanic"
    }
    CompositeTypes: {
      geometry_dump: {
        path: number[] | null
        geom: unknown
      }
      valid_detail: {
        valid: boolean | null
        reason: string | null
        location: unknown
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      asset_category: [
        "heavy_machinery",
        "light_vehicle",
        "static_plant",
        "HAUL_TRUCK",
      ],
      asset_status: [
        "operational",
        "maintenance",
        "decommissioned",
        "AVAILABLE",
        "DISPATCHED",
        "OUT_OF_SERVICE",
      ],
      assignment_status: [
        "active",
        "completed",
        "cancelled",
        "pending_prestart",
        "in_progress",
        "revoked",
      ],
      cycle_status: ["loading", "in_transit", "dumped", "reconciled"],
      defect_category: [
        "hydraulic",
        "electrical",
        "engine",
        "wear_and_tear",
        "false_alarm",
      ],
      defect_status: ["reported", "under_repair", "rectified"],
      excavator_status: [
        "ready_to_load",
        "relocating",
        "rock_breaking",
        "standby",
      ],
      hire_model_type: ["dry_hire", "wet_hire"],
      maintenance_status: ["in_progress", "resolved"],
      subscription_status: [
        "trialing",
        "active",
        "past_due",
        "canceled",
        "suspended",
      ],
      subscription_tier: ["tier_1", "tier_2", "tier_3"],
      user_role: [
        "contractor",
        "operator",
        "admin",
        "weighbridge_operator",
        "heavy_mechanic",
      ],
    },
  },
} as const

