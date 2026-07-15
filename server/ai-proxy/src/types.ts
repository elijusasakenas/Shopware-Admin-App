export interface Env extends Cloudflare.Env {
  ANTHROPIC_API_KEY: string;
  CAPABILITY_SECRET: string;
  APPLE_APP_ID?: string;
}

export interface ApprovalAction {
  fingerprint: string;
  tool: string;
  summary: string;
}

export interface ApprovalChallenge {
  token: string;
  actions: ApprovalAction[];
  expires_at: number;
}

export interface CapabilityPayload {
  kind: "mcp-capability";
  upstreamURL: string;
  upstreamToken: string;
  approvalGrants: Record<string, string>;
  subject: string;
  clientID: string;
  expiresAt: number;
}

export interface ApprovalPayload {
  kind: "approval";
  clientID: string;
  shopHost: string;
  subject: string;
  approvalID: string;
  approved: string[];
  expiresAt: number;
}
