/**
 * EXAMPLE TOUR — reference only. Copy into your project as
 * `.claude/tours/<name>.mjs` and rewrite every selector, URL and assertion
 * for YOUR app. Nothing here is a real project's configuration.
 *
 * Adapted from the tour this capability was proven on: a walkthrough that
 * demonstrated a scheduler had actually triggered an agent run, narrated for a
 * human and re-run in verify mode as a check. It passed 4/4 assertions and
 * surfaced 4 real HTTP 404s the UI was swallowing.
 *
 * Run:
 *   node "$CLAUDE_PLUGIN_ROOT/scripts/guided-tour.mjs" .claude/tours/example.mjs \
 *     --base-url http://localhost:3000            # narrate (watch it)
 *   node "$CLAUDE_PLUGIN_ROOT/scripts/guided-tour.mjs" .claude/tours/example.mjs \
 *     --base-url http://localhost:3000 --verify   # verify (exit code + report.json)
 */

export default {
  name: 'example-tour',

  // Placeholder. Prefer passing --base-url resolved from `.claude/sdlc.yml`
  // (`browser.frontend_url`) so the tour is not pinned to one machine's ports.
  baseUrl: 'http://localhost:3000',

  steps: [
    { goto: '/', say: 'Example tour — walking the surfaces that prove the feature works', dwell: 2500 },

    // Login is `optional`: an already-authenticated browser skips these three
    // steps instead of failing. Never commit real credentials to a tour.
    {
      fill: { selector: 'input[type="email"], input[name="email"]', value: 'demo@example.test', label: 'email: demo@example.test' },
      optional: true,
      dwell: 800,
    },
    {
      fill: { selector: 'input[type="password"], input[name="password"]', value: 'example-password', label: 'password: ••••••••' },
      optional: true,
      dwell: 800,
    },
    {
      click: 'button[type="submit"]',
      label: 'sign in',
      say: 'Authenticating (skipped if already signed in)',
      optional: true,
      dwell: 3000,
    },

    {
      goto: '/items',
      say: 'The list view — every item the feature creates shows up here',
      waitFor: 'css=[data-testid="item-list"]',
      expect: ['example-item'],
      shot: 'tour-1-list',
      dwell: 5000,
    },

    {
      goto: '/settings',
      say: 'Settings — the configuration that drives the list',
      expect: ['Notifications', 'Schedule'],
      shot: 'tour-2-settings',
      dwell: 5000,
    },

    {
      click: 'text=example-item',
      label: 'open example-item',
      say: 'Opening a single item to see its detail view',
      dwell: 4000,
    },

    {
      say: 'The detail view — this is the evidence the feature is wired end to end',
      expect: ['Created', 'Status'],
      shot: 'tour-3-detail',
      dwell: 6000,
    },
  ],
};
