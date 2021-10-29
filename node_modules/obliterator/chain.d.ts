import ObliteratorIterator from './iterator';
import type {IntoInterator} from './types';

export default function chain<T>(
  ...iterables: IntoInterator<T>[]
): ObliteratorIterator<T>;
