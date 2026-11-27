/*
 * Topes de líneas por documento. Deben coincidir con los de la base (`jsonb_array_length(...)
 * not between 1 and N` en cada función). Migración 037 aplicada por el propietario y verificada
 * por catálogo el 23/11/2026: fórmula 500, consumo de orden "ya fabricada" 500, remito de
 * fabricación/materiales 500, remito de venta 200, orden de compra 200, recepción de compra 200.
 * Ventas (`post_sale`), ajustes de venta y órdenes de pago siguen en 40 a propósito (dinero:
 * requieren auditoría antes de subirlos). Si se cambia un tope en la base, cambiarlo acá también.
 */
export const LINE_LIMITS = {
  formula: 500,
  productionInputs: 500,
  deliveryNote: 500,
  saleDeliveryNote: 200,
  purchaseOrder: 200,
  purchaseReceipt: 200,
  sale: 40,
  supplierPayment: 40,
};
