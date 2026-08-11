#!/usr/bin/env bash
# Static validation suite for the n8n AI Customer Support project.
# Requires Node.js 18+. No n8n or database needed.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Validating workflow JSON structure, connections, env refs and sub-workflow references..."
node validate_workflows.mjs

echo "==> Checking that every scenario fixture is valid JSON and references a supported channel..."
for f in fixtures/scenario-*.json; do
  # scenario-12-invalid deliberately breaks validation rules
  if [[ "$f" == *scenario-12-invalid* ]]; then
    continue
  fi
  node -e "
    const fs = require('fs');
    const d = JSON.parse(fs.readFileSync('$f', 'utf8'));
    const channels = new Set(['website','whatsapp','telegram','email','slack','instagram','facebook']);
    if (!d.channel || !channels.has(d.channel)) {
      console.error('$f: invalid or missing channel: ' + d.channel);
      process.exit(1);
    }
    for (const k of ['customer_id','conversation_id','message_id','message']) {
      if (!d[k]) { console.error('$f: missing field ' + k); process.exit(1); }
    }
  "
done
echo "    All scenario fixtures are valid."

echo "==> Checking .env.example variables are documented in ENVIRONMENT.md..."
node -e "
  const fs = require('fs');
  const env = fs.readFileSync('../.env.example', 'utf8');
  const doc = fs.readFileSync('../docs/ENVIRONMENT.md', 'utf8');
  const vars = [...env.matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map(m => m[1]);
  const missing = vars.filter(v => !doc.includes(v));
  if (missing.length) { console.error('Undocumented env vars: ' + missing.join(', ')); process.exit(1); }
  console.log('    All ' + vars.length + ' env vars documented.');
"

echo "==> All static checks passed."
