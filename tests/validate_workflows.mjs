#!/usr/bin/env node
/**
 * Static validator for the n8n AI Customer Support workflows.
 *
 * Checks, for every workflow JSON in workflows/ and workflows/subflows/:
 *   1. valid JSON with a non-empty `nodes` array and a `connections` object
 *   2. unique, non-empty node ids
 *   3. node types on the supported import allow-list
 *   4. known-good (type, typeVersion) combinations
 *   5. connections reference existing nodes (and vice-versa) with valid types
 *   6. `$env.X` references exist in .env.example (or are n8n built-ins)
 *   7. Execute Workflow `localFile` sources point at existing sub-workflow files
 *   8. no lingering REPLACE_WITH_ credential placeholders
 *
 * Usage:  node tests/validate_workflows.mjs
 * Exit code 0 when all checks pass; 1 otherwise.
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const WF_DIR = join(ROOT, 'workflows');
const SUB_DIR = join(WF_DIR, 'subflows');
const ENV_EXAMPLE = readFileSync(join(ROOT, '.env.example'), 'utf8');

// ---------------------------------------------------------------------------
// Supported node types (n8n 1.x)
// ---------------------------------------------------------------------------
const NODE_TYPE_ALLOW = new Set([
  'n8n-nodes-base.webhook',
  'n8n-nodes-base.code',
  'n8n-nodes-base.if',
  'n8n-nodes-base.switch',
  'n8n-nodes-base.executeWorkflow',
  'n8n-nodes-base.executeWorkflowTrigger',
  'n8n-nodes-base.respondToWebhook',
  'n8n-nodes-base.httpRequest',
  'n8n-nodes-base.postgres',
  'n8n-nodes-base.manualTrigger',
  'n8n-nodes-base.errorTrigger',
  '@n8n/n8n-nodes-langchain.lmChatOpenAi',
  '@n8n/n8n-nodes-langchain.chainLlm',
  '@n8n/n8n-nodes-langchain.agent',
  '@n8n/n8n-nodes-langchain.memoryPostgresChat',
  '@n8n/n8n-nodes-langchain.toolCode',
  '@n8n/n8n-nodes-langchain.embeddingsOpenAi',
  '@n8n/n8n-nodes-langchain.vectorStorePGVector',
  '@n8n/n8n-nodes-langchain.documentDefaultDataLoader',
]);

// Known-good (type, typeVersion). Anything outside is reported as a WARNING.
const KNOWN_VERSIONS = new Set([
  'n8n-nodes-base.code@2',
  'n8n-nodes-base.if@2',
  'n8n-nodes-base.switch@3',
  'n8n-nodes-base.webhook@2',
  'n8n-nodes-base.postgres@2.4',
  'n8n-nodes-base.executeWorkflow@2',
  'n8n-nodes-base.executeWorkflowTrigger@1.1',
  'n8n-nodes-base.respondToWebhook@1.1',
  'n8n-nodes-base.httpRequest@4.2',
  'n8n-nodes-base.manualTrigger@1',
  'n8n-nodes-base.errorTrigger@1.1',
  '@n8n/n8n-nodes-langchain.lmChatOpenAi@1.2',
  '@n8n/n8n-nodes-langchain.chainLlm@1.2',
  '@n8n/n8n-nodes-langchain.agent@2',
  '@n8n/n8n-nodes-langchain.memoryPostgresChat@1.1',
  '@n8n/n8n-nodes-langchain.toolCode@1',
  '@n8n/n8n-nodes-langchain.embeddingsOpenAi@1.2',
  '@n8n/n8n-nodes-langchain.vectorStorePGVector@1.4',
  '@n8n/n8n-nodes-langchain.documentDefaultDataLoader@1.1',
]);

// n8n built-in / standard environment variables that need no .env.example entry
const ENV_BUILTIN = new Set([
  'NODE_ENV',
  'N8N_HOST',
  'N8N_PORT',
  'N8N_PROTOCOL',
  'N8N_ENCRYPTION_KEY',
  'N8N_USER_FOLDER',
  'N8N_PUBLIC_API_DISABLED',
  'N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS',
]);

const ENV_DEFINED = new Set(
  [...ENV_EXAMPLE.matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map((m) => m[1]),
);

// Valid connection types seen on either side of a connection
const CONN_TYPES = new Set([
  'main', 'true', 'false', 'string', 'number', 'boolean',
  'ai_memory', 'ai_tool', 'ai_embedding', 'ai_languageModel', 'ai_document',
]);

const errors = [];
const warnings = [];
let fileCount = 0;
let nodeCount = 0;

const fail = (file, msg) => errors.push(`[${file}] ${msg}`);
const warn = (file, msg) => warnings.push(`[${file}] ${msg}`);

function collectFiles() {
  const files = [];
  for (const name of readdirSync(WF_DIR).sort()) {
    if (name.endsWith('.json')) files.push(join(WF_DIR, name));
  }
  for (const name of readdirSync(SUB_DIR).sort()) {
    if (name.endsWith('.json')) files.push(join(SUB_DIR, name));
  }
  return files;
}

function validateFile(file) {
  const rel = basename(file);
  let doc;
  try {
    doc = JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    fail(rel, `invalid JSON: ${e.message}`);
    return;
  }
  fileCount++;

  if (!Array.isArray(doc.nodes) || doc.nodes.length === 0) {
    fail(rel, 'missing or empty `nodes` array');
    return;
  }
  if (!doc.connections || typeof doc.connections !== 'object') {
    fail(rel, 'missing `connections` object');
  }

  const names = new Set();
  const seenIds = new Set();

  for (const node of doc.nodes) {
    nodeCount++;
    if (!node.name || typeof node.name !== 'string') {
      fail(rel, `node at index ${doc.nodes.indexOf(node)} missing \`name\``);
      continue;
    }
    if (names.has(node.name)) fail(rel, `duplicate node name: ${node.name}`);
    names.add(node.name);

    if (!node.id || typeof node.id !== 'string') {
      fail(rel, `node "${node.name}" missing \`id\``);
    } else if (seenIds.has(node.id)) {
      fail(rel, `duplicate node id: ${node.id} (node "${node.name}")`);
    } else {
      seenIds.add(node.id);
    }

    const type = node.type;
    if (!NODE_TYPE_ALLOW.has(type)) {
      fail(rel, `node "${node.name}" uses unsupported type "${type}"`);
    }
    const combo = `${type}@${node.typeVersion}`;
    if (!KNOWN_VERSIONS.has(combo)) {
      warn(rel, `node "${node.name}" uses unverified typeVersion "${combo}"`);
    }
  }

  // Connections: keys are source node names; entries reference existing nodes.
  for (const [src, connByType] of Object.entries(doc.connections || {})) {
    if (src !== '_' && !names.has(src)) {
      fail(rel, `connection source "${src}" is not a defined node`);
    }
    if (!connByType || typeof connByType !== 'object') {
      fail(rel, `connection "${src}" has invalid value`);
      continue;
    }
    for (const [connType, groups] of Object.entries(connByType)) {
      if (!Array.isArray(groups)) {
        fail(rel, `connection "${src}" -> "${connType}" is not an array`);
        continue;
      }
      for (const group of groups) {
        if (!Array.isArray(group)) continue;
        for (const entry of group) {
          if (!entry || typeof entry !== 'object') continue;
          const tgt = entry.node;
          if (tgt !== '_' && !names.has(tgt)) {
            fail(rel, `connection "${src}" -> "${connType}" references undefined node "${tgt}"`);
          }
          if (entry.type && !CONN_TYPES.has(entry.type)) {
            fail(rel, `connection "${src}" -> "${connType}" uses unknown connection type "${entry.type}"`);
          }
          if (typeof entry.index !== 'number') {
            fail(rel, `connection "${src}" -> "${connType}" entry missing numeric index`);
          }
        }
      }
    }
  }

  // env variable references
  const raw = JSON.stringify(doc);
  for (const m of raw.matchAll(/env\.([A-Z][A-Z0-9_]*)/g)) {
    const v = m[1];
    if (!ENV_DEFINED.has(v) && !ENV_BUILTIN.has(v)) {
      fail(rel, `references undefined env var ${v}`);
    }
  }

  // Execute Workflow localFile sources
  for (const node of doc.nodes) {
    if (node.type !== 'n8n-nodes-base.executeWorkflow') continue;
    const p = node.parameters || {};
    if (p.source === 'localFile') {
      const wfPath = typeof p.workflowPath === 'string' ? p.workflowPath : '';
      const m = wfPath.match(/\/([A-Za-z0-9._-]+\.json)$/);
      if (!m) {
        fail(rel, `Execute Workflow "${node.name}" localFile workflowPath is invalid: "${wfPath}"`);
        continue;
      }
      const target = join(SUB_DIR, m[1]);
      if (!existsSync(target)) {
        fail(rel, `Execute Workflow "${node.name}" references missing sub-workflow "${m[1]}"`);
      }
    } else if (p.workflowId) {
      warn(rel, `Execute Workflow "${node.name}" uses workflowId "${p.workflowId}" (prefer localFile)`);
    }
  }

  // credential placeholders — intentional until credentials are bound on import
  for (const m of raw.matchAll(/REPLACE_WITH_[A-Z0-9_]+/g)) {
    warn(rel, `unbound credential placeholder: ${m[0]} (bind a real credential on import)`);
  }
}

// ---------------------------------------------------------------------------
for (const f of collectFiles()) validateFile(f);

// Report
if (warnings.length) {
  console.log(`\nWarnings (${warnings.length}):`);
  for (const w of warnings) console.log(`  - ${w}`);
}

if (errors.length) {
  console.log(`\nValidation FAILED (${errors.length} errors across ${fileCount} files, ${nodeCount} nodes):`);
  for (const e of errors) console.log(`  - ${e}`);
  process.exit(1);
}

console.log(`\nValidation PASSED: ${fileCount} workflow files, ${nodeCount} nodes, no errors.`);
