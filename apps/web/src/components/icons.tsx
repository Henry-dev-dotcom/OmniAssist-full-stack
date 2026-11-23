// One outline icon family for navigation: 24 px grid, 1.75 stroke, round joins, drawn in the
// current text colour. Decorative: the label next to each icon carries the meaning.

type IconProps = { className?: string };

function Svg({ className, children }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      className={className ?? "nav-icon"}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export const TodayIcon = (p: IconProps) => (
  <Svg {...p}><circle cx="12" cy="12" r="4" /><path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4" /></Svg>
);
export const ProjectsIcon = (p: IconProps) => (
  <Svg {...p}><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z" /></Svg>
);
export const GrantsIcon = (p: IconProps) => (
  <Svg {...p}><rect x="2.5" y="6" width="19" height="12" rx="2" /><circle cx="12" cy="12" r="2.5" /><path d="M6 9.5v5M18 9.5v5" /></Svg>
);
export const ScholarshipsIcon = (p: IconProps) => (
  <Svg {...p}><path d="M2.5 9 12 4.5 21.5 9 12 13.5z" /><path d="M6.5 11v4.5c1.5 1.6 3.4 2.5 5.5 2.5s4-.9 5.5-2.5V11M21.5 9v5" /></Svg>
);
export const CalendarIcon = (p: IconProps) => (
  <Svg {...p}><rect x="3.5" y="5" width="17" height="15.5" rx="2" /><path d="M3.5 10h17M8 3v4M16 3v4" /></Svg>
);
export const MilestonesIcon = (p: IconProps) => (
  <Svg {...p}><path d="M5 21V4M5 4.5h11l-2 3.5 2 3.5H5" /></Svg>
);
export const ResearchIcon = (p: IconProps) => (
  <Svg {...p}><circle cx="10.5" cy="10.5" r="6" /><path d="m15 15 5.5 5.5" /></Svg>
);
export const MoreIcon = (p: IconProps) => (
  <Svg {...p}><circle cx="5.5" cy="12" r="1.25" /><circle cx="12" cy="12" r="1.25" /><circle cx="18.5" cy="12" r="1.25" /></Svg>
);
export const SetupIcon = (p: IconProps) => (
  <Svg {...p}><path d="M12 5v14M5 12h14" /></Svg>
);
export const SignOutIcon = (p: IconProps) => (
  <Svg {...p}><path d="M14 4.5h3.5a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H14M10 16l-4-4 4-4M6 12h9.5" /></Svg>
);
