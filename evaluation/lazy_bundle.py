#!/usr/bin/env python3
"""Measures what `deferred_locales` does to a web bundle.

    python3 evaluation/lazy_bundle.py

Builds a throwaway project, generates it both ways, compiles each with
`dart compile js -O4`, and prints the bytes. The point of having it in the
repository is that the figures in `docs/` should be re-runnable rather than
taken on trust.

Two corpus sizes, 396 messages and 36, because the answer changes sign between
them: the deferred loader is a fixed cost in the first download, and a project
has to carry more translation text than that before moving it out of the way
buys anything.

Two scenarios, because they answer different questions and only one of them is
the usual advertisement for lazy loading:

* `all`     -- the entry point reads every message of every locale. Nothing can
               be dropped, so this is the size of the translations themselves
               and the deferred split moves them out of the first download.
* `one`     -- the entry point reads one message. `dart2js` tree-shakes the
               rest, because a generated message is a getter on a `const`
               class and an unused getter is dead code. This is the scenario
               that says how much lazy loading is worth to an application that
               does not render every screen in every language.
"""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

PACKAGES = pathlib.Path(__file__).resolve().parent.parent / 'packages'
FEATURES = ('auth', 'wallet', 'catalog', 'orders', 'profile', 'settings',
            'support', 'search', 'checkout')
PER_FEATURE = 44  # overridden per run
LOCALES = {
    'en': ('Log in', 'Total', '{n, plural, one{# item} other{# items}}'),
    'ru': ('Войти', 'Итого',
           '{n, plural, one{# товар} few{# товара} many{# товаров} '
           'other{# товара}}'),
    'de': ('Anmelden', 'Summe', '{n, plural, one{# Artikel} other{# Artikel}}'),
    'fr': ('Connexion', 'Total',
           '{n, plural, one{# article} other{# articles}}'),
}


def keys(per_feature=PER_FEATURE):
    """Every message key, as (namespace, member, kind)."""
    for feature in FEATURES:
        for i in range(per_feature):
            if i % 7 == 0:
                yield feature, f'count{i}', 'plural'
            elif i % 11 == 0:
                yield feature, f'amount{i}', 'amount'
            else:
                yield feature, f'label{i}', 'label'


def translations(tag, per_feature):
    title, total, plural = LOCALES[tag]
    doc = {}
    for feature, member, kind in keys(per_feature):
        node = doc.setdefault(feature, {})
        if kind == 'plural':
            node[member] = plural
        elif kind == 'amount':
            node[member] = f'{total}: {{v, number, currency:USD}}'
        else:
            node[member] = f'{title} {feature} {member}'
    return doc


def main_source(*, reads_everything, deferred, per_feature):
    """The entry point, which decides what `dart2js` may drop."""
    lines = [
        "import 'l10n/app_localizations.g.dart';",
        '',
        'Future<void> main() async {',
        '  final sink = StringBuffer();',
    ]
    if deferred:
        lines.append('  await AppLocale.loadAll();')
    if reads_everything:
        lines.append('  for (final locale in AppLocale.values) {')
        lines.append('    final t = AppLocalizations.forLocale(locale);')
        for feature, member, kind in keys(per_feature):
            call = {
                'plural': f'{member}(n: 3)',
                'amount': f'{member}(v: 1)',
                'label': member,
            }[kind]
            lines.append(f'    sink.write(t.{feature}.{call});')
        lines.append('  }')
    else:
        lines.append(
            '  sink.write(AppLocalizations.forLocale(AppLocale.en)'
            '.auth.label1);'
        )
    lines += [
        '  // ignore: avoid_print',
        '  print(sink.length);',
        '}',
        '',
    ]
    return '\n'.join(lines)


def config(*, deferred):
    return (
        'input_directory: translations\n'
        'output_directory: lib/l10n\n'
        'base_locale: en\n'
        'fallback_locale: en\n'
        'file_per_locale: true\n'
        f'deferred_locales: {"true" if deferred else "false"}\n'
        'flutter:\n'
        '  enabled: false\n'
    )


PUBSPEC = f'''name: lazybench
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  l10n_plus: ^0.1.0
  intl: ^0.20.0
dev_dependencies:
  l10n_plus_generator: ^0.1.0
dependency_overrides:
  l10n_plus:
    path: {PACKAGES / 'l10n_plus'}
  l10n_plus_generator:
    path: {PACKAGES / 'l10n_plus_generator'}
'''


def run(root, *args):
    result = subprocess.run(args, cwd=root, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f'{" ".join(args)} failed:\n{result.stdout}{result.stderr}')
    return result.stdout


def measure(root, *, reads_everything, deferred, per_feature):
    (root / 'l10n_plus.yaml').write_text(config(deferred=deferred))
    (root / 'lib' / 'main.dart').write_text(
        main_source(
            reads_everything=reads_everything,
            deferred=deferred,
            per_feature=per_feature,
        )
    )
    shutil.rmtree(root / 'lib' / 'l10n', ignore_errors=True)
    shutil.rmtree(root / 'out', ignore_errors=True)
    run(root, 'dart', 'run', 'l10n_plus_generator', 'generate')
    run(root, 'dart', 'compile', 'js', '-o', 'out/main.js', '-O4',
        'lib/main.dart')
    out = root / 'out'
    first = (out / 'main.js').stat().st_size
    chunks = sorted(p.stat().st_size for p in out.glob('main.js_*.part.js'))
    return first, chunks


def main():
    with tempfile.TemporaryDirectory(prefix='l10n_plus_lazy') as tmp:
        root = pathlib.Path(tmp)
        (root / 'lib').mkdir()
        (root / 'translations').mkdir()
        (root / 'pubspec.yaml').write_text(PUBSPEC)
        run(root, 'dart', 'pub', 'get')

        # Two corpus sizes, because the answer changes sign between them: the
        # deferred loader itself is a fixed cost in the first download, and a
        # project has to have more translation text than that before moving it
        # out of the way is worth anything.
        for per_feature in (44, 4):
            for tag in LOCALES:
                (root / 'translations' / f'{tag}.json').write_text(
                    json.dumps(translations(tag, per_feature),
                               ensure_ascii=False) + '\n'
                )
            total = len(list(keys(per_feature)))
            print(
                f'== {total} messages x {len(LOCALES)} locales, '
                'dart compile js -O4'
            )
            for scenario, reads_everything in (('all', True), ('one', False)):
                print(f'   the entry point reads {scenario} of the messages:')
                for deferred in (False, True):
                    first, chunks = measure(
                        root,
                        reads_everything=reads_everything,
                        deferred=deferred,
                        per_feature=per_feature,
                    )
                    served = first + sum(chunks)
                    label = 'deferred' if deferred else 'one library'
                    parts = (
                        '' if not chunks
                        else '  chunks ' + ' + '.join(f'{c:,}' for c in chunks)
                    )
                    print(
                        f'     {label:12} first {first:>8,}'
                        f'   served {served:>8,}{parts}'
                    )
            print()


if __name__ == '__main__':
    main()
