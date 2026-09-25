// PostgreSQL envía numeric como texto: evitamos perder fracciones al mostrarlo.
export function formatQuantity(value) {
  const raw = String(value ?? '0');
  const negative = raw.startsWith('-');
  const [integer, fractional = ''] = (negative ? raw.slice(1) : raw).split('.');
  const grouped = (integer || '0').replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const decimals = fractional.replace(/0+$/, '');

  return `${negative ? '−' : ''}${grouped}${decimals ? `,${decimals}` : ''}`;
}

export function isAtOrBelow(value, threshold) {
  const scaled = (number) => {
    const raw = String(number ?? '0');
    const [integer, fractional = ''] = raw.split('.');
    return BigInt(integer || '0') * 1_000_000n
      + BigInt(fractional.padEnd(6, '0').slice(0, 6) || '0');
  };

  return scaled(value) <= scaled(threshold);
}

export function subtractQuantity(total, received) {
  const toMicro = (value) => {
    const [integer, fractional = ''] = String(value ?? 0).split('.');
    return BigInt(integer || '0') * 1_000_000n
      + BigInt(fractional.padEnd(6, '0').slice(0, 6) || '0');
  };

  const difference = toMicro(total) - toMicro(received);
  const whole = difference / 1_000_000n;
  const fraction = (difference % 1_000_000n).toString().padStart(6, '0')
    .replace(/0+$/, '');
  return fraction ? `${whole}.${fraction}` : String(whole);
}
