import { describe, expect, it } from "vitest";
import { appAttestPayload } from "./app-attest";
import { estimatedTokenReservation } from "./quota";

describe("App Attest request binding", () => {
  it("binds the assertion to method, path, challenge, and exact body hash", async () => {
    const payload = await appAttestPayload(
      "post",
      "/v1/chat",
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      new TextEncoder().encode("{}"),
    );
    expect(new TextDecoder().decode(payload)).toBe(
      "shopware-ai-app-attest-v1\nPOST\n/v1/chat\nAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n" +
      "RBNvo1WzZ4oRRq0W9-hknpT7T8If536DEMBg9hyq_4o",
    );
  });
});

describe("token reservations", () => {
  it("reserves a conservative floor before a provider call", () => {
    expect(estimatedTokenReservation(2_000, "250000")).toBe(250_000);
    expect(estimatedTokenReservation(300_000, "250000")).toBe(369_632);
    expect(estimatedTokenReservation(2_000_000, "250000")).toBe(1_000_000);
  });
});
