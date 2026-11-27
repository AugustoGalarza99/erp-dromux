/* Tipos de ítem: etiquetas y ayuda en un solo lugar. Los colores viven en uiFoundation.css. */
export const itemTypeOrder = [
  "raw_material",
  "semi_finished",
  "finished_product",
  "consumable",
];

export const itemTypeLabels = {
  raw_material: "Materia prima",
  semi_finished: "Semielaborado",
  finished_product: "Producto terminado",
  consumable: "Insumo",
};

export const itemTypeHelp = {
  raw_material: "Lo que comprás y transformás al fabricar: chapa, harina, aceite, tela.",
  semi_finished: "Lo que fabricás y después usás para armar otro producto.",
  finished_product: "Lo que vendés o entregás a un cliente.",
  consumable: "Lo que se gasta en la operación: envases, etiquetas, guantes.",
};
