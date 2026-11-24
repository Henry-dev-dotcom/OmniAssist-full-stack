import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = { title: "Page not found" };

export default function NotFound() {
  return (
    <main className="not-found-page">
      <div>
        <span className="brand-symbol" aria-hidden="true">∞</span>
        <p className="eyebrow">Page not found</p>
        <h1>There is nothing at this address.</h1>
        <p>The link may be old, or the page may have moved. Your workspace is still where you left it.</p>
        <Link className="button button-primary button-link" href="/app/today">Go to Today</Link>
      </div>
    </main>
  );
}
