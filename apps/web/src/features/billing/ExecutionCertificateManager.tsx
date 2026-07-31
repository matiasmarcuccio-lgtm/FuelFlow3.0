import React, { useMemo } from "react";

interface ShiftData {
  id: string;
  shift_start: string | null;
  shift_end: string | null;
  master_order_id: string | null;
  master_orders?: {
    description: string;
  } | null;
  assets: {
    internal_code: string;
  };
  profiles: {
    first_name: string;
    last_name: string;
  };
}

interface Props {
  shifts: ShiftData[];
  loading: boolean;
  error: string | null;
  selectedShiftIds: string[];
  onToggleShift: (id: string) => void;
  onGenerate: () => void;
  generating: boolean;
}

export const ExecutionCertificateManager: React.FC<Props> = ({
  shifts,
  loading,
  error,
  selectedShiftIds,
  onToggleShift,
  onGenerate,
  generating,
}) => {
  // We assume 8 hours per shift as a placeholder since actual duration relies on telemetry
  const assumedHoursPerShift = 8;
  const standardHourlyRate = 150;

  const totalSelectedHours = selectedShiftIds.length * assumedHoursPerShift;
  const estimatedRevenue = totalSelectedHours * standardHourlyRate;

  // Segregate shifts by master_order_id
  const groupedShifts = useMemo(() => {
    return shifts.reduce(
      (acc, shift) => {
        const orderId = shift.master_order_id || "SIN CONTRATO";
        if (!acc[orderId]) {
          acc[orderId] = [];
        }
        acc[orderId].push(shift);
        return acc;
      },
      {} as Record<string, ShiftData[]>,
    );
  }, [shifts]);

  // Validar que no se mezclen contratos
  const selectedOrderIds = useMemo(() => {
    const orders = new Set<string>();
    shifts.forEach((s) => {
      if (selectedShiftIds.includes(s.id)) {
        orders.add(s.master_order_id || "SIN CONTRATO");
      }
    });
    return Array.from(orders);
  }, [shifts, selectedShiftIds]);

  const hasMixedContracts = selectedOrderIds.length > 1;

  if (loading)
    return (
      <div className="p-8 text-center text-slate-400">
        Cargando turnos facturables...
      </div>
    );

  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-8 shadow-2xl mt-8">
      <div className="border-b border-slate-800 pb-6 mb-8 flex justify-between items-center">
        <div>
          <h2 className="text-xl font-bold tracking-tight text-white flex items-center gap-2">
            <span>🧾</span> Aduana de Certificados de Ejecución
          </h2>
          <p className="text-slate-400 mt-2 text-sm max-w-lg">
            Selecciona los turnos completados para agruparlos de forma atómica
            en un certificado financiero. El ERP será notificado de inmediato.
          </p>
        </div>

        <div className="bg-slate-800 rounded-lg p-4 flex gap-6 text-right border border-slate-700">
          <div>
            <p className="text-xs text-slate-400 font-mono uppercase">
              Horas Sel.
            </p>
            <p className="text-lg text-white font-bold">
              {totalSelectedHours} hrs
            </p>
          </div>
          <div>
            <p className="text-xs text-slate-400 font-mono uppercase">
              Ingreso Bruto
            </p>
            <p className="text-lg text-emerald-400 font-bold">
              ${estimatedRevenue.toFixed(2)}
            </p>
          </div>
        </div>
      </div>

      {error && (
        <div className="bg-red-900/50 border border-red-500/50 text-red-200 p-4 rounded-lg mb-6 text-sm font-mono flex items-start gap-3">
          <span className="text-lg mt-0.5">⚠️</span>
          <div>
            <p className="font-bold uppercase mb-1 text-red-400">
              Violación Financiera
            </p>
            <p>{error}</p>
          </div>
        </div>
      )}

      {hasMixedContracts && (
        <div className="bg-orange-900/50 border border-orange-500/50 text-orange-200 p-4 rounded-lg mb-6 text-sm font-mono flex items-start gap-3">
          <span className="text-lg mt-0.5">⚠️</span>
          <div>
            <p className="font-bold uppercase mb-1 text-orange-400">
              Error de Segregación
            </p>
            <p>
              No puedes agrupar turnos de diferentes contratos maestros en un
              mismo certificado. Deselecciona los turnos para que pertenezcan a
              un único contrato.
            </p>
          </div>
        </div>
      )}

      {shifts.length === 0 ? (
        <div className="text-center py-12 border-2 border-dashed border-slate-800 rounded-lg bg-slate-900/50">
          <p className="text-slate-500 font-mono text-sm">
            No hay turnos completados pendientes de facturación en la flota.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-6">
          {Object.entries(groupedShifts).map(([orderId, orderShifts]) => {
            const orderName =
              orderShifts[0]?.master_orders?.description ||
              "Contrato Secundario";
            const isMixedOut =
              hasMixedContracts &&
              selectedOrderIds[0] !== orderId &&
              selectedShiftIds.length > 0;

            return (
              <div
                key={orderId}
                className={`rounded-lg border overflow-hidden ${isMixedOut ? "border-slate-800 opacity-50" : "border-slate-700"}`}
              >
                <div className="bg-slate-950 px-4 py-3 border-b border-slate-800 flex items-center justify-between">
                  <h3 className="font-mono text-sm text-blue-400 uppercase font-bold tracking-wider">
                    Contrato: {orderName}
                  </h3>
                  <span className="text-xs text-slate-500 font-mono">
                    {orderId}
                  </span>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-sm text-slate-300">
                    <thead className="text-xs text-slate-500 uppercase bg-slate-900 border-b border-slate-800">
                      <tr>
                        <th className="p-4 w-12"></th>
                        <th className="p-4">Operador</th>
                        <th className="p-4">Activo Físico</th>
                        <th className="p-4">Inicio Turno</th>
                        <th className="p-4">Fin Turno</th>
                        <th className="p-4 text-right">Horas</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800 bg-slate-900/50">
                      {orderShifts.map((shift) => (
                        <tr
                          key={shift.id}
                          className={`hover:bg-slate-800 transition-colors cursor-pointer ${selectedShiftIds.includes(shift.id) ? "bg-blue-900/20" : ""}`}
                          onClick={() => onToggleShift(shift.id)}
                        >
                          <td className="p-4">
                            <input
                              type="checkbox"
                              className="w-4 h-4 rounded bg-slate-800 border-slate-600 text-blue-500 focus:ring-blue-600 focus:ring-offset-slate-900 pointer-events-none"
                              checked={selectedShiftIds.includes(shift.id)}
                              readOnly
                            />
                          </td>
                          <td className="p-4 font-medium text-white">
                            {shift.profiles?.first_name}{" "}
                            {shift.profiles?.last_name}
                          </td>
                          <td className="p-4">
                            <span className="bg-slate-950 px-2 py-1 rounded font-mono text-xs border border-slate-700 text-blue-400 shadow-sm">
                              {shift.assets?.internal_code}
                            </span>
                          </td>
                          <td className="p-4 text-slate-400 font-mono text-xs">
                            {shift.shift_start
                              ? new Date(shift.shift_start).toLocaleString()
                              : "N/A"}
                          </td>
                          <td className="p-4 text-slate-400 font-mono text-xs">
                            {shift.shift_end
                              ? new Date(shift.shift_end).toLocaleString()
                              : "N/A"}
                          </td>
                          <td className="p-4 text-right font-mono text-emerald-400">
                            {assumedHoursPerShift}h
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="mt-8 pt-6 border-t border-slate-800 flex justify-end">
        <button
          onClick={onGenerate}
          disabled={
            selectedShiftIds.length === 0 || generating || hasMixedContracts
          }
          className="px-6 py-3 bg-emerald-600 hover:bg-emerald-500 disabled:bg-slate-800 disabled:text-slate-600 disabled:border-slate-700 text-white font-bold text-sm tracking-wide rounded-lg shadow-lg transition-all flex items-center gap-3 border border-emerald-500"
        >
          {generating ? (
            "FIRMANTE FINANCIERO..."
          ) : (
            <>
              <span>GENERAR CERTIFICADO Y NOTIFICAR ERP</span>
              {selectedShiftIds.length > 0 && !hasMixedContracts && (
                <span className="bg-emerald-950 text-emerald-300 px-2.5 py-1 rounded-md text-xs font-mono border border-emerald-800">
                  {selectedShiftIds.length} turnos
                </span>
              )}
            </>
          )}
        </button>
      </div>
    </div>
  );
};
