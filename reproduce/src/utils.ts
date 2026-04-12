export function formatName(first: string, last: string): string {
  return `${first} ${last}`;
}

export function formatDate(date: Date): string {
  return date.toISOString();
}
