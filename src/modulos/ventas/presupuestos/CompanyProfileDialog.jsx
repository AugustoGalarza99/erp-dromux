import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import ActionDialog from "../../../compartido/componentes/ActionDialog";
import { useAuth } from "../../../compartido/contextos/AuthContext";
import { readLogo } from "../../../compartido/utilidades/logo";
import { friendlyError, notifyError, notifySuccess } from "../../../compartido/utilidades/notifications";
import { getCompanyProfile, saveCompanyProfile } from "./quotes";

const empty = { legal_name: "", tax_id: "", tax_condition: "", address: "", phone: "", email: "", website: "", logo_data: "" };

/* Datos que aparecen en el membrete de los presupuestos (y futuros documentos). Solo administración. */
export default function CompanyProfileDialog({ open, onClose, onSaved }) {
  const { activeCompanyId, user } = useAuth();
  const [form, setForm] = useState(empty);
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: ["company-profile", user?.id, activeCompanyId],
    queryFn: () => getCompanyProfile(activeCompanyId),
    enabled: open && Boolean(activeCompanyId),
  });
  useEffect(() => {
    if (open && query.data) setForm({ ...empty, ...query.data });
  }, [open, query.data]);
  const set = (key) => (event) => setForm((current) => ({ ...current, [key]: event.target.value }));

  async function upload(event) {
    const file = event.target.files?.[0];
    if (!file) return;
    setBusy(true);
    try {
      const logo = await readLogo(file);
      setForm((current) => ({ ...current, logo_data: logo }));
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
      event.target.value = "";
    }
  }

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      await saveCompanyProfile(activeCompanyId, form);
      notifySuccess("Datos de la empresa guardados");
      await onSaved();
      onClose();
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <ActionDialog open={open} busy={busy} onClose={onClose} title="Datos de la empresa"
      description="Aparecen en el encabezado de los presupuestos que le enviás a tus clientes.">
      <form className="pl-form" onSubmit={submit}>
        {query.error && <p role="alert" className="error">{friendlyError(query.error)}</p>}
        <label>Razón social o nombre comercial
          <input maxLength={160} value={form.legal_name} onChange={set("legal_name")} />
        </label>
        <div className="pl-two">
          <label>CUIT<input maxLength={30} value={form.tax_id} onChange={set("tax_id")} /></label>
          <label>Condición frente al IVA<input maxLength={60} value={form.tax_condition} onChange={set("tax_condition")} placeholder="Ej.: Responsable Inscripto" /></label>
        </div>
        <label>Domicilio<input maxLength={240} value={form.address} onChange={set("address")} /></label>
        <div className="pl-two">
          <label>Teléfono<input maxLength={40} value={form.phone} onChange={set("phone")} /></label>
          <label>Correo electrónico<input type="email" maxLength={160} value={form.email} onChange={set("email")} /></label>
        </div>
        <label>Sitio web<input maxLength={160} value={form.website} onChange={set("website")} /></label>
        <div className="pl-logo">
          <span>Logo</span>
          {form.logo_data ? <img src={form.logo_data} alt="Logo de la empresa" /> : <small>Sin logo cargado.</small>}
          <div className="pl-logo-actions">
            <label className="button outline">Elegir imagen
              <input type="file" accept="image/png,image/jpeg,image/webp" onChange={upload} disabled={busy} hidden />
            </label>
            {form.logo_data && <button type="button" className="button outline" onClick={() => setForm({ ...form, logo_data: "" })}>Quitar logo</button>}
          </div>
          <small>PNG, JPG o WebP de hasta 2 MB. Se reduce automáticamente.</small>
        </div>
        <div className="pl-footer">
          <button type="button" className="button outline" onClick={onClose} disabled={busy}>Cancelar</button>
          <button type="submit" className="button primary" disabled={busy || query.isPending}>
            {busy ? "Guardando…" : "Guardar datos"}
          </button>
        </div>
      </form>
    </ActionDialog>
  );
}
