export function formatKSh(amount: number): string {
  return (
    'KSh ' +
    Math.round(amount).toLocaleString('en-KE', {
      maximumFractionDigits: 0,
    })
  );
}

export function formatAgo(seconds: number): string {
  if (seconds < 5) return 'just now';
  if (seconds < 60) return `${Math.floor(seconds)}s ago`;
  const m = Math.floor(seconds / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return `${h}h ago`;
}
