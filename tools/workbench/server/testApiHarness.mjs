import { Readable, Writable } from 'node:stream';
import {
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { basename, join } from 'node:path';
import { createServer } from 'vite';

class TestResponse extends Writable {
  statusCode = 200;
  headers = new Map();
  chunks = [];

  _write(chunk, _encoding, callback) {
    this.chunks.push(Buffer.from(chunk));
    callback();
  }

  setHeader(name, value) {
    this.headers.set(name.toLowerCase(), String(value));
    return this;
  }

  getHeader(name) {
    return this.headers.get(name.toLowerCase());
  }

  getHeaders() {
    return Object.fromEntries(this.headers);
  }

  hasHeader(name) {
    return this.headers.has(name.toLowerCase());
  }

  removeHeader(name) {
    this.headers.delete(name.toLowerCase());
  }

  writeHead(statusCode, headers) {
    this.statusCode = statusCode;
    if (headers) {
      for (const [name, value] of Object.entries(headers)) {
        this.setHeader(name, value);
      }
    }
    return this;
  }
}

const root = process.argv[2];
const ipcDir = process.argv[3];
const requestsDir = join(ipcDir, 'requests');
const responsesDir = join(ipcDir, 'responses');
mkdirSync(requestsDir, { recursive: true });
mkdirSync(responsesDir, { recursive: true });
const server = await createServer({
  root,
  appType: 'spa',
  logLevel: 'silent',
  server: { middlewareMode: true, hmr: false },
});

async function request(input) {
  const req = Readable.from(input.body ? [input.body] : []);
  req.method = input.method;
  req.url = input.path;
  req.headers = input.headers ?? {};
  const res = new TestResponse();
  const finished = new Promise((resolve, reject) => {
    res.once('finish', resolve);
    res.once('error', reject);
  });
  server.middlewares.handle(req, res, error => {
    if (error) res.destroy(error);
    else {
      res.statusCode = 404;
      res.end();
    }
  });
  await finished;
  return {
    requestId: input.requestId,
    status: res.statusCode,
    headers: res.getHeaders(),
    body: Buffer.concat(res.chunks).toString('utf8'),
  };
}

writeFileSync(join(ipcDir, 'ready'), '');
let running = true;
process.once('SIGTERM', () => {
  running = false;
});
while (running) {
  for (const name of readdirSync(requestsDir)) {
    if (!name.endsWith('.json')) continue;
    const requestPath = join(requestsDir, name);
    const responsePath = join(responsesDir, name);
    let input;
    let output;
    try {
      input = JSON.parse(readFileSync(requestPath, 'utf8'));
      output = await request(input);
    } catch (error) {
      output = {
        requestId: input?.requestId ?? null,
        status: 500,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          error: error instanceof Error ? error.message : String(error),
        }),
      };
    }
    unlinkSync(requestPath);
    const temporary = join(responsesDir, `.${basename(name)}.tmp`);
    writeFileSync(temporary, JSON.stringify(output));
    renameSync(temporary, responsePath);
  }
  await new Promise(resolve => setTimeout(resolve, 5));
}
await server.close();
process.exit(0);
