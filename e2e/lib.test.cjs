// Checks of the .env URL parsing: npm run test:lib (node --test). Not part of CI.
const test = require('node:test');
const assert = require('node:assert');
const { splitPgUrl } = require('./lib.cjs');

test('path database, query stripped from the server part', () => {
  assert.deepStrictEqual(splitPgUrl('postgresql://u:p@h:5432/real?sslmode=disable'), { server: 'postgresql://u:p@h:5432', db: 'real' });
});
test('path wins over dbname', () => {
  assert.strictEqual(splitPgUrl('postgres://u@h/real?dbname=other').db, 'real');
});
test('dbname query parameter', () => {
  assert.deepStrictEqual(splitPgUrl('postgresql://u:p@h/?dbname=foo'), { server: 'postgresql://u:p@h', db: 'foo' });
  assert.deepStrictEqual(splitPgUrl('postgres://h?sslmode=x&dbname=foo'), { server: 'postgres://h', db: 'foo' });
});
test('percent-encoded names', () => {
  assert.strictEqual(splitPgUrl('postgres://h?dbname=my%20db%2Fx').db, 'my db/x');
  assert.strictEqual(splitPgUrl('postgres://h/a%2Bb').db, 'a+b');
});
test('no database', () => {
  assert.strictEqual(splitPgUrl('postgres://u:p@h:5432').db, undefined);
  assert.strictEqual(splitPgUrl('postgres://h?dbname=').db, undefined);
  assert.strictEqual(splitPgUrl('not a url'), undefined);
});
