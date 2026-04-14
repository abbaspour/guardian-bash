#!/usr/bin/env node

/**
 * pem-to-jwk.js - Convert any PEM key to a public JWK for Guardian enrollment
 *
 * Accepts RSA or EC private/public keys. Auto-detects key type.
 * Outputs only the public key fields (safe to send to the server).
 *
 * Usage:
 *   node pem-to-jwk.js <pem-file>
 *   node pem-to-jwk.js -          # read from stdin
 *   cat ec-private.pem | node pem-to-jwk.js
 *
 * Supported input formats:
 *   RSA private key  (-----BEGIN RSA PRIVATE KEY-----)
 *   RSA public key   (-----BEGIN PUBLIC KEY----------)
 *   EC private key   (-----BEGIN EC PRIVATE KEY------)
 *   PKCS#8 private   (-----BEGIN PRIVATE KEY---------)
 */

'use strict';

const { createPrivateKey, createPublicKey } = require('crypto');
const fs = require('fs');

function pemToPublicJwk(pem) {
  let keyObject;

  if (pem.includes('PRIVATE')) {
    const privateKey = createPrivateKey(pem);
    keyObject = createPublicKey(privateKey);
  } else {
    keyObject = createPublicKey(pem);
  }

  const jwk = keyObject.export({ format: 'jwk' });

  // Remove any private fields that shouldn't be sent to the server
  delete jwk.d;
  delete jwk.p;
  delete jwk.q;
  delete jwk.dp;
  delete jwk.dq;
  delete jwk.qi;

  // Add algorithm and usage fields
  if (jwk.kty === 'EC') {
    jwk.alg = 'ES256';
    jwk.use = 'sig';
  } else if (jwk.kty === 'RSA') {
    jwk.alg = 'RS256';
    jwk.use = 'sig';
  } else {
    process.stderr.write(`Error: Unsupported key type: ${jwk.kty}\n`);
    process.exit(1);
  }

  return jwk;
}

function readPem(source) {
  if (!source || source === '-') {
    return fs.readFileSync('/dev/stdin', 'utf8');
  }
  if (!fs.existsSync(source)) {
    process.stderr.write(`Error: File not found: ${source}\n`);
    process.exit(1);
  }
  return fs.readFileSync(source, 'utf8');
}

const arg = process.argv[2];

if (arg === '-h' || arg === '--help') {
  process.stdout.write([
    'Usage: node pem-to-jwk.js [PEM_FILE]',
    '',
    'Convert RSA or EC PEM keys to JWK format for Guardian enrollment.',
    'Auto-detects key type. Accepts private or public keys.',
    '',
    'Arguments:',
    '  PEM_FILE    Path to PEM file (reads from stdin if omitted or "-")',
    '',
    'Examples:',
    '  node pem-to-jwk.js private.pem',
    '  node pem-to-jwk.js ec-private.pem',
    '  node pem-to-jwk.js public.pem',
    '  cat ec-private.pem | node pem-to-jwk.js',
    '',
  ].join('\n'));
  process.exit(0);
}

try {
  const pem = readPem(arg);
  const jwk = pemToPublicJwk(pem);
  process.stdout.write(JSON.stringify(jwk) + '\n');
} catch (err) {
  process.stderr.write(`Error: Failed to parse PEM key: ${err.message}\n`);
  process.exit(1);
}
