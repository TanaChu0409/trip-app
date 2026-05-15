---
name: flutter-skills
description: Flutter app development and maintenance guidance for this repository. Use when Codex needs to build, refactor, debug, review, or test Dart/Flutter code under `app/`, especially widget UI, layout constraints, Riverpod state flow, GoRouter navigation, forms, assets, testing, or platform-specific behavior. Prefer official Flutter documentation and API guidance over blog-style patterns.
---

# Flutter Skills

Use this skill for Flutter work in this repository's `app/` project.

## Repo Entry Points

- Start from `app/pubspec.yaml` to confirm dependencies and project scope.
- Treat `app/lib/` as the application source and `app/test/` as the primary automated test area.
- Expect Flutter with Riverpod, GoRouter, Drift, Supabase, and common mobile plugins already in use.

## Workflow

1. Inspect the current feature area before editing.
Check the nearby screen, store, service, route, and tests so changes match existing project conventions.

2. Map the task to the official guidance.
Open [official guidance](./references/official-guidance.md) and use the most relevant Flutter doc section before changing architecture or UI patterns.

3. Implement in Flutter-native terms.
Reason in widgets, widget trees, constraints, rebuilds, async UI state, and explicit ownership of data.

4. Preserve the repo's existing patterns.
Prefer the current Riverpod, routing, and data-layer conventions unless the task clearly requires a broader refactor.

5. Verify from the `app/` directory.
Prefer `flutter analyze` plus focused tests related to the changed feature before closing the task.

## Working Rules

- Prefer official Flutter docs and API docs over third-party advice.
- Treat UI as widget composition first, not as HTML/CSS translation.
- When layout breaks, debug constraints before introducing extra wrappers.
- Keep state ownership explicit.
If state is app data or shared behavior, keep it in the existing state layer.
If state is only transient widget behavior, local widget state is acceptable.
- Default to the simplest readable widget structure before adding abstractions.
- Prefer cookbook-backed implementations when Flutter already documents the pattern.

## Implementation Heuristics

### UI and Layout

- Start from the widget tree and parent-child relationships.
- Use `Expanded`, `Flexible`, scrolling widgets, and explicit sizing only after reasoning about constraints.
- Keep responsive behavior aligned with documented Flutter adaptive patterns.

### State and Interaction

- Prefer `StatelessWidget` when UI is fully derived from inputs.
- Use local state only for local UI behavior.
- Follow existing Riverpod boundaries for shared or asynchronous state.
- Use built-in interactive widgets first, then `GestureDetector` for custom input handling.

### Navigation, Forms, and Assets

- Keep route and parameter flow explicit and consistent with the existing GoRouter setup.
- Use documented Flutter form validation and text input patterns.
- Update `app/pubspec.yaml` when adding assets, fonts, or packages.

### Testing and Debugging

- Match the test level to the problem: unit, widget, or integration.
- Prefer focused tests near the changed behavior before broad test runs.
- Use Flutter analyzer and official common-error guidance when framework errors appear.

## References

- [Official guidance](./references/official-guidance.md)
