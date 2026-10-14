import SupplierAccountsPage from '../modules/purchases/SupplierAccountsPage';
import PackagingPage from '../modules/production/PackagingPage';
import ProductionDocumentSettings from '../modules/settings/ProductionDocumentSettings';
import { useState } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { ArrowRight, Building2, ShieldCheck } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import { createCompany } from '../services/core';
import { friendlyError, notifyError, notifySuccess } from '../lib/notifications';
import Login from '../modules/auth/Login';
import Dashboard from '../modules/dashboard/Dashboard';
import AdminLayout from '../components/AdminLayout';
import UsersPage from '../modules/settings/UsersPage';
import RolesPage from '../modules/settings/RolesPage';
import CatalogPage from '../modules/catalogs/CatalogPage';
import ItemsPage from '../modules/inventory/ItemsPage';
import ItemEditor from '../modules/inventory/ItemEditor';
import StockPage from '../modules/inventory/StockPage';
import MovementsPage from '../modules/inventory/MovementsPage';
import DeliveryNotesPage from '../modules/inventory/DeliveryNotesPage';
import SuppliersPage from '../modules/purchases/SuppliersPage';
import PurchaseOrdersPage from '../modules/purchases/PurchaseOrdersPage';
import FormulasPage from '../modules/production/FormulasPage';
import ProductionOrdersPage from '../modules/production/ProductionOrdersPage';
import ProductionPlanningPage from '../modules/production/ProductionPlanningPage';
import ManufacturingAvailabilityPage from '../modules/production/ManufacturingAvailabilityPage';
import ReplenishmentPage from '../modules/production/ReplenishmentPage';
import CustomersPage from '../modules/sales/CustomersPage';
import PriceListPage from '../modules/sales/PriceListPage';
import SalesOrdersPage from '../modules/sales/SalesOrdersPage';
import ReceivablesPage from '../modules/finance/ReceivablesPage';
import TreasuryPage from '../modules/finance/TreasuryPage';
import CostsPage from '../modules/finance/CostsPage';
import ReportsPage from '../modules/reports/ReportsPage';
import GuidePage from '../modules/help/GuidePage';
import ProfilePage from '../modules/settings/ProfilePage';
import UpdatesPage from '../modules/help/UpdatesPage';

function SetupCompany() {
  const { refresh, signOut } = useAuth();
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError('');

    try {
      await createCompany(name.trim());
      await refresh();
      notifySuccess('Empresa creada', name.trim());
    } catch (err) {
      setError(notifyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="setup">
      <span className="brand-mark">D</span>
      <span className="eyebrow">PRIMEROS PASOS</span>
      <Building2 size={34} />
      <h1>Creá tu espacio de trabajo</h1>
      <p>Escribí el nombre de tu empresa para comenzar. Tu cuenta tendrá el rol administrador.</p>

      <form onSubmit={handleSubmit}>
        <input
          required
          minLength={2}
          maxLength={100}
          value={name}
          onChange={(event) => setName(event.target.value)}
          placeholder="Nombre de la empresa"
        />
        <button disabled={busy} className="button primary">
          {busy ? 'Creando…' : 'Crear empresa'}
          <ArrowRight size={17} />
        </button>
      </form>

      {error && <p className="error">{error}</p>}
      <button className="text-button" onClick={signOut}>
        Cerrar sesión
      </button>
    </div>
  );
}

function PermissionGate({ resource, children }) {
  const { can } = useAuth();

  if (!can(resource, 'read')) {
    return (
      <div className="setup">
        <h1>Acceso limitado</h1>
        <p>No tenés permiso para ver esta sección.</p>
      </div>
    );
  }

  return children;
}

function SuspendedCompany({ companies }) {
  const { signOut, refresh } = useAuth();

  return (
    <div className="setup suspended-screen">
      <span className="brand-mark">D</span>
      <span className="eyebrow">ACCESO SUSPENDIDO</span>
      <h1>El acceso a tu empresa está suspendido</h1>
      <p>
        {companies.map((item) => item.companies.name).join(', ')}. Contactá al administrador del
        servicio para regularizar la cuenta.
      </p>
      <button className="button primary" onClick={refresh}>
        Comprobar estado
      </button>
      <button className="text-button" onClick={signOut}>
        Cerrar sesión
      </button>
    </div>
  );
}

function SupportAccess() {
  const { activeCompany, activeCompanyId, openSupportCompany, signOut } = useAuth();
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function enter(event) {
    event.preventDefault();
    if (busy || reason.trim().length < 8) return;
    setBusy(true);
    setError('');
    try {
      await openSupportCompany(activeCompanyId, reason);
    } catch (cause) {
      setError(friendlyError(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="setup support-entry">
      <ShieldCheck size={32} />
      <h1>Acceso de soporte</h1>
      <p>
        Para consultar {activeCompany?.name}, indicá el motivo. El acceso será de solo lectura y
        quedará registrado.
      </p>
      <form onSubmit={enter}>
        <label className="sr-only" htmlFor="support-reason">
          Motivo de acceso
        </label>
        <input
          id="support-reason"
          required
          minLength={8}
          maxLength={300}
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Ej.: asistencia solicitada por el cliente"
        />
        <button className="button primary" disabled={busy || reason.trim().length < 8}>
          {busy ? 'Ingresando…' : 'Ingresar'}
        </button>
      </form>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <button type="button" className="text-button" onClick={signOut}>
        Cerrar sesión
      </button>
    </div>
  );
}

function Gate() {
  const { user, authLoading, error, memberships, suspendedCompanies, supportNeedsAccess, can } =
    useAuth();

  if (authLoading) {
    return (
      <div className="loading">
        <span className="brand-mark">D</span>
        <p>Preparando tu espacio…</p>
      </div>
    );
  }

  if (!user) return <Navigate to="/login" replace />;

  if (error) {
    return (
      <div className="setup">
        <h1>No pudimos cargar tu acceso</h1>
        <p>{friendlyError(error)}</p>
        <button className="button primary" onClick={() => window.location.reload()}>
          Reintentar
        </button>
      </div>
    );
  }

  if (!memberships.length && suspendedCompanies.length) {
    return <SuspendedCompany companies={suspendedCompanies} />;
  }
  if (!memberships.length) return <SetupCompany />;

  if (supportNeedsAccess) return <SupportAccess />;

  if (!can('dashboard', 'read')) {
    return (
      <div className="setup">
        <h1>Acceso limitado</h1>
        <p>Tu cuenta no tiene permiso para ver el panel. Pedí acceso al administrador.</p>
      </div>
    );
  }

  return <AdminLayout />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<Gate />}>
        <Route index element={<Dashboard />} />
        <Route path="/mi-perfil" element={<ProfilePage />} />
        <Route
          path="/settings/users"
          element={
            <PermissionGate resource="users">
              <UsersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/roles"
          element={
            <PermissionGate resource="roles">
              <RolesPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/units"
          element={
            <PermissionGate resource="units">
              <CatalogPage resource="units" />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/categories"
          element={
            <PermissionGate resource="categories">
              <CatalogPage resource="categories" />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/warehouses"
          element={
            <PermissionGate resource="warehouses">
              <CatalogPage resource="warehouses" />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/items"
          element={
            <PermissionGate resource="items">
              <ItemsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/items/new"
          element={
            <PermissionGate resource="items">
              <ItemEditor />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/items/:itemId"
          element={
            <PermissionGate resource="items">
              <ItemEditor />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/stock"
          element={
            <PermissionGate resource="stock">
              <StockPage />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/movements"
          element={
            <PermissionGate resource="stock">
              <MovementsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/delivery-notes"
          element={
            <PermissionGate resource="stock">
              <DeliveryNotesPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/suppliers"
          element={
            <PermissionGate resource="purchases">
              <SuppliersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/orders"
          element={
            <PermissionGate resource="purchases">
              <PurchaseOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/formulas"
          element={
            <PermissionGate resource="production">
              <FormulasPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/orders"
          element={
            <PermissionGate resource="production">
              <ProductionOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/planning"
          element={
            <PermissionGate resource="production">
              <ProductionPlanningPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/availability"
          element={
            <PermissionGate resource="production">
              <ManufacturingAvailabilityPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/replenishment"
          element={
            <PermissionGate resource="production">
              <ReplenishmentPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/customers"
          element={
            <PermissionGate resource="sales">
              <CustomersPage />
            </PermissionGate>
          }
        />
        <Route path="/sales/prices" element={<Navigate to="/sales/lista-precios" replace />} />
        <Route
          path="/sales/lista-precios"
          element={
            <PermissionGate resource="sales">
              <PriceListPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/orders"
          element={
            <PermissionGate resource="sales">
              <SalesOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/finance/treasury"
          element={
            <PermissionGate resource="finance">
              <TreasuryPage />
            </PermissionGate>
          }
        />
        <Route
          path="/finance/costs"
          element={
            <PermissionGate resource="finance">
              <CostsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/accounts"
          element={
            <PermissionGate resource="purchases">
              <SupplierAccountsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/packaging"
          element={
            <PermissionGate resource="production">
              <PackagingPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/production-documents"
          element={
            <PermissionGate resource="production">
              <ProductionDocumentSettings />
            </PermissionGate>
          }
        />
        <Route
          path="/reports"
          element={
            <PermissionGate resource="reports">
              <ReportsPage />
            </PermissionGate>
          }
        />
        <Route path="/ayuda" element={<GuidePage />} />
        <Route path="/actualizaciones" element={<UpdatesPage />} />
        <Route
          path="/finance/receivables"
          element={
            <PermissionGate resource="finance">
              <ReceivablesPage />
            </PermissionGate>
          }
        />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
