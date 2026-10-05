const fs = require('fs');
const path = require('path');

const root = '/Volumes/PD1000/job/INTERCITY';

function walk(dir, ext, acc = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, ext, acc);
    else if (p.endsWith(ext)) acc.push(p);
  }
  return acc;
}

function normalizePath(p) {
  return (p || '/').replace(/\/+/g, '/').replace(/\/$/, '') || '/';
}

function normalizeMobilePath(p) {
  return normalizePath(
    p
      .replace(/\$\{[^}]+\}/g, ':id')
      .replace(/\$id/g, ':id')
  );
}

function toRegex(route) {
  const escaped = route
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    .replace(/:([A-Za-z0-9_]+)/g, '[^/]+');
  return new RegExp(`^${escaped}$`);
}

const mobileCalls = [];
for (const file of walk(path.join(root, 'apps/mobile_flutter/lib'), '.dart')) {
  const t = fs.readFileSync(file, 'utf8');
  for (const re of [
    /ApiClient\(\)\.(get|post|patch|delete)\(\s*'([^']+)'/g,
    /_api\.(get|post|patch|delete)\(\s*'([^']+)'/g,
  ]) {
    let m;
    while ((m = re.exec(t))) {
      mobileCalls.push({ method: m[1].toUpperCase(), path: m[2], file });
    }
  }
}

const backendRoutes = [];
for (const file of walk(path.join(root, 'backend/src'), '.ts')) {
  const t = fs.readFileSync(file, 'utf8');

  let base = '';
  const ctrlWithPath = t.match(/@Controller\('([^']*)'\)/);
  if (ctrlWithPath) {
    base = ctrlWithPath[1] || '';
  } else if (/@Controller\(\)/.test(t)) {
    base = '';
  } else {
    continue;
  }

  for (const [decorator, method] of [
    ['Get', 'GET'],
    ['Post', 'POST'],
    ['Patch', 'PATCH'],
    ['Delete', 'DELETE'],
  ]) {
    const withPath = new RegExp(`@${decorator}\\('([^']*)'\\)`, 'g');
    let m;
    while ((m = withPath.exec(t))) {
      const sub = m[1] || '';
      const route = normalizePath('/' + (base ? base + '/' : '') + sub);
      backendRoutes.push({ method, route, file });
    }

    const noPath = new RegExp(`@${decorator}\\(\\)`, 'g');
    while (noPath.exec(t)) {
      const route = normalizePath('/' + base);
      backendRoutes.push({ method, route, file });
    }
  }
}

const mismatches = [];
for (const call of mobileCalls) {
  const norm = normalizeMobilePath(call.path);
  const matched = backendRoutes.some((r) => r.method === call.method && toRegex(r.route).test(norm));
  if (!matched) mismatches.push({ ...call, normalized: norm });
}

console.log(`Mobile calls: ${mobileCalls.length}`);
console.log(`Backend routes: ${backendRoutes.length}`);
if (!mismatches.length) {
  console.log('API contract check: OK (all mobile API calls matched backend routes).');
} else {
  console.log('API contract mismatches found:');
  for (const m of mismatches) {
    console.log(`- ${m.method} ${m.path} -> ${m.normalized} (${m.file})`);
  }
  process.exitCode = 1;
}
