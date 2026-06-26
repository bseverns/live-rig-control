import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import Ajv2020 from "ajv/dist/2020.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--mappings" || arg === "-m") {
      opts.mappings = argv[i + 1];
      i += 1;
    } else if (arg === "--schema" || arg === "-s") {
      opts.schema = argv[i + 1];
      i += 1;
    } else if (arg === "--help" || arg === "-h") {
      opts.help = true;
    }
  }
  return opts;
}

function usage() {
  console.log("Usage: node validate-mappings.js --mappings <path> --schema <path>");
  console.log("Defaults: --mappings ../src/mappings.json --schema ../interop.schema.json");
}

const opts = parseArgs(process.argv.slice(2));
if (opts.help) {
  usage();
  process.exit(0);
}

const mappingsPath = path.resolve(__dirname, opts.mappings ?? "../src/mappings.json");
const schemaPath = path.resolve(__dirname, opts.schema ?? "../interop.schema.json");

const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
const mappings = JSON.parse(fs.readFileSync(mappingsPath, "utf8"));

const ajv = new Ajv2020({ allErrors: true, strict: false });
const validate = ajv.compile(schema);

const ok = validate(mappings);
if (ok) {
  console.log("mappings.json is valid.");
  process.exit(0);
}

console.error("mappings.json failed validation:");
for (const err of validate.errors ?? []) {
  const at = err.instancePath ? `at ${err.instancePath}` : "at root";
  console.error(`- ${at}: ${err.message}`);
}
process.exit(1);
