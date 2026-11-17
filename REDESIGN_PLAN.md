# Pushed Redesign Plan

Goal: same app, less confusion, premium look. It should feel like a widget app first.
Ships as one release (1.3).

**Source of truth for the look:** the design canvas "Pushed Redesign"
(https://claude.ai/artifact/UrGWwG4v5WPeDceNFTX4Q1). Every step below is built to
match it and checked against it in the simulator with screenshots. The widget math
lives in its `Widget.dc.html` board and should be ported, not reinvented.

## Guiding ideas

- The widget is the product. The graph fills the widget, it doesn't float in it.
- Picking, rotating and customizing looks lives in one place: the Styles screen.
- Show, don't explain. If a screen needs a paragraph of footer text, the screen is wrong.
- Every tap responds instantly, with native iOS motion and haptics. It should feel like an Apple app.

## Widget

### Fill the frame
- Square size comes from the widget's height (7 rows reach top to bottom), then the
  widget shows as many weeks as fit across. Row and column gaps stretch slightly so
  the grid meets the edges exactly.
- Results on an iPhone Pro Max: Small about 9 weeks, Medium about 22 weeks, Large
  about 40 weeks in two rows of weeks (older on top, the bottom row ends today).
- Range becomes "Show up to" (a cap), not a fixed 4, 13, 26 or 52 weeks.

### Header
- Small: flame plus streak number on the left, a check circle for today on the right.
- Medium: "12 day streak" on the left, a dot plus "Pushed today" on the right, one line.
- Large: big streak number, "day streak", today status, best streak and this year's total.
- Not pushed yet: the dot or circle empties and the text reads "Not yet today". Nothing else moves.
- No footer row on any size.

### Labels and today
- A thin ring around today's square on every size and every look.
- Small and Medium: no month or day labels.
- Large only: month names above each row of weeks, and Mon, Wed, Fri down the left side.

### Looks
All five stay, each revamped. Every look shares one layout and changes only color,
square shape, type and backdrop, so switching never moves anything.

- **Classic:** GitHub's dark graph, exact greens (#0E4429, #006D32, #26A641, #39D353), #0D1117 ground, near-square corners.
- **Aurora:** navy with teal and violet light, rounded squares, soft glow on busy days, gradient number.
- **Ember:** warm black, coal to flame in five steps, glow on busy days, gradient number.
- **Terminal:** phosphor green, monospace, sharp squares, faint scanlines.
- **Paper:** ink dots on warm paper, serif number. The one light look.
- **Marks (new):** one solid color, no glow. Each day is a symbol: a dot when pushed
  (brighter when busier), × for a missed day, F for a freeze, R for a rest day.
  Today gets the ring. The color is changeable in Customize. Uses the existing rest
  day and freeze data from `StreakProtection`.

### Lock screen
Out of scope. The smallest (circular) one may get a refresh if it clearly helps. Optional.

## In-app redesign

- **Home:** large title "Pushed" and a gear button. A live Medium widget, with a
  line under it ("Today Classic · Tomorrow Aurora"). A "Pushed today" card with the
  number of contributions and the last time. Three stat tiles (current, best, this
  year). One row into Styles showing the look swatches and "3 looks in rotation".
- **Styles:** replaces both the Style Gallery and Daily Rotation.
  - A big live preview at the top that changes the instant you tap a look. This fixes
    the rotation bug from the screen recording.
  - A Small, Medium, Large switch for the preview.
  - A sideways row of look cards, each showing the look itself. Tap a card to preview
    it. The circle on a card adds it to or removes it from the rotation. Previewing and
    rotating are separate actions.
  - A Rotation strip showing the order day by day ("Today Classic, Wed Aurora, Thu
    Ember"), in the order looks were added, changing at midnight.
  - A "Customize" button opens a half-height sheet so the preview stays visible:
    square shape (Look, Square, Rounded, Dot), color swatches, glow, More options
    (background, font, spacing), and "Save as my look".
  - A "New" card at the end of the row for starting from scratch.
- **Settings (behind the gear):** Widget (Show up to), Streak (Rest days, Freezes),
  Reminders (three switches), GitHub (Account, Refresh now), version at the bottom.
  Testing stays in debug builds only.
- Copy: short, no em dashes, no instruction paragraphs.
- Simplify Edit Widget options: drop "Same as app" and reduce the parameters.

## Confirmed bugs to fix in the redesign

- **Rotation preview:** it shows "today's pick" (`dayNumber % checkedCount` over a fixed
  order, `Shared/StyleLibrary.swift` `rotationPick`) instead of the look you tapped.
  The fix is the new Styles screen above, plus keeping the rotation in the order looks were added.
- **Laggy checkmarks:** every tap saves the whole style library and reloads every
  widget timeline before the screen updates. The screen should update instantly,
  with saving and widget reloads batched in the background.

## Rename cleanup

Code and targets are already "Pushed". What remains:
- GitHub repo `git-widget` becomes `pushed` (GitHub redirects the old URL), then update the remote.
- Remove the stale worktree in `.claude/worktrees/`.
- Rename `StreakWidgetView` to `PushedWidgetView`.
- Local folder `git-streak-widget` becomes `pushed`. Do this last, since it moves the working session.

## App Store

After the redesign: new screenshots using `Scripts/compose_screenshots.py`, an updated
description and keywords, and a listing that leads with the widget.

## Order of work (for agents)

0. ~~Design mockups~~. Done and approved in direction. Small changes may still come up.
1. **Widget engine:** the fill-the-frame sizing, headers, today ring and Large labels
   in `Shared/ContributionGridView.swift` and `Shared/StreakWidgetView.swift`.
2. **Looks:** revamp the five built-ins and add Marks (`Shared/WidgetStyle.swift`,
   the `WidgetStyle` enum and its intent options).
3. **Styles screen:** replaces `WidgetStyleGallery.swift`, `RotationView.swift` and
   folds in `CustomStyleEditor.swift`. Includes both bug fixes.
4. **Home and Settings:** rebuild `ContentView.swift` into Home plus a Settings screen.
5. **Widget options:** simplify `WidgetOptionsIntent.swift`.
6. **Copy pass** across the app.
7. **Rename cleanup** (can run in parallel with anything; the local folder move goes last).
8. **App Store** screenshots and listing.

Steps 1 and 2 land before 3 and 4, since the app's previews draw the real widget.
Step 7 is independent. Every step is checked in the simulator against the canvas,
with screenshots, before it's called done. Automate widgets on a scratch simulator,
not the iPhone 17 Pro Max one that holds the user's home screen.
