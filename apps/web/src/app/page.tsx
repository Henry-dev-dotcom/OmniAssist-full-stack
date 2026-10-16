import { OmniAssistMark } from "@/components/brand/omniassist-mark";

const workspaceIdeas = [
  {
    number: "01",
    title: "Plan with context",
    description: "Keep the next action connected to the project and milestone behind it.",
  },
  {
    number: "02",
    title: "Keep research together",
    description: "Bring reviews, analysis, and experiment notes into one considered workspace.",
  },
  {
    number: "03",
    title: "Notice your progress",
    description: "Make steady movement visible without adding noise to the work.",
  },
];

export default function Home() {
  return (
    <div className="site-shell">
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>

      <aside className="sidebar" aria-label="OmniAssist workspace">
        <a className="brand-lockup" href="#overview" aria-label="OmniAssist overview">
          <span className="brand-mark-wrap">
            <OmniAssistMark className="brand-mark" />
          </span>
          <span className="brand-name">OmniAssist</span>
        </a>
        <p className="sidebar-tagline">Research, with room to think.</p>

        <nav className="workspace-nav" aria-label="Workspace navigation">
          <span className="nav-label">YOUR WORKSPACE</span>
          <a className="nav-link nav-link-active" href="#overview" aria-current="page">
            <span className="nav-indicator" aria-hidden="true" />
            Overview
          </a>
          <a className="nav-link" href="#capabilities">
            <span className="nav-indicator" aria-hidden="true" />
            What it holds
          </a>
        </nav>

        <div className="sidebar-note">
          <span className="sidebar-note-mark" aria-hidden="true" />
          <div>
            <span className="sidebar-note-label">A WORK IN PROGRESS</span>
            <span className="sidebar-note-copy">Built one useful step at a time.</span>
          </div>
        </div>
      </aside>

      <main className="main-column" id="main-content">
        <header className="topbar">
          <p className="topbar-label">A research planner</p>
          <span className="topbar-status">
            <span className="status-dot" aria-hidden="true" />
            Focused work, thoughtfully organized
          </span>
        </header>

        <section className="hero" id="overview" aria-labelledby="hero-title">
          <div className="hero-copy">
            <p className="eyebrow">PLANNING &amp; RESEARCH</p>
            <h1 id="hero-title">Plan today.<br />Advance your research.</h1>
            <p className="hero-description">
              A calmer place to connect the next small action with the questions that matter
              most to your work.
            </p>
            <a className="primary-link" href="/signin">
              Enter the workspace
              <span className="arrow-mark" aria-hidden="true">↗</span>
            </a>
          </div>

          <aside className="hero-note" aria-label="OmniAssist guiding idea">
            <span className="hero-note-mark" aria-hidden="true">
              <OmniAssistMark className="note-symbol" />
            </span>
            <p className="hero-note-label">THE OMNIASSIST APPROACH</p>
            <p className="hero-note-quote">Keep the next step visible. Give important questions room to grow.</p>
            <span className="hero-note-rule" aria-hidden="true" />
            <p className="hero-note-caption">Made for the long arc of research.</p>
          </aside>
        </section>

        <section className="capabilities" id="capabilities" aria-labelledby="capabilities-title">
          <div className="section-heading">
            <p className="eyebrow">A THOUGHTFUL FOUNDATION</p>
            <h2 id="capabilities-title">Structure that supports the work.</h2>
            <p className="section-description">
              The workspace connects everyday planning with the long arc of postgraduate research.
            </p>
          </div>

          <div className="capability-list">
            {workspaceIdeas.map((idea) => (
              <article className="capability-row" key={idea.number}>
                <span className="capability-number">{idea.number}</span>
                <div className="capability-copy">
                  <h3>{idea.title}</h3>
                  <p>{idea.description}</p>
                </div>
                <span className="status-chip">In progress</span>
              </article>
            ))}
          </div>
          <p className="foundation-note">
            The installable workspace brings projects, milestones, reviews, analysis records and experiment notes into one place.
          </p>
        </section>

        <footer className="page-footer">
          <span>OmniAssist</span>
          <span>Made for focused research work.</span>
        </footer>
      </main>
    </div>
  );
}
