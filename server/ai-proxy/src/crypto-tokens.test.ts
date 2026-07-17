import { describe, expect, it } from "vitest";
import { openToken, sealToken } from "./crypto-tokens";

describe("capability token configuration", () => {
  it("returns a service configuration error when the signing secret is missing", async () => {
    await expect(sealToken({}, undefined)).rejects.toMatchObject({
      status: 503,
      message: "Capability secret is not configured securely.",
    });
    await expect(openToken("v1.AAAAAAAAAAAAAAAA.AA", undefined)).rejects.toMatchObject({
      status: 503,
      message: "Capability secret is not configured securely.",
    });
  });
});
