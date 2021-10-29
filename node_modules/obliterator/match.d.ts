import ObliteratorIterator from './iterator';

export default function match(
  pattern: RegExp,
  string: string
): ObliteratorIterator<string>;
