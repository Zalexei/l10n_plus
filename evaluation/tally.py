#!/usr/bin/env python3
"""Tallies the capability matrix of docs/competitors.md.

    python3 evaluation/tally.py

The point of it is that the number in that document should be reproducible
rather than taken on trust -- it has been counted wrong twice, once by hand
and once by a script nobody kept.

The rule, so that a disagreement is about the rule and not about arithmetic:

* only the table whose header row begins `| Capability |`, up to the first
  blank line after it;
* a cell's verdict is its first `Y`, `~` or `N` once bold markers are
  stripped, and `n/a` counts as `N` -- a feature a package does not have is a
  feature a package does not have;
* a row where any of the four cells is neither (a bare number, a
  parenthetical) is not comparable, and is excluded from every column.
"""

import pathlib
import re
import sys

PACKAGES = ('l10n_plus', 'slang', 'gen_l10n', 'easy_localization')


def verdict(cell):
    text = cell.strip().replace('*', '').strip()
    if text.lower().startswith('n/a'):
        return 'N'
    match = re.match(r'^([Y~N])', text)
    return match.group(1) if match else None


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    lines = (root / 'docs' / 'competitors.md').read_text('utf-8').split('\n')
    start = next(i for i, l in enumerate(lines) if l.startswith('| Capability |'))
    end = next(i for i in range(start, len(lines)) if not lines[i].strip())
    rows = [l for l in lines[start + 2:end] if l.startswith('| ')]

    counts = {name: {'Y': 0, '~': 0, 'N': 0} for name in PACKAGES}
    excluded = []
    for row in rows:
        cells = row.split('|')[1:-1]
        verdicts = [verdict(cell) for cell in cells[1:5]]
        if any(v is None for v in verdicts):
            excluded.append(cells[0].strip())
            continue
        for name, v in zip(PACKAGES, verdicts):
            counts[name][v] += 1

    comparable = len(rows) - len(excluded)
    print(f'{comparable} comparable rows of {len(rows)}')
    for name in PACKAGES:
        row = counts[name]
        print(f'  {name:18} Y={row["Y"]:3}  ~={row["~"]:3}  N={row["N"]:3}')
    for name in excluded:
        print(f'  excluded: {name}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
