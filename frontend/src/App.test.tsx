import { render, screen } from "@testing-library/react";
import App from "./App";

describe("App", () => {
  afterEach(() => vi.unstubAllGlobals());

  test("shows the backend as ok when /api/health answers", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    render(<App />);
    expect(await screen.findByText("ok")).toBeInTheDocument();
  });

  test("shows the backend as unreachable when the request fails", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("down")));
    render(<App />);
    expect(await screen.findByText("unreachable")).toBeInTheDocument();
  });
});
