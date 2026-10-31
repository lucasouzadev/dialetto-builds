// Turns whatever was pasted into the APP_STORE_CONNECT_API_KEY secret into a
// proper PEM on stdout. Prints only the key, never a log line about it.
//
// Accepted (any mix of CR, literal "\n", and surrounding whitespace):
//   1. the .p8 file as is                       (BEGIN ... END, real lines)
//   2. the .p8 file flattened to one line        (BEGIN ... END, no line breaks)
//   3. base64 of the whole .p8 file
//   4. just the base64 body between BEGIN and END (what `base64 -i` of the DER gives)
const raw = process.env.ASC_KEY_P8 ?? "";
const HEAD = "-----BEGIN PRIVATE KEY-----";
const FOOT = "-----END PRIVATE KEY-----";

const clean = (s) => s.replace(/\r/g, "").replace(/\\n/g, "\n").trim();
const wrap = (b64) => b64.match(/.{1,64}/g).join("\n");
const pem = (b64) => `${HEAD}\n${wrap(b64)}\n${FOOT}\n`;
const onlyB64 = (s) => s.replace(/\s+/g, "");
const isB64 = (s) => s.length > 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(s);

function normalize(input) {
  const text = clean(input);
  // 1 and 2: there are BEGIN/END markers; rebuild the body between them.
  if (text.includes("BEGIN PRIVATE KEY")) {
    const body = onlyB64(text.replace(HEAD, "").replace(FOOT, ""));
    return isB64(body) ? pem(body) : null;
  }
  const compact = onlyB64(text);
  if (!isB64(compact)) return null;
  // 3: base64 of the whole file.
  const decoded = Buffer.from(compact, "base64").toString("latin1");
  if (decoded.includes("BEGIN PRIVATE KEY")) return normalize(decoded);
  // 4: bare body.
  return pem(compact);
}

const out = normalize(raw);
if (!out) {
  console.error("::error::APP_STORE_CONNECT_API_KEY is not a PEM key, nor base64 of one.");
  process.exit(1);
}
process.stdout.write(out);
