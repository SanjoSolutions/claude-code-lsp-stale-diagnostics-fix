import { formatName } from './utils';

const name = formatName('John', 'Doe');
console.log(name);

export function handleRequest(path: string): string {
  return `Handling ${path}`;
}