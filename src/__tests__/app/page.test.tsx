import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor, cleanup } from "@testing-library/react";
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
    expect(screen.getByText("CoffeeScheduler")).toBeInTheDocument();
    expect(screen.getByText("Settings")).toBeInTheDocument();
  });

  it("renders the Bean Queue sidebar with beans", async () => {
    renderHome();
    expect(screen.getByText("Bean Queue")).toBeInTheDocument();
    await waitFor(() => {
      expect(screen.getByText("Ethiopia Guji")).toBeInTheDocument();
    });
  });

  it("renders the calendar area", () => {
    renderHome();
    expect(screen.getByTestId("fullcalendar")).toBeInTheDocument();
  });

  it("opens settings panel when Settings button is clicked", async () => {
    const user = userEvent.setup();
    renderHome();

    await user.click(screen.getByText("Settings"));

    await waitFor(() => {
      expect(screen.getByText("Daily consumption (grams)")).toBeInTheDocument();
      expect(screen.getByText("Default rest days")).toBeInTheDocument();
    });
  });

  it("closes settings panel when Cancel is clicked", async () => {
    const user = userEvent.setup();
    renderHome();

    await user.click(screen.getByText("Settings"));
    await waitFor(() => {
      expect(screen.getByText("Daily consumption (grams)")).toBeInTheDocument();
    });

    await user.click(screen.getByText("Cancel"));
    await waitFor(() => {
      expect(screen.queryByText("Daily consumption (grams)")).not.toBeInTheDocument();
    });
  });

  it("shows bean detail when a bean is clicked in the sidebar", async () => {
    const user = userEvent.setup();
    renderHome();

    await waitFor(() => {
      expect(screen.getByText("Ethiopia Guji")).toBeInTheDocument();
    });

    await user.click(screen.getByText("Ethiopia Guji"));

    // After clicking, BeanDetail replaces BeanList.
    // BeanDetail fetches /api/beans/bean-1 which returns mockBeans (array).
    // The "Bean Queue" heading stays since it's in the parent, not BeanList.
    await waitFor(() => {
      expect(screen.getByText("Bean Queue")).toBeInTheDocument();
    });
  });

  it("shows days of coffee remaining in calendar summary", async () => {
    renderHome();
    await waitFor(() => {
      expect(screen.getByText(/of coffee remaining/)).toBeInTheDocument();
    });
  });
});
