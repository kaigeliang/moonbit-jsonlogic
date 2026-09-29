import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { formatQuery } from '@react-querybuilder/core';

// These are real React Query Builder query trees. Keep the exported JSONLogic
// untouched: the integration test must exercise the producer's actual output.
const peopleSchema = { age: 'int32', status: 'string', active: 'bool', name: 'string' };
const orderSchema = { amount: 'int32', status: 'string', active: 'bool', name: 'string' };
const people = [
  { id: 1, age: 17, status: 'member', active: true, name: '未成年' },
  { id: 2, age: 18, status: 'member', active: true, name: '梁😀' },
  { id: 3, age: 22, status: 'inactive', active: false, name: 'O\'Reilly "梁😀"' },
  { id: 4, age: 65, status: 'active', active: true, name: '张三' },
  { id: 5, age: 66, status: 'active', active: false, name: '' },
  { id: 6, age: -2147483648, status: 'active', active: true, name: '最小值' },
  { id: 7, age: 2147483647, status: 'member', active: false, name: '最大值' },
  { id: 8, age: 22, status: '已付款', active: true, name: 'O\'Reilly "梁😀"' },
  { id: 9, age: 22, status: "x' OR 1=1 --", active: true, name: '参数不应成为SQL代码' },
  { id: 10, age: 19, status: 'active', active: true, name: '下界之内' },
  { id: 11, age: 64, status: 'active', active: true, name: '上界之内' },
  { id: 12, age: 22, status: '001', active: false, name: '数字外观的字符串' },
];
const orders = [
  { id: 101, amount: 99, status: 'paid', active: true, name: '订单一' },
  { id: 102, amount: 100, status: 'paid', active: true, name: '订单二😀' },
  { id: 103, amount: 101, status: 'pending', active: true, name: 'O\'Reilly' },
  { id: 104, amount: 200, status: 'cancelled', active: false, name: '已取消' },
  { id: 105, amount: 0, status: 'paid', active: false, name: '' },
  { id: 106, amount: -2147483648, status: 'paid', active: true, name: '最小值' },
  { id: 107, amount: 2147483647, status: 'paid', active: true, name: '最大值' },
  { id: 108, amount: 100, status: "x' OR 1=1 --", active: true, name: '参数测试' },
];

const rule = (field, operator, value) => ({ field, operator, value });
const and = (...rules) => ({ combinator: 'and', rules });
const or = (...rules) => ({ combinator: 'or', rules });
const exported = (id, querytree, schema, data) => ({
  id,
  querytree,
  schema,
  rule: formatQuery(querytree, 'jsonlogic'),
  data,
});
const queries = [
  exported('rqb/users/adult-active', and(rule('age', '>=', 18), rule('active', '=', true)), peopleSchema, people),
  exported('rqb/users/open-age-range', and(rule('age', '>', 18), rule('age', '<', 65)), peopleSchema, people),
  exported('rqb/users/status-and-range', and(
    rule('status', '!=', 'inactive'),
    or(rule('age', '<', 18), rule('age', '<=', 65)),
  ), peopleSchema, people),
  exported('rqb/users/unicode-and-quotes', and(
    rule('status', '=', '已付款'),
    rule('name', '=', 'O\'Reilly "梁😀"'),
  ), peopleSchema, people),
  exported('rqb/users/not-inactive', {
    ...or(rule('status', '=', 'inactive'), rule('active', '=', false)),
    not: true,
  }, peopleSchema, people),
  exported('rqb/users/numeric-looking-string', and(
    rule('status', '=', '001'), rule('active', '!=', true),
  ), peopleSchema, people),
  exported('rqb/orders/paid-minimum-amount', and(
    rule('status', '=', 'paid'), rule('amount', '>=', 100),
  ), orderSchema, orders),
  exported('rqb/orders/boundaries', or(
    rule('amount', '<=', -2147483648), rule('amount', '>=', 2147483647),
  ), orderSchema, orders),
  exported('rqb/orders/parameter-not-code', and(
    rule('status', '=', "x' OR 1=1 --"), rule('amount', '>', 0),
  ), orderSchema, orders),
];

// Expectations come from the input contract and source AST locations, never
// from adapter/executor output. A failing translation must identify this site.
const rejection = (id, rejectedRule, reason, path, schema = peopleSchema) => ({
  id, schema, rule: rejectedRule, reason,
  expected_error: { kind: 'invalid_rule', path },
});
const rejections = [
  {
    ...rejection('rqb/numeric-string-export', formatQuery(and(rule('age', '=', '18')), 'jsonlogic'), 'The real producer preserves a numeric-looking string; the Int32 adapter must reject this comparison.', '/and/0/==/1'),
    querytree: and(rule('age', '=', '18')),
  },
  rejection('empty-and', { and: [] }, 'Empty logical groups are outside the nonempty predicate subset.', '/and'),
  rejection('empty-or', { or: [] }, 'Empty logical groups are outside the nonempty predicate subset.', '/or'),
  rejection('null-literal', { '==': [{ var: 'age' }, null] }, 'The typed SQL adapter accepts no nullable literals.', '/==/1'),
  rejection('numeric-string-coercion', { '==': [{ var: 'age' }, '18'] }, 'Same-type comparisons cannot reproduce number/string coercion.', '/==/1'),
  rejection('boolean-number-coercion', { '==': [{ var: 'active' }, 1] }, 'Boolean/numeric coercion is outside the typed subset.', '/==/1'),
  rejection('dynamic-var', { '==': [{ var: { cat: ['a', 'ge'] } }, 18] }, 'Field names must be static schema-checked strings.', '/==/0/var'),
  rejection('collection-scope', { some: [{ var: 'age' }, { '>': [{ var: '' }, 18] }] }, 'Collection operators and local scopes are not scalar predicates.', '/some'),
  rejection('unknown-field', { '>': [{ var: 'secret' }, 18] }, 'The field is absent from the declared schema.', '/>/0/var'),
  rejection('integer-overflow', { '>': [{ var: 'age' }, 2147483648] }, 'The typed database currently accepts Int32 literals only.', '/>/1'),
  rejection('integer-underflow', { '>': [{ var: 'age' }, -2147483649] }, 'The typed database currently accepts Int32 literals only.', '/>/1'),
  rejection('fractional-number', { '>': [{ var: 'age' }, 18.5] }, 'The database numeric column type is Int32.', '/>/1'),
  rejection('nested-field', { '==': [{ var: 'profile.age' }, 18] }, 'Nested field paths are outside the flat-column subset.', '/==/0/var'),
  rejection('field-default', { '==': [{ var: ['age', 18] }, 18] }, 'Variable defaults require missing-value semantics.', '/==/0/var'),
  rejection('unknown-operation', { dateRelative: ['today'] }, 'Custom operations must not become executable SQL.', '/dateRelative'),
  rejection('standalone-boolean', true, 'All predicate leaves must be typed comparisons.', ''),
  rejection('bare-variable', { var: 'active' }, 'Bare variables rely on truthiness outside the comparison subset.', '/var'),
  rejection('nul-string-literal', { '==': [{ var: 'status' }, 'paid\u0000' ] }, 'NUL cannot be transported through the current database string ABI.', '/==/1'),
];

const recordRejection = (id, data, reason, path) => ({
  id, schema: peopleSchema, data, reason,
  expected_error: { kind: 'invalid_record', path },
});
const record_rejections = [
  recordRejection('null-value', { id: 201, age: null, status: 'member', active: true, name: 'Null' }, 'Null violates a nonnullable column.', '/age'),
  recordRejection('missing-value', { id: 202, status: 'member', active: true, name: 'Missing' }, 'Missing age violates the complete record contract.', '/age'),
  recordRejection('numeric-string-value', { id: 203, age: '18', status: 'member', active: true, name: 'String' }, 'Numeric strings are not Int32 JSON numbers.', '/age'),
  recordRejection('boolean-number-value', { id: 204, age: 18, status: 'member', active: 1, name: 'Number' }, 'Boolean columns accept only JSON booleans.', '/active'),
  recordRejection('overflow-value', { id: 205, age: 2147483648, status: 'member', active: true, name: 'Overflow' }, 'The record exceeds Int32.', '/age'),
  recordRejection('fractional-value', { id: 206, age: 18.5, status: 'member', active: true, name: 'Fraction' }, 'The record is not an integer.', '/age'),
  recordRejection('string-number-value', { id: 207, age: 18, status: 123, active: true, name: 'Status' }, 'String columns accept only JSON strings.', '/status'),
  recordRejection('nul-string-value', { id: 208, age: 18, status: 'member', active: true, name: 'NUL\u0000' }, 'NUL cannot be transported through the current database string ABI.', '/name'),
];

const packageManifest = JSON.parse(await readFile(new URL('./node_modules/@react-querybuilder/core/package.json', import.meta.url), 'utf8'));
assert.equal(packageManifest.version, '8.24.3', 'Run npm ci with the committed lockfile.');
assert.ok(queries.every(({ rule }) => rule && typeof rule === 'object'));
assert.ok([...rejections, ...record_rejections].every(({ expected_error }) =>
  typeof expected_error.path === 'string' &&
  (expected_error.path === '' || expected_error.path.startsWith('/'))));
const document = {
  producer: {
    package: '@react-querybuilder/core',
    version: packageManifest.version,
    function: "formatQuery(query, 'jsonlogic')",
    format: 'jsonlogic',
    source: 'https://github.com/react-querybuilder/react-querybuilder',
    documentation: 'https://react-querybuilder.js.org/docs/utils/export',
    package_source: 'https://www.npmjs.com/package/@react-querybuilder/core/v/8.24.3',
    note: 'Positive rules and the rqb/numeric-string-export rejection are unmodified exports of their bundled querytree; other rejection rules are deliberately handwritten contract probes.',
  },
  contract: {
    fields: 'Flat, complete, nonnullable records; JSON number fields restricted to Int32.',
    comparisons: 'Int32 comparisons; string/bool == and != with same-type literals.',
    logic: 'Nonempty and/or groups and !; every leaf must be a comparison.',
  },
  queries,
  rejections,
  record_rejections,
};
const serialized = JSON.stringify(document, null, 2) + '\n';
const fixturePath = new URL('../../tests/queryx_fixture.json', import.meta.url);
if (process.argv.slice(2).some((arg) => arg !== '--check')) {
  throw new Error('Usage: node generate.mjs [--check]');
}
if (process.argv.includes('--check')) {
  assert.equal(await readFile(fixturePath, 'utf8'), serialized, 'QueryX fixture differs from pinned React Query Builder output.');
  console.log(`React Query Builder ${packageManifest.version}: ${queries.length} exports reproduce tests/queryx_fixture.json.`);
} else {
  await writeFile(fixturePath, serialized);
  console.log(`Wrote ${queries.length} real React Query Builder exports, ${rejections.length} rule rejection probes and ${record_rejections.length} record rejection probes.`);
}
