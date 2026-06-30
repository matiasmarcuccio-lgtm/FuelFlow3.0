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
      assets: {
        Row: {
          asset_type: string
          compliance_records: Json | null
          created_at: string | null
          fleet_id: string
          fuel_burn_rate: number
          has_4x4_traction: boolean | null
          id: string
          is_active: boolean | null
          is_nhvr_accredited: boolean | null
          max_fuel_capacity: number
          max_load_length_mm: number | null
          max_load_width_mm: number | null
          max_payload_kg: number | null
          pallet_capacity: number | null
          registration_number: string
          special_features: Json | null
          trailer_type: string | null
          turning_radius_m: number | null
          updated_at: string | null
          vehicle_metadata: Json | null
        }
        Insert: {
          asset_type: string
          compliance_records?: Json | null
          created_at?: string | null
          fleet_id: string
          fuel_burn_rate: number
          has_4x4_traction?: boolean | null
          id?: string
          is_active?: boolean | null
          is_nhvr_accredited?: boolean | null
          max_fuel_capacity: number
          max_load_length_mm?: number | null
          max_load_width_mm?: number | null
          max_payload_kg?: number | null
          pallet_capacity?: number | null
          registration_number: string
          special_features?: Json | null
          trailer_type?: string | null
          turning_radius_m?: number | null
          updated_at?: string | null
          vehicle_metadata?: Json | null
        }
        Update: {
          asset_type?: string
          compliance_records?: Json | null
          created_at?: string | null
          fleet_id?: string
          fuel_burn_rate?: number
          has_4x4_traction?: boolean | null
          id?: string
          is_active?: boolean | null
          is_nhvr_accredited?: boolean | null
          max_fuel_capacity?: number
          max_load_length_mm?: number | null
          max_load_width_mm?: number | null
          max_payload_kg?: number | null
          pallet_capacity?: number | null
          registration_number?: string
          special_features?: Json | null
          trailer_type?: string | null
          turning_radius_m?: number | null
          updated_at?: string | null
          vehicle_metadata?: Json | null
        }
        Relationships: []
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
        Relationships: [
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
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
        Relationships: [
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
        ]
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
      profiles: {
        Row: {
          created_at: string | null
          fleet_id: string
          full_name: string | null
          id: string
          insurance_expiry_date: string | null
          insurance_policy_number: string | null
          is_verified: boolean | null
          role: string
          updated_at: string | null
          insurance_compliant: boolean | null
        }
        Insert: {
          created_at?: string | null
          fleet_id?: string
          full_name?: string | null
          id: string
          insurance_expiry_date?: string | null
          insurance_policy_number?: string | null
          is_verified?: boolean | null
          role: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          fleet_id?: string
          full_name?: string | null
          id?: string
          insurance_expiry_date?: string | null
          insurance_policy_number?: string | null
          is_verified?: boolean | null
          role?: string
          updated_at?: string | null
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
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
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
          {
            foreignKeyName: "shift_assignments_vehicle_id_fkey"
            columns: ["vehicle_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_assignments_vehicle_id_fkey"
            columns: ["vehicle_id"]
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
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
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
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fk_asset"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "view_fleet_matrix"
            referencedColumns: ["vehicle_id"]
          },
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
          has_4x4_traction: boolean | null
          max_payload_kg: number | null
          registration_number: string | null
          turning_radius_m: number | null
          vehicle_id: string | null
        }
        Insert: {
          has_4x4_traction?: boolean | null
          max_payload_kg?: number | null
          registration_number?: string | null
          turning_radius_m?: number | null
          vehicle_id?: string | null
        }
        Update: {
          has_4x4_traction?: boolean | null
          max_payload_kg?: number | null
          registration_number?: string | null
          turning_radius_m?: number | null
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
      enablelongtransactions: { Args: never; Returns: string }
      equals: { Args: { geom1: unknown; geom2: unknown }; Returns: boolean }
      exclusion_zone_geojson: {
        Args: { offer: Database["public"]["Tables"]["load_offers"]["Row"] }
        Returns: Json
      }
      fn_assign_asset_to_project: {
        Args: {
          p_asset_id: string
          p_driver_id: string
          p_load_offer_id: string
        }
        Returns: boolean
      }
      fn_dispatch_shift: {
        Args: {
          p_asset_id: string
          p_driver_id: string
          p_master_order_id: string
        }
        Returns: string
      }
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
      fn_request_detach:
        | { Args: { p_reason: string }; Returns: undefined }
        | { Args: { p_reason: string; p_shift_id: string }; Returns: undefined }
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
      longtransactionsenabled: { Args: never; Returns: boolean }
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
      report_incident: {
        Args: {
          p_description: string
          p_lat: number
          p_lng: number
          p_offer_id: string
        }
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
      user_role: "contractor" | "operator" | "admin"
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
      user_role: ["contractor", "operator", "admin"],
    },
  },
} as const

