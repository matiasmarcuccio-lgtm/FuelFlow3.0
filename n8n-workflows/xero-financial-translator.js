// n8n Code Node: FuelFlow to Xero Financial Translator
const inputPayload = $input.item.json;
const eventType = inputPayload.event;

let xeroPayload = {};

// Constantes Contables (Ajustar a tu Chart of Accounts en Xero)
const COA_EQUIPMENT_HIRE = "200"; // Cuenta de Ventas/Ingresos
const COA_FUEL_EXPENSE = "310"; // Cuenta de Costo de Bienes Vendidos (COGS)
const GST_ON_INCOME = "OUTPUT"; // 10% GST cobrado al cliente
const GST_ON_EXPENSES = "INPUT"; // 10% GST pagado (para deducir)

if (eventType === "billing.certificate.generated") {
  // ESCENARIO 1: Facturación de Horas de Maquinaria (Cuentas por Cobrar - ACCREC)
  
  // Calcular el precio unitario exacto por hora
  const unitPrice = (inputPayload.total_billable / inputPayload.total_hours).toFixed(2);
  
  xeroPayload = {
    "Type": "ACCREC",
    "Status": "DRAFT", // Nunca emitir como AUTHORISED directamente. Obliga a un humano a revisarla en Xero.
    "Contact": { 
      // En un sistema real, extraerías el ContactID de Xero desde Supabase,
      // cruzándolo con el ID del contrato.
      "ContactID": inputPayload.client_xero_id || "ID-POR-DEFECTO-CLIENTE" 
    },
    "Reference": `FuelFlow Cert: ${inputPayload.certificate_id.substring(0,8)}`,
    "LineItems": [
      {
        "Description": `Alquiler de Equipo Pesado. Horas Operativas. Sello Forense: ${inputPayload.forensic_hash}`,
        "Quantity": inputPayload.total_hours,
        "UnitAmount": parseFloat(unitPrice),
        "AccountCode": COA_EQUIPMENT_HIRE,
        "TaxType": GST_ON_INCOME
      }
    ]
  };

} else if (eventType === "billing.expense.approved") {
  // ESCENARIO 2: Reembolsos Análogos / Cuarentena OCR (Cuentas por Pagar - ACCPAY)
  
  let accountCode = "429"; // Gastos Generales por defecto
  let description = "Gasto Operativo Auditado";

  if (inputPayload.category === "fuel") {
    accountCode = COA_FUEL_EXPENSE;
    description = `Diésel / Combustible. Shift ID: ${inputPayload.shift_id.substring(0,8)}`;
  } else if (inputPayload.category === "toll") {
    accountCode = "489"; // Peajes
    description = `Toll/Permiso de Tránsito. Shift ID: ${inputPayload.shift_id.substring(0,8)}`;
  }

  xeroPayload = {
    "Type": "ACCPAY",
    "Status": "DRAFT",
    "Contact": { 
      "Name": "Proveedor Analógico (Subida por Operador)" 
    },
    "Reference": `Expense ID: ${inputPayload.expense_id.substring(0,8)}`,
    "LineItems": [
      {
        "Description": description,
        "Quantity": 1,
        "UnitAmount": inputPayload.approved_amount,
        "AccountCode": accountCode,
        "TaxType": GST_ON_EXPENSES
      }
    ]
  };
} else {
  throw new Error("EVENTO NO RECONOCIDO: " + eventType);
}

// Retornar el objeto envuelto para el siguiente nodo (HTTP Request hacia Xero)
return {
  json: xeroPayload
};
