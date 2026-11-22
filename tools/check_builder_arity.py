#!/usr/bin/env python3
"""Regression check for the food-DB builders' schema/row arity.

Regression: the OFF builder's row tuple grew a misplaced `micros` placeholder
(12 bindings against an 11-column INSERT -> sqlite3.ProgrammingError in CI),
and the table schemas drifted from what the app's search query selects.

Asserts for each builder (tools/build_off_db.py, tools/build_common_db.py):
  1. the CREATE TABLE foods column count == the placeholder count of every
     INSERT INTO foods statement,
  2. every row-tuple literal has exactly that many elements,
  3. the `micros` column exists (the app's search selects it).

Run standalone (exit 0/1) or import run_checks() from tests.
"""
import ast
import sys
from pathlib import Path

BUILDERS = ['build_off_db.py', 'build_common_db.py']


def _columns_of_create(create: ast.Call) -> int:
    """Count columns in a CREATE TABLE built from concatenated string parts."""
    parts = []
    for arg in create.args:
        parts.append(ast.literal_eval(arg))
    cols = 0
    depth = 0
    text = ' '.join(parts)
    # count commas at top level of the column list (between the outer parens)
    inner = text[text.index('(') + 1:text.rindex(')')]
    for ch in inner:
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        elif ch == ',' and depth == 0:
            cols += 1
    return cols + 1


def _placeholders(insert: ast.Call) -> int:
    """Count '?' placeholders in the SQL string argument(s)."""
    n = 0
    for arg in insert.args:
        if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
            n += arg.value.count('?')
    return n


def run_checks(tools_dir: Path) -> list:
    errors = []
    for name in BUILDERS:
        path = tools_dir / name
        tree = ast.parse(path.read_text(), filename=str(path))

        create_cols = None
        inserts = []
        tuples = []
        has_micros = False
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                sql = ' '.join(
                    a.value for a in node.args
                    if isinstance(a, ast.Constant) and isinstance(a.value, str))
                if 'CREATE TABLE foods' in sql:
                    create_cols = _columns_of_create(node)
                    has_micros = has_micros or 'micros' in sql
                if 'INTO foods VALUES' in sql:
                    inserts.append(node)
            if isinstance(node, ast.Tuple):
                seg = ast.get_source_segment(path.read_text(), node) or ''
                if 'micros' in seg or ('IDX' in seg and 'fiber' in seg):
                    tuples.append(node)

        if create_cols is None:
            errors.append(f'{name}: no CREATE TABLE foods found')
            continue
        if not has_micros:
            errors.append(f'{name}: foods table is missing the micros column '
                          '(the app search selects it)')
        for node in inserts:
            ph = _placeholders(node)
            if ph != create_cols:
                errors.append(f'{name}: INSERT uses {ph} placeholders but the '
                              f'table has {create_cols} columns')
        for node in tuples:
            if len(node.elts) != create_cols:
                seg = (ast.get_source_segment(path.read_text(), node) or '')[:60]
                errors.append(f'{name}: row tuple has {len(node.elts)} elements '
                              f'but the table has {create_cols} columns: {seg}...')
        print(f'{name}: columns={create_cols} inserts={len(inserts)} '
              f'row-tuples={len(tuples)} -> OK' if not errors else '')
    return errors


if __name__ == '__main__':
    tools = Path(__file__).resolve().parent
    errs = run_checks(tools)
    for e in errs:
        print('FAIL:', e, file=sys.stderr)
    sys.exit(1 if errs else 0)
