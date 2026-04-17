#!/usr/bin/env node
// Validates state.json.example against state.schema.json (type + required checks, no external deps)

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const schema = JSON.parse(fs.readFileSync(path.join(root, 'state.schema.json'), 'utf8'));
const example = JSON.parse(fs.readFileSync(path.join(root, 'state.json.example'), 'utf8'));

const errors = [];

function jsTypeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  return typeof value;
}

function checkType(value, typeDef, fieldPath) {
  const allowed = Array.isArray(typeDef.type) ? typeDef.type : [typeDef.type];
  const actual = jsTypeOf(value);
  const matched = allowed.some(t => {
    if (t === actual) return true;
    if (t === 'integer' && typeof value === 'number' && Number.isInteger(value)) return true;
    if (t === 'number' && typeof value === 'number') return true;
    return false;
  });
  if (!matched) {
    errors.push(`${fieldPath}: expected ${JSON.stringify(typeDef.type)}, got "${actual}"`);
  }
}

function validateObj(obj, schemaDef, basePath) {
  if (!schemaDef || !schemaDef.properties) return;
  for (const [key, propSchema] of Object.entries(schemaDef.properties)) {
    if (!(key in obj)) continue;
    const val = obj[key];
    const fullPath = `${basePath}.${key}`;
    if (propSchema.type) checkType(val, propSchema, fullPath);
    if (typeof val === 'object' && val !== null && !Array.isArray(val)) {
      validateObj(val, propSchema, fullPath);
    }
  }
}

for (const req of schema.required || []) {
  if (!(req in example)) errors.push(`Missing required field: "${req}"`);
}

for (const [key, propSchema] of Object.entries(schema.properties || {})) {
  if (!(key in example)) continue;
  const val = example[key];
  const allowed = Array.isArray(propSchema.type) ? propSchema.type : [propSchema.type];
  if (propSchema.type) checkType(val, propSchema, key);
  if (allowed.includes('object') && typeof val === 'object' && val !== null && !Array.isArray(val)) {
    validateObj(val, propSchema, key);
  }
}

if (errors.length > 0) {
  console.error('state.json.example validation FAILED:');
  errors.forEach(e => console.error('  ' + e));
  process.exit(1);
}
console.log('state.json.example validation PASSED');
