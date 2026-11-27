// Reescritura de SQL/PLpgSQL: tablas, columnas y valores guardados.
// No usa reemplazos ciegos: separa el texto en piezas y resuelve a qué tabla
// pertenece cada nombre. Lo que no puede decidir queda en el informe.

const REGLAS = [
  ['espacio', /\s+/y],
  ['comentario', /--[^\n]*/y],
  ['comentario', /\/\*[\s\S]*?\*\//y],
  ['cadena', /[Ee]'(?:\\.|''|[^'\\])*'/y],
  ['cadena', /'(?:''|[^'])*'/y],
  ['dolar', /\$([A-Za-z_]*)\$[\s\S]*?\$\1\$/y],
  ['citado', /"(?:""|[^"])*"/y],
  ['parametro', /\$\d+/y],
  ['numero', /\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/y],
  ['palabra', /[A-Za-z_\u0080-\uffff][A-Za-z0-9_$\u0080-\uffff]*/y],
  ['signo', /::|:=|<>|!=|>=|<=|=>|\|\||->>|->|#>>|#>|@>|<@|\.\.|[\s\S]/y],
];

export function tokenizar(texto) {
  const tokens = [];
  let posicion = 0;
  while (posicion < texto.length) {
    for (const [tipo, regla] of REGLAS) {
      regla.lastIndex = posicion;
      const hallado = regla.exec(texto);
      if (hallado) {
        tokens.push({ tipo, texto: hallado[0] });
        posicion = regla.lastIndex;
        break;
      }
    }
  }
  return tokens;
}

const RESERVADAS = new Set(
  ('where set join on left right inner outer full cross lateral order group limit offset for union intersect except ' +
    'returning values using when then else end loop into from and or not as select insert update delete conflict do ' +
    'having window natural if begin case in is null exists with of share nowait skip to only').split(' '),
);

const FUNCIONES_CON_VALORES = {
  has_permission: { 1: 'role_permissions.resource', 2: 'role_permissions.action' },
  cleanup_has_references: { 1: 'cleanup.p_resource' },
  cleanup_target: { 0: 'cleanup.p_resource' },
  log_access_event: { 1: 'access_audit_events.action' },
  post_stock_operation: { 4: 'stock_operations.kind' },
  post_treasury_entry: { 2: 'treasury_entries.kind' },
  price_compute: { 0: 'price_list_item_pricing.method' },
  price_write: { 4: 'price_list_item_pricing.method', 8: 'price_list_item_history.source' },
};

export function reescribir(texto, contexto) {
  const { modelo, nombre, informe } = contexto;
  const tokens = tokenizar(texto);
  const s = tokens.filter((t) => t.tipo !== 'espacio' && t.tipo !== 'comentario');
  const bajo = (i) => (s[i] && s[i].tipo === 'palabra' ? s[i].texto.toLowerCase() : s[i]?.texto);
  const esPalabra = (i) => s[i]?.tipo === 'palabra';
  const esColumna = (palabra) => palabra in modelo.mapa.columnas;

  const avisar = (i, motivo) => {
    const trozo = s.slice(Math.max(0, i - 9), i + 5).map((t) => t.texto).join(' ');
    informe.push({ objeto: nombre, motivo, pieza: s[i].texto, trozo });
  };

  // Paréntesis: grupo que contiene cada pieza.
  const grupo = new Array(s.length).fill(-1);
  const cierre = new Map();
  const padre = new Map([[-1, null]]);
  const pila = [-1];
  for (let i = 0; i < s.length; i += 1) {
    grupo[i] = pila[pila.length - 1];
    if (s[i].texto === '(' || s[i].texto === '[') {
      padre.set(i, grupo[i]);
      pila.push(i);
    } else if ((s[i].texto === ')' || s[i].texto === ']') && pila.length > 1) {
      const abre = pila.pop();
      cierre.set(abre, i);
      grupo[i] = grupo[abre];
    }
  }

  // Sentencias separadas por ";" fuera de paréntesis.
  const sentencia = new Array(s.length);
  const sentencias = [];
  let inicio = 0;
  for (let i = 0; i < s.length; i += 1) {
    sentencia[i] = sentencias.length;
    if (s[i].texto === ';' && grupo[i] === -1) {
      sentencias.push([inicio, i]);
      inicio = i + 1;
    }
  }
  sentencias.push([inicio, s.length]);

  // Referencias a tablas.
  const tablaEn = new Map();
  for (let i = 0; i + 2 < s.length; i += 1) {
    if ((bajo(i) === 'public' || bajo(i) === 'private') && s[i + 1].texto === '.' && esPalabra(i + 2)) {
      const tabla = modelo.tablas.get(`${bajo(i)}.${bajo(i + 2)}`);
      if (tabla && s[i + 3]?.texto !== '(') tablaEn.set(i + 2, tabla);
      else if (tabla && ['into', 'references', 'on'].includes(bajo(i - 1))) tablaEn.set(i + 2, tabla);
    }
  }

  // Tablas del sistema (auth, pg_catalog): sus columnas no cambian.
  const externaEn = new Set();
  for (let i = 0; i + 2 < s.length; i += 1) {
    if (['auth', 'pg_catalog', 'information_schema'].includes(bajo(i)) && s[i + 1].texto === '.' &&
        s[i + 3]?.texto !== '(' && ['from', 'join'].includes(bajo(i - 1))) externaEn.add(i + 2);
  }
  // En políticas, índices y restricciones las tablas pueden venir sin esquema.
  if (contexto.tablaBase) {
    for (let i = 1; i < s.length; i += 1) {
      if (!['from', 'join'].includes(bajo(i - 1)) || !esPalabra(i)) continue;
      if (s[i + 1]?.texto === '.' || s[i + 1]?.texto === '(') continue;
      const tabla = modelo.tablas.get(`public.${bajo(i)}`);
      if (tabla) tablaEn.set(i, tabla);
    }
  }

  // Variables declaradas.
  const variables = new Map(contexto.variables ?? []);
  for (let i = 0; i < s.length; i += 1) {
    if (bajo(i) !== 'declare') continue;
    let j = i + 1;
    while (j < s.length && bajo(j) !== 'begin') {
      if (esPalabra(j)) {
        const variable = bajo(j);
        let fin = j;
        let tabla = null;
        let esRegistro = false;
        while (fin < s.length && !(s[fin].texto === ';' && grupo[fin] === -1)) {
          if (tablaEn.has(fin) && s[fin + 1]?.texto === '%') tabla = tablaEn.get(fin);
          if (bajo(fin) === 'record') esRegistro = true;
          fin += 1;
        }
        variables.set(variable, { tabla, esRegistro, origen: null });
        j = fin + 1;
      } else j += 1;
    }
  }

  // Enlaces (alias) por sentencia y grupo de paréntesis.
  const enlaces = new Map();
  const enlazar = (n, g, alias, valor) => {
    const clave = `${n}:${g}`;
    if (!enlaces.has(clave)) enlaces.set(clave, new Map());
    const mapa = enlaces.get(clave);
    if (!mapa.has(alias)) mapa.set(alias, []);
    mapa.get(alias).push(valor);
  };
  // Alias sin "as": "tabla.columna alias," o "expresion) alias from".
  const esAliasImplicito = (i) =>
    esPalabra(i) && !RESERVADAS.has(bajo(i)) && ['from', ','].includes(bajo(i + 1)) &&
    (s[i - 1]?.texto === ')' || (esPalabra(i - 1) && s[i - 2]?.texto === '.' && !RESERVADAS.has(bajo(i - 1)))) &&
    !tablaEn.has(i - 1) && !tablaEn.has(i);
  const aliasExplicitos = (desde, hasta, nivel) => {
    const hallados = new Set();
    for (let i = desde; i < hasta; i += 1) {
      if (grupo[i] === nivel && esAliasImplicito(i)) hallados.add(bajo(i));
      if (bajo(i) === 'as' && grupo[i] === nivel && esPalabra(i + 1) && s[i + 2]?.texto !== '(') {
        hallados.add(bajo(i + 1));
      }
    }
    return hallados;
  };

  const definiciones = new Set(); // nombres en listas "alias(col, col)": no se renombran
  const ctes = new Map();
  for (let i = 0; i < s.length; i += 1) {
    const abre = ['materialized'].includes(bajo(i + 3)) ? i + 4 : i + 3;
    if (['with', ',', 'recursive'].includes(bajo(i)) && esPalabra(i + 1) && bajo(i + 2) === 'as' && s[abre]?.texto === '(') {
      const fin = cierre.get(abre) ?? abre;
      ctes.set(`${sentencia[i]}:${bajo(i + 1)}`, { explicitos: aliasExplicitos(abre + 1, fin, abre), abre, fin });
    }
  }

  for (let i = 0; i < s.length; i += 1) {
    const n = sentencia[i];
    if (tablaEn.has(i) && s[i + 1]?.texto !== '%') {
      const tabla = tablaEn.get(i);
      enlazar(n, grupo[i], tabla.viejo, { tabla });
      let j = i + 1;
      if (bajo(j) === 'as') j += 1;
      if (esPalabra(j) && !RESERVADAS.has(bajo(j))) enlazar(n, grupo[i], bajo(j), { tabla });
    }
    // Función usada como tabla: sus columnas de salida no cambian de nombre.
    if (['public', 'private'].includes(bajo(i)) && s[i + 1]?.texto === '.' && s[i + 3]?.texto === '(') {
      const salida = contexto.salidas?.get(bajo(i + 2));
      const fin = cierre.get(i + 3);
      if (salida && fin !== undefined) {
        let j = fin + 1;
        if (bajo(j) === 'as') j += 1;
        const derivada = { explicitos: new Set(salida) };
        enlazar(n, grupo[i], bajo(i + 2), { derivada });
        if (esPalabra(j) && !RESERVADAS.has(bajo(j))) enlazar(n, grupo[i], bajo(j), { derivada });
      }
    }
    if (externaEn.has(i)) {
      let j = i + 1;
      if (bajo(j) === 'as') j += 1;
      enlazar(n, grupo[i], bajo(i), { externa: true });
      if (esPalabra(j) && !RESERVADAS.has(bajo(j))) enlazar(n, grupo[i], bajo(j), { externa: true });
    }
    // Consultas usadas como tabla: ( ... ) alias
    if (s[i].texto === '(' && cierre.has(i)) {
      const fin = cierre.get(i);
      let j = fin + 1;
      if (bajo(j) === 'as') j += 1;
      if (!esPalabra(j) || RESERVADAS.has(bajo(j))) continue;
      const consulta = s.slice(i + 1, fin).some((t, k) => grupo[i + 1 + k] === i && ['select', 'values'].includes(t.texto.toLowerCase()));
      const enFrom = ['from', 'join', 'lateral', ','].includes(bajo(i - 1)) ||
        (esPalabra(i - 1) && ['from', 'join', 'lateral', ',', '.'].includes(bajo(i - 2)));
      if (!consulta && !enFrom) continue;
      const explicitos = consulta ? aliasExplicitos(i + 1, fin, i) : new Set();
      if (s[j + 1]?.texto === '(' && cierre.has(j + 1)) {
        for (let k = j + 2; k < cierre.get(j + 1); k += 1) {
          if (grupo[k] === j + 1 && ['(', ','].includes(s[k - 1].texto) && esPalabra(k)) {
            explicitos.add(bajo(k));
            definiciones.add(k);
          }
        }
      }
      enlazar(n, grupo[i], bajo(j), { derivada: { explicitos, abre: i, fin } });
    }
    if (['from', 'join'].includes(bajo(i)) && esPalabra(i + 1)) {
      const cte = ctes.get(`${n}:${bajo(i + 1)}`);
      if (cte) {
        enlazar(n, grupo[i], bajo(i + 1), { derivada: cte });
        let j = i + 2;
        if (bajo(j) === 'as') j += 1;
        if (esPalabra(j) && !RESERVADAS.has(bajo(j))) enlazar(n, grupo[i], bajo(j), { derivada: cte });
      }
    }
  }

  // Origen de las variables record.
  for (let i = 0; i < s.length; i += 1) {
    const [desde, hasta] = sentencias[sentencia[i]];
    if (bajo(i) === 'for' && esPalabra(i + 1) && bajo(i + 2) === 'in') {
      let fin = i + 3;
      while (fin < s.length && !(bajo(fin) === 'loop' && grupo[fin] === -1)) fin += 1;
      const variable = variables.get(bajo(i + 1)) ?? { tabla: null, esRegistro: true, origen: null };
      variable.origen = { explicitos: aliasExplicitos(i + 3, fin, -1) };
      variables.set(bajo(i + 1), variable);
    }
    if (bajo(i) === 'into' && esPalabra(i + 1)) {
      const variable = variables.get(bajo(i + 1));
      if (variable?.esRegistro) {
        const explicitos = aliasExplicitos(desde, hasta, -1);
        // "select * into r from funcion()": los campos son las columnas que devuelve la función.
        for (let k = desde; k < hasta; k += 1) {
          if (s[k + 1]?.texto !== '(') continue;
          for (const columna of contexto.salidas?.get(bajo(k)) ?? []) explicitos.add(columna);
        }
        variable.origen = { explicitos };
      }
    }
  }

  const baseDisparador = contexto.tablasDisparador ?? [];
  const cadena = (i) => {
    const niveles = [];
    let g = grupo[i];
    while (g !== null && g !== undefined) {
      niveles.push(enlaces.get(`${sentencia[i]}:${g}`));
      g = padre.get(g);
    }
    if (contexto.tablaBase) {
      niveles.push(new Map([[contexto.tablaBase.viejo, [{ tabla: contexto.tablaBase }]]]));
    }
    return niveles;
  };

  // Un alias que pasa de una consulta interna a la externa conserva su nombre.
  const derivadas = [];
  for (const [clave, mapaAlias] of enlaces) {
    const g = Number(clave.split(':')[1]);
    for (const opciones of mapaAlias.values()) {
      for (const o of opciones) if (o.derivada && g !== undefined) derivadas.push(o.derivada);
    }
  }
  derivadas.push(...ctes.values());
  for (let vuelta = 0; vuelta < 3; vuelta += 1) {
    for (const derivada of derivadas) {
      if (derivada.abre === undefined) continue;
      for (let i = derivada.abre + 1; i < derivada.fin; i += 1) {
        if (grupo[i] !== derivada.abre) continue;
        if (bajo(i) === 'from') break;
        if (s[i].texto === '*' && ['select', ',', '.'].includes(bajo(i - 1))) {
          for (let k = derivada.abre + 1; k < derivada.fin; k += 1) {
            if (grupo[k] !== derivada.abre) continue;
            for (const opciones of enlaces.get(`${sentencia[i]}:${derivada.abre}`)?.values() ?? []) {
              for (const o of opciones) for (const a of o.derivada?.explicitos ?? []) derivada.explicitos.add(a);
            }
            break;
          }
        }
        if (s[i - 1]?.texto !== '.' || !['from', ','].includes(bajo(i + 1))) continue;
        for (const nivel of cadena(i)) {
          const opciones = nivel?.get(bajo(i - 2));
          if (!opciones) continue;
          if (opciones.some((o) => o.derivada?.explicitos.has(bajo(i)))) derivada.explicitos.add(bajo(i));
          break;
        }
      }
    }
  }

  // Tabla destino de la sentencia (insert / update).
  const destino = (i) => {
    const [desde] = sentencias[sentencia[i]];
    for (let k = i; k >= desde; k -= 1) {
      if (tablaEn.has(k) && ['into', 'update'].includes(bajo(k - 3))) return tablaEn.get(k);
    }
    return null;
  };

  const referencias = new Map();
  const renombrar = (i, columna, tabla) => {
    const nueva = tabla ? modelo.columnaNueva(tabla, columna) : modelo.mapa.columnas[columna];
    referencias.set(i, { tabla, columna });
    s[i].nuevo = nueva;
  };

  // Listas de columnas de INSERT y ON CONFLICT.
  const listaDe = new Map();
  for (const [i, tabla] of tablaEn) {
    if (bajo(i - 3) !== 'into') continue;
    let j = i + 1;
    if (bajo(j) === 'as') j += 2;
    else if (esPalabra(j) && !RESERVADAS.has(bajo(j))) j += 1;
    if (s[j]?.texto === '(') listaDe.set(j, tabla);
  }
  for (let i = 0; i < s.length; i += 1) {
    if (bajo(i) === 'conflict' && s[i + 1]?.texto === '(') {
      const tabla = destino(i);
      if (tabla) listaDe.set(i + 1, tabla);
    }
  }

  for (let i = 0; i < s.length; i += 1) {
    if (!esPalabra(i)) continue;
    const palabra = bajo(i);
    if (!esColumna(palabra) || tablaEn.has(i) || definiciones.has(i)) continue;
    const anterior = bajo(i - 1);
    const siguiente = bajo(i + 1);

    if (listaDe.has(grupo[i])) {
      renombrar(i, palabra, listaDe.get(grupo[i]));
      continue;
    }

    if (anterior === '.') {
      const calificador = bajo(i - 2);
      if (['public', 'private', 'pg_catalog', 'auth', 'extensions'].includes(calificador) || siguiente === '(') continue;
      if (calificador === 'excluded') {
        renombrar(i, palabra, destino(i));
        continue;
      }
      if (calificador === 'new' || calificador === 'old') {
        const tabla = baseDisparador.find((t) => t.columnas.has(palabra));
        if (!tabla) avisar(i, 'new/old sin tabla');
        renombrar(i, palabra, tabla ?? null);
        continue;
      }
      let resuelto = false;
      for (const nivel of cadena(i)) {
        const opciones = nivel?.get(calificador);
        if (!opciones) continue;
        const conTabla = opciones.find((o) => o.tabla?.columnas.has(palabra));
        const derivada = opciones.find((o) => o.derivada);
        if (opciones.some((o) => o.externa)) {
          resuelto = true;
          break;
        }
        if (derivada) {
          if (!derivada.derivada.explicitos.has(palabra)) renombrar(i, palabra, null);
        } else if (conTabla) {
          renombrar(i, palabra, conTabla.tabla);
          // "tabla.columna" sin alias: el calificador también cambia de nombre.
          if (calificador === conTabla.tabla.viejo && !tablaEn.has(i - 2)) s[i - 2].nuevo = conTabla.tabla.nuevo;
        }
        else avisar(i, `la tabla de "${calificador}" no tiene la columna`);
        resuelto = true;
        break;
      }
      if (resuelto) continue;
      const variable = variables.get(calificador);
      if (variable) {
        if (variable.tabla) renombrar(i, palabra, variable.tabla);
        else if (!variable.origen?.explicitos.has(palabra)) renombrar(i, palabra, null);
        continue;
      }
      if (ctes.has(`${sentencia[i]}:${calificador}`)) {
        if (!ctes.get(`${sentencia[i]}:${calificador}`).explicitos.has(palabra)) renombrar(i, palabra, null);
        continue;
      }
      avisar(i, `calificador desconocido "${calificador}"`);
      continue;
    }

    if (siguiente === '.' || siguiente === '(' || anterior === 'as' || anterior === '::') continue;
    if (siguiente === ':=' || siguiente === '=>') continue;
    if (esAliasImplicito(i) && !listaDe.has(grupo[i])) continue;
    if (['using', ','].includes(anterior) && siguiente === '=' && ['detail', 'hint', 'message', 'errcode'].includes(palabra)) continue;

    // Lado izquierdo de SET en un UPDATE.
    if (siguiente === '=' && (anterior === 'set' || anterior === ',')) {
      const [desde] = sentencias[sentencia[i]];
      let esAsignacion = false;
      for (let k = i - 1; k >= desde; k -= 1) {
        if (grupo[k] !== grupo[i]) continue;
        if (bajo(k) === 'where') break;
        if (bajo(k) === 'set') { esAsignacion = true; break; }
      }
      const tabla = esAsignacion ? destino(i) : null;
      if (tabla?.columnas.has(palabra)) {
        renombrar(i, palabra, tabla);
        continue;
      }
    }

    let decidido = false;
    for (const nivel of cadena(i)) {
      if (!nivel) continue;
      const opciones = [...nivel.values()].flat();
      const conTabla = opciones.find((o) => o.tabla?.columnas.has(palabra));
      if (conTabla) {
        renombrar(i, palabra, conTabla.tabla);
        decidido = true;
        break;
      }
      const derivadas = opciones.filter((o) => o.derivada);
      if (palabra === 'name' && opciones.some((o) => o.externa)) {
        decidido = true;
        break;
      }
      if (derivadas.length) {
        if (!derivadas.some((o) => o.derivada.explicitos.has(palabra)) && !variables.has(palabra)) {
          renombrar(i, palabra, null);
        }
        decidido = true;
        break;
      }
    }
    if (decidido || variables.has(palabra)) continue;
    const [desde, hasta] = sentencias[sentencia[i]];
    let esAlias = false;
    for (let k = desde; k < hasta; k += 1) if (bajo(k) === 'as' && bajo(k + 1) === palabra) esAlias = true;
    if (!esAlias) avisar(i, 'columna sin resolver');
  }

  traducirValores();

  for (const [i, tabla] of tablaEn) {
    if (!tabla.nuevo) avisar(i, 'usa una tabla que no pasa a la base nueva');
    else s[i].nuevo = tabla.nuevo;
  }
  return tokens.map((t) => t.nuevo ?? t.texto).join('');

  function dominioDe(i) {
    if (i < 0 || !esPalabra(i)) return null;
    if (bajo(i) === 'get_user_role') return 'roles.code';
    if (s[i - 1]?.texto === '.') {
      const campo = contexto.dominiosVariables?.[`${bajo(i - 2)}.${bajo(i)}`];
      if (campo) return campo;
    }
    const ref = referencias.get(i);
    if (ref?.tabla) return `${ref.tabla.viejo}.${ref.columna}`;
    const variable = contexto.dominiosVariables?.[bajo(i)];
    if (variable && s[i - 1]?.texto !== '.') return variable;
    if (ref) {
      const candidatos = Object.keys(modelo.mapa.valores).filter((k) => k.endsWith(`.${ref.columna}`));
      if (candidatos.length === 1) return candidatos[0];
    }
    return contexto.dominiosVariables?.[bajo(i)] ?? null;
  }

  // Operando anterior a una comparación: salta casts y cierres de función simples.
  function operando(k) {
    let j = k;
    while (j > 1 && s[j - 1]?.texto === '::') j -= 2;
    if (s[j]?.texto === ')') {
      let abre = j;
      for (const [a, c] of cierre) if (c === j) abre = a;
      if (bajo(abre - 1) === 'get_user_role') return abre - 1;
      for (let m = j - 1; m > abre; m -= 1) if (dominioDe(m)) return m;
      return -1;
    }
    return j;
  }

  function dominioPorContexto(i) {
    const previo = bajo(i - 1);
    if (previo === 'when') {
      const porCaso = dominioCaso(i, previo);
      if (porCaso) return porCaso;
    }
    if (['=', '<>', '!=', ':=', '<@'].includes(previo)) {
      const d = dominioDe(operando(i - 2));
      if (d) return d;
    }
    if (previo === 'from' && bajo(i - 2) === 'distinct') {
      const k = bajo(i - 3) === 'not' ? i - 5 : i - 4;
      return dominioDe(operando(k));
    }
    if (['=', '<>', '!='].includes(bajo(i + 1))) {
      const d = dominioDe(i + 2) ?? dominioDe(i + 4);
      if (d) return d;
    }
    // Listas: in (...), array[...]
    let g = grupo[i];
    while (g !== null && g !== undefined && g >= 0) {
      if (bajo(g - 1) === 'in') {
        const k = bajo(g - 2) === 'not' ? g - 3 : g - 2;
        return dominioDe(operando(k));
      }
      if (s[g].texto === '[' && bajo(g - 1) === 'array') {
        let k = g - 2;
        while (k > 0 && ['(', 'any', 'all'].includes(bajo(k))) k -= 1;
        if (['=', '<>', '!=', '<@'].includes(bajo(k))) return dominioDe(operando(k - 1));
        break;
      }
      if (esPalabra(g - 1) && FUNCIONES_CON_VALORES[bajo(g - 1)]) {
        let posicion = 0;
        for (let k = g + 1; k < i; k += 1) if (grupo[k] === g && s[k].texto === ',') posicion += 1;
        const d = FUNCIONES_CON_VALORES[bajo(g - 1)][posicion];
        if (d) return d;
      }
      g = padre.get(g);
    }
    // Valores de un INSERT, por posición.
    const insercion = dominioInsercion(i);
    if (insercion) return insercion;
    return dominioCaso(i, previo);
  }

  // case x when 'a' then 'b' else 'c' end
  function dominioCaso(i, previo) {
    const [desde] = sentencias[sentencia[i]];
    let profundidad = 0;
    for (let k = i - 1; k >= desde; k -= 1) {
      if (bajo(k) === 'end') profundidad += 1;
      if (bajo(k) !== 'case') continue;
      if (profundidad > 0) { profundidad -= 1; continue; }
      if (previo === 'when' && bajo(k + 1) !== 'when') {
        let m = k + 1;
        while (bajo(m + 1) !== 'when') m += 1;
        return dominioDe(m);
      }
      if (previo === 'then' || previo === 'else') {
        if (['=', ':='].includes(bajo(k - 1))) return dominioDe(k - 2);
      }
      break;
    }
    return null;
  }

  function dominioInsercion(i) {
    let g = grupo[i];
    while (g !== null && g !== undefined && g >= 0 && bajo(g - 1) !== 'values') g = padre.get(g);
    if (g === null || g === undefined || g < 0) return null;
    const tabla = destino(g);
    if (!tabla) return null;
    let posicion = 0;
    for (let k = g + 1; k < i; k += 1) if (grupo[k] === g && s[k].texto === ',') posicion += 1;
    for (const [abre, t] of listaDe) {
      if (t !== tabla || sentencia[abre] !== sentencia[i] || bajo(abre - 1) === 'conflict') continue;
      let n = 0;
      for (let k = abre + 1; k < cierre.get(abre); k += 1) {
        if (grupo[k] !== abre || !esPalabra(k)) continue;
        if (n === posicion) return `${tabla.viejo}.${bajo(k)}`;
        n += 1;
      }
    }
    return null;
  }

  // Las claves de jsonb_build_object son el contrato con la aplicación: no cambian.
  function esClaveJson(i) {
    const g = grupo[i];
    if (g < 1 || !['jsonb_build_object', 'json_build_object'].includes(bajo(g - 1))) return false;
    if (![g, undefined].includes(i - 1) && s[i - 1].texto !== ',') return false;
    if (s[i + 1]?.texto !== ',') return false;
    let posicion = 0;
    for (let k = g + 1; k < i; k += 1) if (grupo[k] === g && s[k].texto === ',') posicion += 1;
    return posicion % 2 === 0;
  }

  function traducirValores() {
    const todos = new Set();
    for (const clave of Object.keys(modelo.mapa.valores)) {
      for (const valor of Object.keys(modelo.dominio(clave) ?? {})) todos.add(valor);
    }
    for (let i = 0; i < s.length; i += 1) {
      if (s[i].tipo !== 'cadena' || !s[i].texto.startsWith("'")) continue;
      const valor = s[i].texto.slice(1, -1);
      if (!todos.has(valor)) continue;
      if (esClaveJson(i)) continue;
      const dominio = contexto.literales?.[valor] ?? contexto.dominioFijo ?? dominioPorContexto(i);
      if (dominio === null) {
        avisar(i, 'valor sin contexto');
        continue;
      }
      if (dominio === '-' || valor === 'all') continue;
      const tabla = modelo.dominio(dominio);
      if (!tabla) continue;
      if (!(valor in tabla)) {
        avisar(i, `valor fuera del dominio ${dominio}`);
        continue;
      }
      s[i].nuevo = `'${tabla[valor]}'`;
    }
  }
}
