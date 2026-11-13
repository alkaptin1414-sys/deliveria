export function platformMinorFromBps(feeMinor: number, bps: number): number {
  if (!Number.isInteger(feeMinor) || feeMinor < 0 || !Number.isInteger(bps) || bps < 0 || bps > 10000) {
    throw new Error('INVALID_COMMISSION');
  }
  return Math.round((feeMinor * bps) / 10000);
}

export function minorToLabel(minor: number): string {
  const pounds = minor / 100;
  const text = Number.isInteger(pounds) ? String(pounds) : pounds.toFixed(2);
  return `${text} ج.م`;
}

export function publicOrderNumber(now = new Date()): string {
  const y = String(now.getFullYear()).slice(2);
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const rand = Math.floor(1000 + Math.random() * 9000);
  return `DL-${y}${m}${d}-${rand}`;
}
