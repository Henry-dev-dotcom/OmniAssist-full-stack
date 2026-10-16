type OmniAssistMarkProps = {
  className?: string;
};

export function OmniAssistMark({ className }: OmniAssistMarkProps) {
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      viewBox="0 0 64 64"
    >
      <circle cx="32" cy="32" r="21" stroke="currentColor" strokeWidth="4" />
      <path
        d="m17 39 11-11 8 8 12-14"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="4"
      />
      <circle cx="48" cy="22" r="4" fill="currentColor" />
    </svg>
  );
}
