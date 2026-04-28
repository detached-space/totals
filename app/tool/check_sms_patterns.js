#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function normalizeSms(text) {
  return String(text ?? '')
    .replace(/\r\n?/g, '\n')
    .replace(/\u00A0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function loadPatterns(filePath) {
  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (Array.isArray(parsed)) return parsed;
  if (Array.isArray(parsed.patterns)) return parsed.patterns;
  throw new Error('Pattern file must be a JSON array or an object with a patterns array.');
}

function loadMessages(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');

  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return parsed;
    if (Array.isArray(parsed.messages)) return parsed.messages;
    throw new Error();
  } catch (_) {
    return [raw];
  }
}

function parseArgs(argv) {
  const options = {
    sender: 'Zemen',
    patterns: path.resolve(__dirname, '../assets/sms_patterns.json'),
    messages: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--sender') {
      options.sender = argv[++i];
    } else if (arg === '--patterns') {
      options.patterns = path.resolve(process.cwd(), argv[++i]);
    } else if (arg === '--messages') {
      options.messages = path.resolve(process.cwd(), argv[++i]);
    } else if (arg === '--help' || arg === '-h') {
      printUsage();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.messages) {
    throw new Error('Missing --messages <file>');
  }

  return options;
}

function printUsage() {
  console.log(`Usage:\n  node app/tool/check_sms_patterns.js --sender Zemen --messages /path/to/messages.json\n\nMessage file can be:\n  - a JSON array of SMS strings\n  - an object like { "messages": ["..."] }\n  - a plain text file containing one SMS`);
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    printUsage();
    process.exit(1);
  }

  const allPatterns = loadPatterns(options.patterns);
  const bankPatterns = allPatterns.filter(
    (pattern) =>
      String(pattern.senderId || '').toLowerCase() ===
      String(options.sender).toLowerCase(),
  );
  const messages = loadMessages(options.messages);

  console.log(`Sender: ${options.sender}`);
  console.log(`Patterns loaded: ${bankPatterns.length}`);
  console.log(`Messages loaded: ${messages.length}`);

  let anyMatch = false;

  messages.forEach((message, index) => {
    const rawMessage = String(message ?? '').trim();
    const normalizedMessage = normalizeSms(rawMessage);
    const matches = [];

    for (const pattern of bankPatterns) {
      try {
        const regex = new RegExp(pattern.regex, 'ims');
        const rawMatched = regex.test(rawMessage);
        regex.lastIndex = 0;
        const normalizedMatched = regex.test(normalizedMessage);

        if (rawMatched || normalizedMatched) {
          matches.push({
            description: pattern.description,
            type: pattern.type,
            rawMatched,
            normalizedMatched,
          });
        }
      } catch (error) {
        matches.push({
          description: pattern.description,
          type: pattern.type,
          error: error.message,
        });
      }
    }

    console.log(`\nMessage ${index + 1}: ${matches.some((m) => !m.error) ? 'MATCH' : 'NO MATCH'}`);

    if (matches.some((m) => !m.error)) {
      anyMatch = true;
      for (const match of matches.filter((m) => !m.error)) {
        console.log(
          `  - ${match.description} [${match.type}] raw=${match.rawMatched} normalized=${match.normalizedMatched}`,
        );
      }
    }
  });

  console.log(
    `\nOverall: ${anyMatch ? 'at least one matching pattern exists' : 'no matching pattern exists for the provided messages'}`,
  );
}

main();
