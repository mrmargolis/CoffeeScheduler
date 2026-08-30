import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, cleanup, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { SWRConfig } from "swr";
import Home from "@/app/page";

// Mock FullCalendar since it doesn't render in happy-dom
vi.mock("@fullcalendar/react", () => ({
  default: () => <div data-testid="fullcalendar">Calendar</div>,
}));
vi.mock("@fullcalendar/daygrid", () => ({ default: {} }));

const mockBeans = [
  {
    id: "bean-1",
    name: "Ethiopia Guji",
    roaster: "Square Mile",
    roast_date: "2026-01-01",
    weight_grams: 250,
    remaining_grams: 200,
    effective_rest_days: 30,
    ready_date: "2026-01-31",
    total_brewed_grams: 50,
    total_split_grams: 0,
    archived: false,
    is_frozen: false,
    rest_days: null,
    notes: null,
    display_order: null,
    cost: null,
    flavour_profile: null,
    country: null,
    region: null,
    variety: null,
    processing: null,
  },
];

const mockSchedule = [
  {
    date: "2026-02-01",
    consumptions: [
      { bean_id: "bean-1", bean_name: "Ethiopia Guji", roaster: "Square Mile", grams: 45 },
    ],
    is_gap: false,
    is_surplus: false,
    is_actual: false,
    is_skip: false,
  },
];

function mockFetch(url: string) {
  // A single bag comes back as an object, matching /api/beans/[id].
  if (/^\/api\/beans\/.+/.test(url))
    return Promise.resolve({
      ok: true,
      json: () => Promise.resolve({ ...mockBeans[0], recent_brews: [] }),
    });
  if (url.startsWith("/api/beans")) return Promise.resolve({ ok: true, json: () => Promise.resolve(mockBeans) });
  if (url.startsWith("/api/schedule")) return Promise.resolve({ ok: true, json: () => Promise.resolve(mockSchedule) });
  if (url.startsWith("/api/skip-days")) return Promise.resolve({ ok: true, json: () => Promise.resolve([]) });
  if (url.startsWith("/api/settings")) {
    return Promise.resolve({
      ok: true,
      json: () =>
        Promise.resolve({
          daily_consumption_grams: 45,
          default_rest_days: 30,
          roaster_defaults: [],
        }),
    });
  }
  return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
}

function renderHome() {
  return render(
    <SWRConfig value={{ provider: () => new Map(), dedupingInterval: 0 }}>
      <Home />
    </SWRConfig>
  );
}

beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn(mockFetch));
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("Home page", () => {
  it("renders the header with title and buttons", () => {
    renderHome();
    expect(screen.getByText("Coffee Scheduler")).toBeInTheDocument();
    expect(screen.getByLabelText("Settings")).toBeInTheDocument();
  });

  it("renders the backlog sidebar with beans", async () => {
    renderHome();
    expect(screen.getByText("Backlog")).toBeInTheDocument();
    // The bag also shows in the runway strip, so scope to the sidebar.
    const sidebar = screen.getByRole("complementary");
    await waitFor(() => {
      expect(within(sidebar).getByText("Ethiopia Guji")).toBeInTheDocument();
    });
  });

  it("renders the calendar area", () => {
    renderHome();
    expect(screen.getByTestId("fullcalendar")).toBeInTheDocument();
  });

  it("opens settings panel when Settings button is clicked", async () => {
    const user = userEvent.setup();
    renderHome();

    await user.click(screen.getByLabelText("Settings"));

    await waitFor(() => {
      expect(screen.getByText("Coffee per day (grams)")).toBeInTheDocument();
      expect(screen.getByText("Default rest (days)")).toBeInTheDocument();
    });
  });

  it("closes settings panel when Cancel is clicked", async () => {
    const user = userEvent.setup();
    renderHome();

    await user.click(screen.getByLabelText("Settings"));
    await waitFor(() => {
      expect(screen.getByText("Coffee per day (grams)")).toBeInTheDocument();
    });

    await user.click(screen.getByText("Cancel"));
    await waitFor(() => {
      expect(screen.queryByText("Coffee per day (grams)")).not.toBeInTheDocument();
    });
  });

  it("shows bean detail when a bean is clicked in the sidebar", async () => {
    const user = userEvent.setup();
    renderHome();

    const sidebar = screen.getByRole("complementary");
    await waitFor(() => {
      expect(within(sidebar).getByText("Ethiopia Guji")).toBeInTheDocument();
    });

    await user.click(within(sidebar).getByText("Ethiopia Guji"));

    // BeanDetail replaces BeanList, bringing its own back-bar with it.
    await waitFor(() => {
      expect(screen.getByText("Back to backlog")).toBeInTheDocument();
    });
  });

  it("shows days of coffee remaining in the runway strip", async () => {
    renderHome();
    await waitFor(() => {
      expect(screen.getByText(/days of coffee/)).toBeInTheDocument();
    });
  });

  it("renders the Publish button", () => {
    renderHome();
    expect(screen.getByText("Publish")).toBeInTheDocument();
  });

  it("shows Publishing... state and re-enables on success", async () => {
    const user = userEvent.setup();
    renderHome();

    const publishBtn = screen.getByText("Publish");
    await user.click(publishBtn);

    // Button should show publishing state
    await waitFor(() => {
      expect(screen.getByText("Publish")).toBeInTheDocument();
      expect(screen.getByText("Publish")).not.toBeDisabled();
    });
  });

  it("calls /api/publish when Publish is clicked", async () => {
    const user = userEvent.setup();
    renderHome();

    await user.click(screen.getByText("Publish"));

    await waitFor(() => {
      expect(vi.mocked(fetch)).toHaveBeenCalledWith("/api/publish", {
        method: "POST",
      });
    });
  });

  it("shows alert when publish fails", async () => {
    const user = userEvent.setup();
    vi.stubGlobal("alert", vi.fn());

    // Override fetch to fail for /api/publish
    vi.mocked(fetch).mockImplementation((url: any) => {
      if (url === "/api/publish") {
        return Promise.resolve({
          ok: false,
          json: () => Promise.resolve({ details: "deploy error" }),
        } as Response);
      }
      return mockFetch(url) as Promise<Response>;
    });

    renderHome();
    await user.click(screen.getByText("Publish"));

    await waitFor(() => {
      expect(window.alert).toHaveBeenCalledWith(
        "Publish failed: deploy error"
      );
    });
  });
});
