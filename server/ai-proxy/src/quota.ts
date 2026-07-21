/**
 * Reserve before the provider call, using a deliberately high floor to cover
 * system/tool/MCP context that is not present in the client's JSON body.
 */
export function estimatedTokenReservation(bodyBytes: number, configuredValue?: string): number {
  const configured = boundedInteger(configuredValue, 250_000, 16_384, 1_000_000);
  return Math.min(1_000_000, Math.max(configured, Math.max(0, Math.trunc(bodyBytes)) + 69_632));
}

function boundedInteger(value: string | undefined, fallback: number, minimum: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  return Number.isFinite(parsed) ? Math.min(maximum, Math.max(minimum, Math.trunc(parsed))) : fallback;
}
