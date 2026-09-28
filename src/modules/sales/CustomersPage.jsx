import { useEffect, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { ContactRound, Plus, Search } from 'lucide-react';
import { useAuth } from '../../contexts/AuthContext';
import { notifyError, notifySuccess, friendlyError } from '../../lib/notifications';
import { listCustomers, saveCustomer, setCustomerActive } from '../../services/sales';
import './sales.css';

const empty = { name: '', tax_id: '', email: '', phone: '', address: '', notes: '' };

export default function CustomersPage() {
  const { activeCompanyId, user, can } = useAuth();
  const client = useQueryClient();
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(empty);
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState(false);
  const query = useQuery({
    queryKey: ['sales-customers', user?.id, activeCompanyId],
    queryFn: () => listCustomers(activeCompanyId),
    enabled: !!activeCompanyId,
  });
  useEffect(() => {
    setForm(empty);
    setEditing(null);
    setSearch('');
  }, [activeCompanyId]);
  const refresh = () => client.invalidateQueries({
    queryKey: ['sales-customers', user?.id, activeCompanyId],
  });
  const customers = (query.data ?? []).filter((entry) =>
    `${entry.name} ${entry.tax_id} ${entry.phone}`.toLocaleLowerCase('es-AR')
      .includes(search.toLocaleLowerCase('es-AR')));

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    try {
      await saveCustomer(activeCompanyId, editing?.id, form);
      await refresh();
      notifySuccess(editing ? 'Cliente actualizado' : 'Cliente creado', form.name.trim());
      setEditing(null);
      setForm(empty);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function toggle(customer) {
    setBusy(true);
    try {
      await setCustomerActive(activeCompanyId, customer.id, !customer.active);
      await refresh();
      notifySuccess(customer.active ? 'Cliente desactivado' : 'Cliente activado');
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  function edit(customer) {
    setEditing(customer);
    setForm({
      name: customer.name, tax_id: customer.tax_id, email: customer.email,
      phone: customer.phone, address: customer.address, notes: customer.notes,
    });
  }

  return (
    <section className="sales-page">
      <div className="sales-heading">
        <div><span className="eyebrow">VENTAS / CLIENTES</span><h1>Clientes</h1>
          <p>Una sola ficha por cliente para reutilizarla en todas sus ventas.</p></div>
      </div>
      <div className="sales-grid">
        <form className="sales-card" onSubmit={submit}>
          <h2><ContactRound size={19} /> {editing ? 'Editar cliente' : 'Nuevo cliente'}</h2>
          <label>Nombre o razón social *
            <input required minLength={2} maxLength={160} value={form.name}
              onChange={(event) => setForm({ ...form, name: event.target.value })} />
          </label>
          <div className="sales-two">
            <label>CUIT / documento
              <input maxLength={30} value={form.tax_id}
                onChange={(event) => setForm({ ...form, tax_id: event.target.value })} />
            </label>
            <label>Teléfono
              <input maxLength={40} value={form.phone}
                onChange={(event) => setForm({ ...form, phone: event.target.value })} />
            </label>
          </div>
          <label>Correo electrónico
            <input type="email" maxLength={160} value={form.email}
              onChange={(event) => setForm({ ...form, email: event.target.value })} />
          </label>
          <label>Dirección
            <input maxLength={240} value={form.address}
              onChange={(event) => setForm({ ...form, address: event.target.value })} />
          </label>
          <label>Notas
            <textarea maxLength={500} value={form.notes}
              onChange={(event) => setForm({ ...form, notes: event.target.value })} />
          </label>
          <div className="sales-actions">
            {editing && <button type="button" className="sales-link" onClick={() => {
              setEditing(null);
              setForm(empty);
            }}>Cancelar edición</button>}
            <button className="button primary" disabled={busy || !can('sales', editing ? 'update' : 'insert')}>
              <Plus size={16} /> {busy ? 'Guardando…' : editing ? 'Guardar cambios' : 'Crear cliente'}
            </button>
          </div>
        </form>
        <div className="sales-card">
          <h2>Directorio</h2>
          <div className="sales-search"><Search size={17} />
            <input aria-label="Buscar cliente" placeholder="Nombre, CUIT o teléfono…"
              value={search} onChange={(event) => setSearch(event.target.value)} />
          </div>
          {query.isError && <p className="sales-error">{friendlyError(query.error)}</p>}
          {!customers.length && !query.isPending && <p className="sales-muted">No se encontraron clientes.</p>}
          {customers.map((customer) => <div className="sales-row" key={customer.id}>
            <div><strong>{customer.name}</strong>
              <small>{customer.tax_id || 'Sin documento'} · {customer.phone || 'Sin teléfono'}</small>
              {!customer.active && <small className="sales-error">Inactivo</small>}
            </div>
            <div className="sales-row-actions">
              {can('sales', 'update') && <>
                <button type="button" onClick={() => edit(customer)}>Editar</button>
                <button type="button" disabled={busy} onClick={() => toggle(customer)}>
                  {customer.active ? 'Desactivar' : 'Activar'}
                </button>
              </>}
            </div>
          </div>)}
        </div>
      </div>
    </section>
  );
}
