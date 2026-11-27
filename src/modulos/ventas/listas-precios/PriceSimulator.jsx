import { useState } from "react";
import { Calculator } from "lucide-react";
import { markupOf, marginOf, money, parseAmount, percent, previewPrice, withTax } from "../compartido/pricing";

/*
 * Simulador "¿a qué precio vendo?". Solo calcula en pantalla con lo que se escribe: no guarda nada.
 * Lo ve solo la administración (usa costos), y la comisión y gastos vienen de los parámetros de precios.
 */
export default function PriceSimulator({ settings, currency = "ARS" }) {
  const [cost, setCost] = useState("");
  const [wanted, setWanted] = useState("");
  const [rival, setRival] = useState("");
  const [tax, setTax] = useState(String(settings?.default_tax_percent ?? 21));

  const costValue = parseAmount(cost);
  const taxValue = parseAmount(tax) ?? 0;
  const over = Number(settings?.commission_percent ?? 0) + Number(settings?.structure_percent ?? 0);
  const suggested = previewPrice("margen", parseAmount(wanted), costValue);
  const rivalNet = parseAmount(rival);
  const afterCosts = (price) => (price != null && costValue != null ? price - costValue - (price * over) / 100 : null);

  return (
    <details className="pl-simulator">
      <summary><Calculator size={16} aria-hidden="true" /> Simulador de precio</summary>
      <div className="pl-sim-grid">
        <label>Costo por unidad<input inputMode="decimal" value={cost} onChange={(event) => setCost(event.target.value)} placeholder="Ej.: 1.485,46" /></label>
        <label>IVA (%)<input inputMode="decimal" value={tax} onChange={(event) => setTax(event.target.value)} /></label>
        <label>Margen que quiero (%)<input inputMode="decimal" value={wanted} onChange={(event) => setWanted(event.target.value)} placeholder="Ej.: 30" /></label>
        <label>Precio de la competencia (sin IVA)<input inputMode="decimal" value={rival} onChange={(event) => setRival(event.target.value)} /></label>
      </div>
      <div className="pl-sim-results" aria-live="polite">
        <div>
          <small>Para ese margen conviene vender a</small>
          <strong>{money(suggested, currency)}</strong>
          <span>Con IVA {money(withTax(suggested, taxValue), currency)} · ganancia neta de comisión y gastos {money(afterCosts(suggested), currency)}</span>
        </div>
        <div>
          <small>Si igualo a la competencia</small>
          <strong>{percent(marginOf(rivalNet, costValue))} de margen</strong>
          <span>Recargo sobre costo {percent(markupOf(rivalNet, costValue))} · ganancia neta de comisión y gastos {money(afterCosts(rivalNet), currency)}</span>
        </div>
      </div>
    </details>
  );
}
