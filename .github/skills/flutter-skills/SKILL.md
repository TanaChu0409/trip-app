---
name: flutter-skills
description: 'Use when working on Flutter features or bugs with guidance grounded in the official Flutter docs. Covers app setup, widget-based UI, layout constraints, stateful vs stateless widgets, navigation, forms, assets, testing, debugging, adaptive design, and cookbook-based implementation patterns.'
argument-hint: 'Describe the Flutter feature, screen, refactor, bug, or test you want help with.'
user-invocable: true
---

# Flutter Skills

Use this skill when the task involves Flutter application development and the response should follow the official guidance from `docs.flutter.dev` and the Flutter API docs.

## When To Use

- Create or extend a Flutter app or package.
- Build UI by composing widgets.
- Fix layout, overflow, alignment, or responsiveness issues.
- Choose between `StatelessWidget`, `StatefulWidget`, and lifted state.
- Add navigation, forms, assets, gestures, animations, or platform-specific behavior.
- Write or improve unit, widget, and integration tests.
- Debug common Flutter framework issues.

## Core Rules

1. Prefer official Flutter documentation and API docs over blog-style patterns.
2. Treat Flutter UI as widget composition first, not as HTML/CSS translation.
3. Respect Flutter layout rules, especially constraints and parent-child sizing behavior.
4. Default to simple, readable widgets before introducing extra abstraction.
5. Keep state ownership explicit.
If the state is user or app data, prefer moving it upward.
If the state is purely local UI behavior, the widget may own it.
6. Prefer cookbook or sample-backed solutions when the official docs already cover the problem.

## Procedure

1. Identify the task type.
Decide whether the request is mainly about setup, UI layout, interactivity, data flow, navigation, testing, debugging, platform integration, or architecture.

2. Inspect the Flutter project structure.
Check `pubspec.yaml`, `lib/`, platform folders, and any existing routing, state, or design-system conventions before editing code.

3. Choose the official guidance path.
Use [official guidance](./references/official-guidance.md) to map the task to the right Flutter documentation area before proposing code.

4. Implement in Flutter-native terms.
Describe or write code in terms of widgets, widget trees, constraints, state ownership, asynchronous UI, and platform adaptation.

5. Verify with Flutter tooling where possible.
Prefer `flutter analyze`, focused tests, and the official testing/debugging guidance before closing the task.

## Implementation Heuristics

### UI and layout

- Start from the widget tree.
- Use `Row`, `Column`, `ListView`, `GridView`, `Stack`, `Card`, and `ListTile` only when they match the documented layout behavior.
- When overflow appears, reason about constraints first, then use `Expanded`, `Flexible`, scrolling widgets, or explicit sizing as appropriate.
- For adaptive UI, prefer documented Flutter patterns instead of duplicating separate app codepaths too early.

### State and interactivity

- Use `StatelessWidget` when UI is derived entirely from inputs.
- Use `StatefulWidget` when local mutable UI state is required.
- If unsure who owns state, start with parent-managed state as recommended by the docs.
- Use built-in interactive widgets first, then `GestureDetector` for custom gestures.

### Navigation, forms, and assets

- Follow official cookbook patterns for routes, passing data, form validation, text fields, and deep links.
- Update `pubspec.yaml` when adding assets, fonts, or packages.

### Testing and debugging

- Match the test level to the problem: unit, widget, or integration.
- Use Flutter's testing and debugging docs for common framework errors, build modes, and debugger workflows.

## References

- [Official guidance](./references/official-guidance.md)
