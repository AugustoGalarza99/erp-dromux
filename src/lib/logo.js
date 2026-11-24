/* Lee un logo PNG/JPG/WebP y lo reduce a un PNG chico (data URI) para guardarlo y usarlo en documentos. */
export async function readLogo(file) {
  if (!["image/png", "image/jpeg", "image/webp"].includes(file.type) || file.size > 2_000_000) {
    throw new Error("Seleccioná un logo PNG, JPG o WebP de hasta 2 MB.");
  }
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement("canvas");
  const ratio = Math.min(1, 480 / bitmap.width, 200 / bitmap.height);
  canvas.width = Math.max(1, Math.round(bitmap.width * ratio));
  canvas.height = Math.max(1, Math.round(bitmap.height * ratio));
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const data = canvas.toDataURL("image/png");
  if (data.length > 400000) throw new Error("El logo es demasiado complejo. Usá una imagen más simple.");
  return data;
}
