#!/usr/bin/env node
// A separate source-repository credential; never put a token in a Git URL.
const fs = require('node:fs');
if (/username/i.test(process.argv[2] || '')) process.stdout.write('x-access-token');
else if (process.env.AMANDA_SOURCE_TOKEN_FILE) process.stdout.write(fs.readFileSync(process.env.AMANDA_SOURCE_TOKEN_FILE, 'utf8').trim());
