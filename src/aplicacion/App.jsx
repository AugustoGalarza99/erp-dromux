import ArchivesPage from "../modulos/ajustes/archivados/ArchivesPage";
import SupplierAccountsPage from "../modulos/compras/cuentas-proveedores/SupplierAccountsPage";
import PackagingPage from "../modulos/produccion/envases/PackagingPage";
import ProductionStatsPage from "../modulos/produccion/estadistica/ProductionStatsPage";
import ProductionDocumentSettings from "../modulos/ajustes/documentos-produccion/ProductionDocumentSettings";
import { useState } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { ArrowRight, Building2, Lock, ShieldCheck } from "lucide-react";
import { useAuth } from "../compartido/contextos/AuthContext";
import { createCompany } from "../compartido/servicios/core";
import {
  friendlyError,
  notifyError,
  notifySuccess,
} from "../compartido/utilidades/notifications";
import Login from "../modulos/acceso/Login";
import Dashboard from "../modulos/inicio/Dashboard";
import AdminLayout from "../compartido/componentes/AdminLayout";
import UsersPage from "../modulos/ajustes/usuarios/UsersPage";
import RolesPage from "../modulos/ajustes/roles/RolesPage";
import CatalogPage from "../modulos/ajustes/catalogos/CatalogPage";
import ItemsPage from "../modulos/stock/items/ItemsPage";
import ItemEditor from "../modulos/stock/items/ItemEditor";
import StockPage from "../modulos/stock/existencias/StockPage";
import StockOverview from "../modulos/stock/resumen/StockOverview";
import PurchasesOverview from "../modulos/compras/resumen/PurchasesOverview";
import PurchaseRequestsPage from "../modulos/compras/pedidos-internos/PurchaseRequestsPage";
import ProductionOverview from "../modulos/produccion/resumen/ProductionOverview";
import MovementsPage from "../modulos/stock/movimientos/MovementsPage";
import DeliveryNotesPage from "../modulos/stock/remitos/DeliveryNotesPage";
import SuppliersPage from "../modulos/compras/proveedores/SuppliersPage";
import PurchaseOrdersPage from "../modulos/compras/ordenes-compra/PurchaseOrdersPage";
import FormulasPage from "../modulos/produccion/formulas/FormulasPage";
import ProductionOrdersPage from "../modulos/produccion/ordenes-fabricacion/ProductionOrdersPage";
import ProductionPlanningPage from "../modulos/produccion/planificacion/ProductionPlanningPage";
import ManufacturingAvailabilityPage from "../modulos/produccion/disponibilidad/ManufacturingAvailabilityPage";
import ReplenishmentPage from "../modulos/produccion/reposicion/ReplenishmentPage";
import CustomersPage from "../modulos/ventas/clientes/CustomersPage";
import PriceListsPage from "../modulos/ventas/listas-precios/PriceListsPage";
import SalesOverview from "../modulos/ventas/resumen/SalesOverview";
import QuotesPage from "../modulos/ventas/presupuestos/QuotesPage";
import SalesOrdersPage from "../modulos/ventas/registrar-venta/SalesOrdersPage";
import ReceivablesPage from "../modulos/finanzas/cuentas-por-cobrar/ReceivablesPage";
import TreasuryPage from "../modulos/finanzas/tesoreria/TreasuryPage";
import CostsPage from "../modulos/finanzas/rentabilidad/CostsPage";
import ReportsPage from "../modulos/reportes/ReportsPage";
import GuidePage from "../modulos/ayuda/GuidePage";
import ProfilePage from "../modulos/ajustes/perfil/ProfilePage";
import UpdatesPage from "../modulos/ayuda/UpdatesPage";

function SetupCompany() {
  const { refresh, signOut } = useAuth();
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setBusy(true);
    setError("");

    try {
      await createCompany(name.trim());
      await refresh();
      notifySuccess("Empresa creada", name.trim());
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
      <p>
        Escribí el nombre de tu empresa para comenzar. Tu cuenta tendrá el rol
        administrador.
      </p>

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
          {busy ? "Creando…" : "Crear empresa"}
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

function PermissionGate({ resource, anyOf, action = "ver", adminOnly = false, children }) {
  const { can, role, planIncluye } = useAuth();
  const inPlan = (anyOf ?? [resource]).some((entry) => planIncluye(entry));
  const allowed = (!adminOnly || role === "administrador")
    && (anyOf ?? [resource]).some((entry) => can(entry, action));

  if (!inPlan) {
    return (
      <div className="restricted-screen" role="status">
        <span className="restricted-icon"><Lock size={26} aria-hidden="true" /></span>
        <span className="restricted-chip"><Lock size={13} aria-hidden="true" /> No incluido en tu plan</span>
        <h1>Este módulo no está incluido en tu plan</h1>
        <p>Tu empresa no tiene activado este módulo. Si lo necesitás, consultá con tu proveedor del sistema.</p>
      </div>
    );
  }

  if (!allowed) {
    return (
      <div className="restricted-screen" role="status">
        <span className="restricted-icon"><Lock size={26} aria-hidden="true" /></span>
        <span className="restricted-chip"><Lock size={13} aria-hidden="true" /> Acceso restringido</span>
        <h1>No tenés acceso a esta sección</h1>
        <p>Tu rol no incluye esta pantalla. Si la necesitás para tu trabajo, pedile al administrador de tu empresa que te la habilite.</p>
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
        {companies.map((item) => item.companies.name).join(", ")}. Contactá al
        administrador del servicio para regularizar la cuenta.
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
  const {
    activeCompany,
    activeCompanyId,
    memberships,
    setActiveCompanyId,
    openSupportCompany,
    signOut,
  } = useAuth();
  const ownCompanies = memberships.filter((item) => item.roles?.code !== "soporte");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function enter(event) {
    event.preventDefault();
    if (busy || reason.trim().length < 8) return;
    setBusy(true);
    setError("");
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
        Para trabajar en {activeCompany?.name}, indicá el motivo. Vas a tener
        acceso completo durante 4 horas y el ingreso quedará registrado.
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
        <button
          className="button primary"
          disabled={busy || reason.trim().length < 8}
        >
          {busy ? "Ingresando…" : "Ingresar"}
        </button>
      </form>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      {ownCompanies.map((item) => (
        <button
          key={item.company_id}
          type="button"
          className="text-button"
          onClick={() => setActiveCompanyId(item.company_id)}
        >
          Volver a {item.companies.name}
        </button>
      ))}
      <button type="button" className="text-button" onClick={signOut}>
        Cerrar sesión
      </button>
    </div>
  );
}

function Gate() {
  const {
    user,
    authLoading,
    error,
    memberships,
    suspendedCompanies,
    supportNeedsAccess,
    can,
  } = useAuth();

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
        <button
          className="button primary"
          onClick={() => window.location.reload()}
        >
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

  if (!can("inicio", "ver")) {
    return (
      <div className="setup">
        <h1>Acceso limitado</h1>
        <p>
          Tu cuenta no tiene permiso para ver el panel. Pedí acceso al
          administrador.
        </p>
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
            <PermissionGate resource="usuarios" adminOnly>
              <UsersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/roles"
          element={
            <PermissionGate resource="roles" adminOnly>
              <RolesPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/units"
          element={
            <PermissionGate resource="unidades">
              <CatalogPage resource="unidades" />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/categories"
          element={
            <PermissionGate resource="categorias">
              <CatalogPage resource="categorias" />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/warehouses"
          element={
            <PermissionGate resource="depositos">
              <CatalogPage resource="depositos" />
            </PermissionGate>
          }
        />
        <Route path="/inventory" element={<StockOverview />} />
        <Route
          path="/purchases/requests"
          element={
            <PermissionGate resource="compras_pedidos">
              <PurchaseRequestsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases"
          element={
            <PermissionGate resource="compras_resumen">
              <PurchasesOverview />
            </PermissionGate>
          }
        />
        <Route
          path="/production"
          element={
            <PermissionGate resource="produccion_resumen">
              <ProductionOverview />
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
            <PermissionGate resource="items" action="crear">
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
            <PermissionGate resource="stock_saldos">
              <StockPage />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/movements"
          element={
            <PermissionGate resource="stock_movimientos">
              <MovementsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/inventory/delivery-notes"
          element={
            <PermissionGate resource="stock_remitos">
              <DeliveryNotesPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/suppliers"
          element={
            <PermissionGate resource="compras_proveedores">
              <SuppliersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/orders"
          element={
            <PermissionGate resource="compras_ordenes">
              <PurchaseOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/formulas"
          element={
            <PermissionGate resource="produccion_formulas">
              <FormulasPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/orders"
          element={
            <PermissionGate resource="produccion_ordenes">
              <ProductionOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/planning"
          element={
            <PermissionGate resource="produccion_planificacion">
              <ProductionPlanningPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/availability"
          element={
            <PermissionGate resource="produccion_disponibilidad">
              <ManufacturingAvailabilityPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/replenishment"
          element={
            <PermissionGate resource="produccion_reposicion">
              <ReplenishmentPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales"
          element={
            <PermissionGate resource="ventas">
              <SalesOverview />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/quotes"
          element={
            <PermissionGate resource="ventas">
              <QuotesPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/customers"
          element={
            <PermissionGate resource="ventas">
              <CustomersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/prices"
          element={<Navigate to="/sales/lista-precios" replace />}
        />
        <Route
          path="/sales/lista-precios"
          element={
            <PermissionGate resource="ventas">
              <PriceListsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/sales/orders"
          element={
            <PermissionGate resource="ventas">
              <SalesOrdersPage />
            </PermissionGate>
          }
        />
        <Route
          path="/finance/treasury"
          element={
            <PermissionGate resource="finanzas">
              <TreasuryPage />
            </PermissionGate>
          }
        />
        <Route
          path="/finance/costs"
          element={
            <PermissionGate resource="finanzas">
              <CostsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/purchases/accounts"
          element={
            <PermissionGate resource="compras_cuentas">
              <SupplierAccountsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/packaging"
          element={
            <PermissionGate resource="produccion_envasado">
              <PackagingPage />
            </PermissionGate>
          }
        />
        <Route
          path="/production/stats"
          element={
            <PermissionGate resource="produccion_estadistica">
              <ProductionStatsPage />
            </PermissionGate>
          }
        />
        <Route
          path="/settings/production-documents"
          element={
            <PermissionGate resource="produccion_documentos">
              <ProductionDocumentSettings />
            </PermissionGate>
          }
        />
        <Route path="/archivados" element={<ArchivesPage />} />
        <Route
          path="/reports"
          element={
            <PermissionGate resource="reportes">
              <ReportsPage />
            </PermissionGate>
          }
        />
        <Route path="/ayuda" element={<GuidePage />} />
        <Route path="/actualizaciones" element={<UpdatesPage />} />
        <Route
          path="/finance/receivables"
          element={
            <PermissionGate resource="finanzas">
              <ReceivablesPage />
            </PermissionGate>
          }
        />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
