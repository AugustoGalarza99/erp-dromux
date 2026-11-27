/* Tipos de ítem: etiquetas y ayuda en un solo lugar. Los colores viven en uiFoundation.css. */
import { TIPOS_ITEM, TIPO_ITEM_ETIQUETA } from "../../../compartido/valores";

export const itemTypeOrder = TIPOS_ITEM;

export const itemTypeLabels = TIPO_ITEM_ETIQUETA;

export const itemTypeHelp = {
  materia_prima: "Lo que comprás y transformás al fabricar: chapa, harina, aceite, tela.",
  semielaborado: "Lo que fabricás y después usás para armar otro producto.",
  producto_terminado: "Lo que vendés o entregás a un cliente.",
  insumo: "Lo que se gasta en la operación: envases, etiquetas, guantes.",
};
