import { formatName, formatDate } from './utils';

const name = formatName('John', 'Doe');
console.log(name);

const date = formatDate(new Date());
console.log(date);
