import { useEffect, useRef, useState } from "react";
import { Trash2 } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "../contexts/AuthContext";
import {
  cleanupPreview,
  cleanupRecord,
  cleanupResources,
  refreshCleanupData,
} from "../services/cleanup";
import { notifyError, notifySuccess } from "../lib/notifications";
import ConfirmDeleteDialog from "./ConfirmDeleteDialog";
import "./cleanup.css";

export default function CleanupButton({ resource, id, label, onRemoved }) {
  const { activeCompanyId, can } = useAuth();
  const client = useQueryClient();
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const company = useRef(activeCompanyId);
  company.current = activeCompanyId;
  useEffect(() => {
    setPreview(null);
  }, [activeCompanyId, id]);
  const permission = cleanupResources.find(
    (entry) => entry.value === resource,
  )?.permission;
  if (!permission || !can(permission, "delete")) return null;

  async function review(event) {
    event.preventDefault();
    event.stopPropagation();
    if (busy) return;
    const targetCompany = activeCompanyId;
    setBusy(true);
    try {
      const data = await cleanupPreview(targetCompany, resource, id);
      if (company.current !== targetCompany) return;
      if (data.action === "blocked") throw new Error(data.message);
      setPreview(data);
    } catch (error) {
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  async function confirm() {
    if (busy || !preview) return;
    setBusy(true);
    try {
      const result = await cleanupRecord(
        activeCompanyId,
        resource,
        id,
        preview.action,
      );
      setPreview(null);
      await refreshCleanupData(client);
      notifySuccess(
        result === "archive" ? "Registro archivado" : "Registro eliminado",
        label,
      );
      await onRemoved?.();
    } catch (error) {
      setPreview(null);
      notifyError(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <button
        type="button"
        className="button outline cleanup-action"
        disabled={busy}
        aria-label={`Eliminar o archivar ${label}`}
        onClick={review}
      >
        <Trash2 size={15} />
        <span>{busy ? "Revisando…" : "Eliminar"}</span>
      </button>
      {preview && (
        <ConfirmDeleteDialog
          open
          busy={busy}
          title={
            preview.action === "archive"
              ? "¿Seguro que querés archivar?"
              : "¿Seguro que querés eliminar?"
          }
          description={`${label}. ${preview.message}`}
          confirmLabel={
            preview.action === "archive"
              ? "Archivar"
              : "Eliminar definitivamente"
          }
          onCancel={() => setPreview(null)}
          onConfirm={confirm}
        />
      )}
    </>
  );
}
