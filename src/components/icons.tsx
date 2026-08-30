/**
 * Stroke icons on a 24px grid, sized down at the call site. Kept together so
 * weight and cap style stay consistent across the app.
 */
type IconProps = { size?: number; className?: string };

function svg(
  path: React.ReactNode,
  { size = 16, className }: IconProps,
  fill = false
) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={fill ? "currentColor" : "none"}
      stroke={fill ? undefined : "currentColor"}
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden="true"
    >
      {path}
    </svg>
  );
}

export const BeanMark = (p: IconProps) =>
  svg(
    <>
      <path d="M4 9h13v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5V9Z" />
      <path d="M17 10h1.5a2.5 2.5 0 0 1 0 5H17" />
      <path d="M8 3v2.5M12 3v2.5" />
    </>,
    p
  );

export const ImportIcon = (p: IconProps) =>
  svg(
    <>
      <path d="M12 3v12" />
      <path d="m7 10 5 5 5-5" />
      <path d="M4 20h16" />
    </>,
    p
  );

export const PublishIcon = (p: IconProps) =>
  svg(
    <>
      <path d="M12 20V8" />
      <path d="m7 13 5-5 5 5" />
      <path d="M4 4h16" />
    </>,
    p
  );

export const SettingsIcon = (p: IconProps) =>
  svg(
    <>
      <path d="M4 7h10M18 7h2M4 17h4M12 17h8" />
      <circle cx="16" cy="7" r="2.3" />
      <circle cx="10" cy="17" r="2.3" />
    </>,
    p
  );

export const ChevronLeft = (p: IconProps) => svg(<path d="m14 6-6 6 6 6" />, p);
export const ChevronRight = (p: IconProps) => svg(<path d="m10 6 6 6-6 6" />, p);

export const InfoIcon = (p: IconProps) =>
  svg(
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v5" />
      <path d="M12 7.6h.01" />
    </>,
    p
  );

export const CloseIcon = (p: IconProps) =>
  svg(<path d="m6 6 12 12M18 6 6 18" />, p);

export const PlusIcon = (p: IconProps) => svg(<path d="M12 5v14M5 12h14" />, p);

export const SnowflakeIcon = (p: IconProps) =>
  svg(<path d="M12 3v18M4.2 7.5l15.6 9M19.8 7.5l-15.6 9" />, p);

export const WarningIcon = (p: IconProps) =>
  svg(
    <>
      <path d="M12 8.5v5" />
      <path d="M12 17h.01" />
      <path d="M10.3 3.9 2.5 18a1.9 1.9 0 0 0 1.7 2.9h15.6a1.9 1.9 0 0 0 1.7-2.9L13.7 3.9a1.9 1.9 0 0 0-3.4 0Z" />
    </>,
    p
  );

export const CalendarIcon = (p: IconProps) =>
  svg(
    <>
      <rect x="3" y="5" width="18" height="16" rx="3" />
      <path d="M3 10h18M8 3v4M16 3v4" />
    </>,
    p
  );

export const BacklogIcon = (p: IconProps) =>
  svg(
    <>
      <rect x="3" y="4" width="18" height="5" rx="2" />
      <rect x="3" y="12" width="18" height="5" rx="2" />
      <path d="M7 20h10" />
    </>,
    p
  );

export const GripIcon = ({ size = 12, className }: IconProps) =>
  svg(
    <>
      <circle cx="9" cy="5" r="1.6" />
      <circle cx="15" cy="5" r="1.6" />
      <circle cx="9" cy="12" r="1.6" />
      <circle cx="15" cy="12" r="1.6" />
      <circle cx="9" cy="19" r="1.6" />
      <circle cx="15" cy="19" r="1.6" />
    </>,
    { size, className },
    true
  );
