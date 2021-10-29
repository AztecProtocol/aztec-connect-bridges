import ObliteratorIterator from './iterator';

export default function range(end: number): ObliteratorIterator<number>;
export default function range(
  start: number,
  end: number
): ObliteratorIterator<number>;
export default function range(
  start: number,
  end: number,
  step: number
): ObliteratorIterator<number>;
