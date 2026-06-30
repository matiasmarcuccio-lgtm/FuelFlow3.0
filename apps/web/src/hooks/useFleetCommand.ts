import { useState } from 'react';
import { supabase } from '../lib/supabase';

interface CommandState {
  isLoading: boolean;
  error: {
    code: string;
    message: string;
    actionRequired?: string;
  } | null;
  success: boolean;
}

export function useFleetCommand() {
  const [state, setState] = useState<CommandState>({
    isLoading: false,
    error: null,
    success: false
  });

  const translateError = (error: any) => {
    const errorMsg = error?.message || '';
    
    if (errorMsg.includes('ACTIVE_TRANSIT_LOCK')) {
      return {
        code: 'ACTIVE_TRANSIT_LOCK',
        message: 'Forensic Block: Driver has active cargo.',
        actionRequired: 'Resolve via Evidence Vault before deactivation. This employee is currently in transit or loading material.'
      };
    }
    
    if (errorMsg.includes('UNAUTHORIZED_ROLE')) {
      return {
        code: 'UNAUTHORIZED_ROLE',
        message: 'Permission Denied.',
        actionRequired: 'Only Fleet Managers or Super Admins can perform this action.'
      };
    }

    if (errorMsg.includes('NO_ACTIVE_SHIFT')) {
      return {
        code: 'NO_ACTIVE_SHIFT',
        message: 'No active shift found.',
        actionRequired: 'The selected driver is not currently assigned to an active auto-loop.'
      };
    }

    if (errorMsg.includes('INVITE_EXPIRED')) {
      return {
        code: 'INVITE_EXPIRED',
        message: 'Invitation Link Expired.',
        actionRequired: 'The enrollment code has expired. Request a new one from your dispatcher.'
      };
    }

    if (errorMsg.includes('INVITE_NOT_FOUND')) {
      return {
        code: 'INVITE_NOT_FOUND',
        message: 'Invalid Invitation Code.',
        actionRequired: 'Check the code and try again.'
      };
    }

    return {
      code: 'UNKNOWN_ERROR',
      message: 'An unexpected error occurred.',
      actionRequired: errorMsg
    };
  };

  const executeCommand = async <T,>(
    commandFn: () => Promise<{ data: T | null; error: any }>
  ): Promise<T | null> => {
    setState({ isLoading: true, error: null, success: false });
    
    try {
      const { data, error } = await commandFn();
      
      if (error) {
        setState({
          isLoading: false,
          error: translateError(error),
          success: false
        });
        return null;
      }

      setState({ isLoading: false, error: null, success: true });
      return data;
    } catch (err) {
      setState({
        isLoading: false,
        error: translateError(err),
        success: false
      });
      return null;
    }
  };

  const generateInvite = async (fleetId: string) => {
    return executeCommand(() => supabase.rpc('fn_generate_fleet_invite', { p_fleet_id: fleetId }));
  };

  const revokeAccess = async (driverId: string) => {
    return executeCommand(() => supabase.rpc('fn_revoke_driver_access', { p_driver_id: driverId }));
  };

  const overrideShift = async (absentDriverId: string, reserveDriverId: string) => {
    return executeCommand(() => supabase.rpc('fn_override_shift_assignment', { 
      p_absent_driver_id: absentDriverId, 
      p_reserve_driver_id: reserveDriverId 
    }));
  };

  const resetState = () => {
    setState({ isLoading: false, error: null, success: false });
  };

  return {
    ...state,
    executeCommand,
    generateInvite,
    revokeAccess,
    overrideShift,
    resetState
  };
}
