export interface Bean {
  id: string; // UUID from BeanConqueror
  name: string;
  roaster: string;
  roast_date: string | null; // ISO 8601 date or null for "Invalid date"
  weight_grams: number;
  cost: number | null;
  flavour_profile: string | null;
  country: string | null;
  region: string | null;
  variety: string | null;
  processing: string | null;
  archived: boolean;
  // User-managed fields
  rest_days: number | null; // Override for this specific bean
  is_frozen: boolean;
  planned_thaw_date: string | null; // ISO 8601 date for auto-thaw
  freeze_after_grams: number | null; // Auto-freeze after consuming this many grams
  notes: string | null;
  display_order: number | null; // For manual queue ordering
}

export interface Brew {
  id?: number;
  bean_id: string;
  ground_coffee_grams: number;
  creation_date: string; // ISO 8601 date
  bean_age_days: number | null;
  rating: number | null;
}

export interface RoasterDefault {
  roaster: string;
  rest_days: number;
}

export interface FreezeEvent {
  id?: number;
  bean_id: string;
  event_type: "freeze" | "thaw";
  event_date: string; // ISO 8601 date
}

export interface Settings {
  daily_consumption_grams: number;
  default_rest_days: number;
}

export interface ScheduleDay {
  date: string; // ISO 8601 date
  consumptions: {
    bean_id: string;
    bean_name: string;
    roaster: string;
    grams: number;
  }[];
  is_gap: boolean; // No coffee available
  is_surplus: boolean; // Multiple bags ready
  is_actual: boolean; // Uses real brew data (past day)
  is_skip: boolean; // User marked as skip day (traveling, etc.)
}

export interface SkipDayRange {
  id?: number;
  start_date: string; // ISO 8601 date
  end_date: string; // ISO 8601 date
  reason?: string | null;
}

export interface BeanWithComputed extends Bean {
  effective_rest_days: number;
  ready_date: string | null;
  remaining_grams: number;
  total_brewed_grams: number;
}
