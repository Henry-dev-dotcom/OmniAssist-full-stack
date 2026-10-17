import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test("landing page has no serious axe violations and works at 320px", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: /Plan today/i })).toBeVisible();
  await expect(page.getByRole("link", { name: /Enter the workspace/i })).toHaveAttribute("href", "/signin");
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Skip to main content" })).toBeFocused();
  const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(horizontalOverflow).toBe(false);
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  expect(results.violations.map(({ id, impact, description }) => ({ id, impact, description }))).toEqual([]);
});

test("protected workspace routes redirect signed-out visitors", async ({ page }) => {
  await page.goto("/app/research");
  await expect(page).toHaveURL(/\/signin(?:\?.*)?$/);
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
});

test("authenticated research workspace remains accessible and fits 320px", async ({ page, context }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await context.addCookies([{ name: "omniassist_session", value: "1", url: "http://127.0.0.1:4173" }]);
  await page.goto("/app/research");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(horizontalOverflow).toBe(false);
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  expect(results.violations).toEqual([]);
});

test("grant tracking is reachable from the workspace navigation on mobile", async ({ page, context }) => {
  await page.setViewportSize({ width: 320, height: 800 });
  await context.addCookies([{ name: "omniassist_session", value: "1", url: "http://127.0.0.1:4173" }]);
  await page.goto("/app/grants");
  await expect(page.getByRole("heading", { level: 1, name: "Grant tracking" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Mobile workspace navigation" }).getByRole("link", { name: "Grants" })).toHaveAttribute("href", "/app/grants");
  const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(horizontalOverflow).toBe(false);
});

test("experiment entry draft survives a reload and remains a draft", async ({ page, context }) => {
  await context.addCookies([{ name: "omniassist_session", value: "1", url: "http://127.0.0.1:4173" }]);
  await page.goto("/app/research");
  await page.getByRole("button", { name: "Experiment log" }).click();
  await page.getByLabel("Title", { exact: true }).fill("Reload recovery check");
  await page.getByLabel("objective", { exact: true }).fill("This is a local draft, not a finalized record.");
  await expect.poll(() => page.evaluate(() => {
    const stored = localStorage.getItem("omniassist-draft:experiment-new");
    return stored ? JSON.parse(stored).value.objective : null;
  })).toBe("This is a local draft, not a finalized record.");
  await page.reload();
  await page.getByRole("button", { name: "Experiment log" }).click();
  await expect(page.getByLabel("Title", { exact: true })).toHaveValue("Reload recovery check");
  await expect(page.locator("textarea").first()).toHaveValue("This is a local draft, not a finalized record.");
  await expect(page.getByRole("button", { name: "Save draft", exact: true })).toBeVisible();
});

test("production service worker provides only the generic offline fallback", async ({ page, context }) => {
  await page.goto("/");
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await page.waitForFunction(() => "serviceWorker" in navigator && Boolean(navigator.serviceWorker.controller));
  await context.setOffline(true);
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(page.getByRole("heading", { name: "You’re offline for now." })).toBeVisible();
  await context.setOffline(false);
});
