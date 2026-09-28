# Dromux ERP · centro operativo y perfiles (versión 023)

## Instalar

1. Conservá una copia de tu proyecto local y de la base de prueba.
2. Descomprimí `erp-dromux-produccion-023.zip` y copiá el contenido de `erp-dromux/` sobre la raíz de tu proyecto. **Conservá tu `.env.local`**: el ZIP no incluye claves ni modifica las variables que ya configuraste.
3. En Supabase SQL Editor del entorno de prueba, ejecutá `supabase/023_centro_operativo.sql` **una sola vez**, después de `supabase/022_remitos_produccion.sql`. Crea una tabla de avisos leídos con permisos por usuario y una consulta protegida de avisos operativos.
4. En la carpeta local ejecutá `npm install` y `npm run dev`. Para verificar la compilación, ejecutá `npm run build`.

## Qué cambia

- **Inicio:** órdenes en fabricación, en cola y vencidas; stock bajo mínimo, compras abiertas, avisos y enlaces a cada orden. Los datos que aparecen dependen de los permisos del usuario.
- **Campana de avisos:** arriba a la derecha. Muestra ítems activos con mínimo configurado cuyo stock físico es inferior al mínimo y órdenes con vencimiento próximo (tres días) o atrasadas. Se consulta al abrir, al volver a la ventana y aproximadamente cada minuto mientras la aplicación está abierta. «Leído» se guarda por usuario y empresa. Si cambia la cantidad o fecha de una alerta, vuelve a marcarse como nueva. Las alertas resueltas desaparecen; no hay mensajes externos ni correo en esta fase.
- **Mi perfil:** al pie del menú o al pulsar el avatar. Guarda nombre y teléfono en el perfil personal; el correo figura como dato de acceso de solo lectura. Para cambiar la contraseña pide la actual y una nueva de al menos 12 caracteres. El perfil no altera el nombre de la empresa ni los permisos del rol.

## Comprobaciones recomendadas

1. Configurá un mínimo mayor al saldo para una materia prima. Abrí Inicio y la campana; confirmá el aviso y su enlace al stock. Marcalo leído. Abrí sesión con otro usuario de la misma empresa: su aviso debe seguir sin leer.
2. Registrá una orden con fecha de ayer y otra para dentro de tres días; verificá el recuento, el aviso y el acceso a la orden. Cerrá una orden y actualizá: el aviso debe desaparecer.
3. Cambiá la cantidad disponible mediante un movimiento válido: el aviso leído debe reaparecer por el nuevo saldo; al superar el mínimo desaparece.
4. En Mi perfil cambiá nombre y teléfono, actualizá la página y comprobá que persisten. Cambiá contraseña y volvé a iniciar sesión con la nueva. Si tu política de autenticación requiere verificación adicional, seguí la indicación que aparezca en la cuenta.
5. Probá un operario sin lectura de stock y un usuario de otra empresa: solo deben ver avisos y cifras permitidos de su propia empresa. Revisá Inicio, menú y campana a 360 px de ancho.

**Alcance actual:** la disponibilidad del aviso es física; todavía no contempla reservas ni fechas de consumo. «¿Tengo stock para fabricar?» y «¿En cuántos días se agota?» requieren las fases 1 y 2 de `HOJA-DE-RUTA-PRODUCCION.md`. No se ejecutó el SQL en tu instancia remota desde esta entrega.
