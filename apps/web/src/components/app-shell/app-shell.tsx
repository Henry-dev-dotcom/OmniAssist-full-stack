"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { clearSession, readSession } from "@/lib/auth/session";
import { useEffect, useId, useRef, useState, useSyncExternalStore } from "react";
import {
  CalendarIcon, GrantsIcon, MilestonesIcon, MoreIcon, ProjectsIcon, ResearchIcon, ScholarshipsIcon, SetupIcon,
  SignOutIcon, TodayIcon,
} from "@/components/icons";

type NavItem = { href: string; label: string; Icon: (props: { className?: string }) => React.ReactNode };

// Phones show the first four as tabs and the rest under More; the sidebar shows them all.
const primary: NavItem[] = [
  { href: "/app/today", label: "Today", Icon: TodayIcon },
  { href: "/app/projects", label: "Projects", Icon: ProjectsIcon },
  { href: "/app/grants", label: "Grants", Icon: GrantsIcon },
  { href: "/app/scholarships", label: "Scholarships", Icon: ScholarshipsIcon },
];
const secondary: NavItem[] = [
  { href: "/app/calendar", label: "Calendar", Icon: CalendarIcon },
  { href: "/app/milestones", label: "Milestones", Icon: MilestonesIcon },
  { href: "/app/research", label: "Research", Icon: ResearchIcon },
];
const nav = [...primary, ...secondary];

// The name lives in browser storage, so the server renders the fallback and the browser
// swaps in the stored name without a hydration mismatch.
const noSubscribe = () => () => {};
const storedName = () => readSession()?.display_name || "You";
const serverName = () => "You";

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const name = useSyncExternalStore(noSubscribe, storedName, serverName);
  const [moreOpen, setMoreOpen] = useState(false);
  const moreId = useId();
  const moreButton = useRef<HTMLButtonElement>(null);
  const morePanel = useRef<HTMLDivElement>(null);
  const inMore = secondary.some((item) => item.href === pathname);

  function signOut() {
    clearSession();
    router.push("/signin");
  }

  // Close the More panel on Escape or a tap outside it, returning focus to its button.
  useEffect(() => {
    if (!moreOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") { setMoreOpen(false); moreButton.current?.focus(); }
    };
    const onPointer = (event: PointerEvent) => {
      const target = event.target as Node;
      if (!morePanel.current?.contains(target) && !moreButton.current?.contains(target)) setMoreOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
  }, [moreOpen]);

  const link = (item: NavItem, className: string, onClick?: () => void) => (
    <Link
      className={`${className} ${pathname === item.href ? "active" : ""}`}
      href={item.href}
      key={item.href}
      aria-current={pathname === item.href ? "page" : undefined}
      onClick={onClick}
    >
      <item.Icon />{item.label}
    </Link>
  );

  return (
    <div className="product-shell">
      <a className="skip-link" href="#app-main">Skip to main content</a>
      <aside className="product-sidebar">
        <Link className="product-brand" href="/app/today"><span className="brand-symbol" aria-hidden="true">∞</span><span>OmniAssist</span></Link>
        <p className="workspace-caption">My workspace</p>
        <nav className="product-nav" aria-label="Workspace navigation">{nav.map((item) => link(item, "product-nav-link"))}</nav>
        <div className="sidebar-bottom">
          <Link className="product-nav-link" href="/onboarding"><SetupIcon />Workspace setup</Link>
          <button className="signout-button" type="button" onClick={signOut}><SignOutIcon />Sign out</button>
        </div>
      </aside>
      <main className="product-main" id="app-main" tabIndex={-1}>
        <header className="product-topbar">
          <p className="topbar-label">OmniAssist workspace</p>
          <div className="user-pill"><span aria-hidden="true">{name.slice(0, 1).toUpperCase()}</span><b><span className="sr-only">Signed in as </span>{name}</b></div>
        </header>
        {children}
      </main>
      <nav className="mobile-nav" aria-label="Mobile workspace navigation">
        {primary.map((item) => link(item, ""))}
        <button
          ref={moreButton}
          type="button"
          className={`mobile-more-button ${inMore || moreOpen ? "active" : ""}`}
          aria-expanded={moreOpen}
          aria-controls={moreId}
          onClick={() => setMoreOpen((open) => !open)}
        >
          <MoreIcon />More
        </button>
        {moreOpen && (
          <div className="mobile-more-panel" id={moreId} ref={morePanel}>
            {secondary.map((item) => link(item, "mobile-more-link", () => setMoreOpen(false)))}
            <Link className="mobile-more-link" href="/onboarding" onClick={() => setMoreOpen(false)}><SetupIcon />Workspace setup</Link>
            <button className="mobile-more-link mobile-more-signout" type="button" onClick={signOut}><SignOutIcon />Sign out</button>
          </div>
        )}
      </nav>
    </div>
  );
}
