import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockRunPublish } = vi.hoisted(() => ({
  mockRunPublish: vi.fn(),
}));

vi.mock("@/lib/run-publish", () => ({
  runPublish: mockRunPublish,
}));

import { POST } from "@/app/api/publish/route";

beforeEach(() => {
  mockRunPublish.mockReset();
});

describe("POST /api/publish", () => {
  it("returns 200 on successful publish", async () => {
    mockRunPublish.mockResolvedValue({ ok: true });

    const res = await POST();
    expect(mockRunPublish).toHaveBeenCalled();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("returns 500 when publish fails", async () => {
    mockRunPublish.mockResolvedValue({ ok: false, error: "script crashed" });

    const res = await POST();
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toBe("Publish failed");
    expect(body.details).toBe("script crashed");
  });
});
