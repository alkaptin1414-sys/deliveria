const EGYPT_MOBILE = /^01[0125]\d{8}$/;

export function normalizeEgyptPhone(input: string): string | null {
  const digits = input.replace(/[^\d]/g, '');
  let local = digits;
  if (local.startsWith('0020')) local = local.slice(4);
  else if (local.startsWith('20') && local.length === 12) local = `0${local.slice(2)}`;
  else if (local.startsWith('1') && local.length === 10) local = `0${local}`;
  if (!EGYPT_MOBILE.test(local)) return null;
  return `+20${local.slice(1)}`;
}

export function formatEgyptPhone(e164: string): string {
  const local = e164.replace('+20', '0');
  return `${local.slice(0, 3)} ${local.slice(3, 7)} ${local.slice(7)}`;
}
