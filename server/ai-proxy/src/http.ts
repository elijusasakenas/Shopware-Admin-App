export class HTTPError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export function errorResponse(status: number, message: string, requestID?: string): Response {
  return Response.json(
    { error: { message, request_id: requestID } },
    { status, headers: securityHeaders(requestID) },
  );
}

export function jsonResponse(value: unknown, init: ResponseInit = {}, requestID?: string): Response {
  const headers = new Headers(init.headers);
  for (const [key, value] of Object.entries(securityHeaders(requestID))) headers.set(key, value);
  return Response.json(value, { ...init, headers });
}

export function securityHeaders(requestID?: string): Record<string, string> {
  return {
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    ...(requestID ? { "X-Request-ID": requestID } : {}),
  };
}

export async function readJSON<T>(request: Request, maxBytes = 1_048_576): Promise<T> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().startsWith("application/json")) {
    throw new HTTPError(415, "Content-Type must be application/json.");
  }
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > maxBytes) throw new HTTPError(413, "Request body is too large.");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > maxBytes) throw new HTTPError(413, "Request body is too large.");
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as T;
  } catch {
    throw new HTTPError(400, "Invalid JSON body.");
  }
}

export async function readResponseText(response: Response, maxBytes = 131_072): Promise<string> {
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > maxBytes) throw new HTTPError(502, "Upstream response is too large.");
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new HTTPError(502, "Upstream response is too large.");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(result);
}

export function logEvent(
  level: "info" | "warn" | "error",
  event: string,
  fields: Record<string, unknown>,
): void {
  console.log(JSON.stringify({ level, event, timestamp: new Date().toISOString(), ...fields }));
}
