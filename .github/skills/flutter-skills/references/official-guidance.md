# Official Flutter Guidance

This reference summarizes the official Flutter documentation areas that are most useful during coding tasks. Use the linked documents as the primary source of truth.

## Primary Sources

- Flutter docs home: https://docs.flutter.dev/
- Flutter API docs: https://api.flutter.dev/
- Learning path: https://docs.flutter.dev/learn/pathway
- Learning resources index: https://docs.flutter.dev/reference/learning-resources

## Setup and project creation

- Install and environment setup: https://docs.flutter.dev/install/quick
- Create a new app: https://docs.flutter.dev/reference/create-new-app
- Choose platform targets and verify toolchain before code changes.

## Widget-first UI

- Widget catalog: https://docs.flutter.dev/ui/widgets
- Layout overview: https://docs.flutter.dev/ui/layout
- Layout constraints: https://docs.flutter.dev/ui/layout/constraints

Guidance:

- Build UIs by composing widgets.
- Think in parent-child widget relationships.
- When layout breaks, inspect constraints before changing many widgets.

## Interactivity and state

- Interactivity overview: https://docs.flutter.dev/ui/interactivity
- Gestures: https://docs.flutter.dev/ui/interactivity/gestures

Guidance:

- Prefer `StatelessWidget` unless the UI needs mutable local state.
- For mutable UI, use `StatefulWidget` plus `State`.
- If state affects broader app behavior, lift it to the parent or state layer.
- Use built-in controls first. Use `GestureDetector` for custom input behavior.

## Navigation, forms, and common tasks

- Cookbook index: https://docs.flutter.dev/cookbook
- Navigation basics: https://docs.flutter.dev/cookbook/navigation/navigation-basics
- Named routes: https://docs.flutter.dev/cookbook/navigation/named-routes
- Forms and validation: https://docs.flutter.dev/cookbook/forms/validation
- Text input: https://docs.flutter.dev/cookbook/forms/text-input
- Assets and images: https://docs.flutter.dev/ui/assets/assets-and-images

Guidance:

- Prefer cookbook-backed implementations for common tasks.
- Keep route handling and data passing explicit.
- Update `pubspec.yaml` for assets, fonts, and packages.

## Architecture and data flow

- App architecture guide: https://docs.flutter.dev/app-architecture
- Result pattern: https://docs.flutter.dev/app-architecture/design-patterns/result
- Offline-first pattern: https://docs.flutter.dev/app-architecture/design-patterns/offline-first
- Key-value data pattern: https://docs.flutter.dev/app-architecture/design-patterns/key-value-data
- SQL pattern: https://docs.flutter.dev/app-architecture/design-patterns/sql

Guidance:

- Follow the official architecture guidance before inventing a project structure.
- Keep UI, state, and data boundaries explicit.
- Reuse documented design patterns when adding persistence, error handling, or offline support.

## Testing and debugging

- Testing and debugging hub: https://docs.flutter.dev/testing
- Testing overview: https://docs.flutter.dev/testing/overview
- Integration tests: https://docs.flutter.dev/testing/integration-tests
- Debugging: https://docs.flutter.dev/testing/debugging
- Common errors: https://docs.flutter.dev/testing/common-errors
- Build modes: https://docs.flutter.dev/testing/build-modes

Guidance:

- Use unit tests for pure logic.
- Use widget tests for UI behavior and rendering.
- Use integration tests for end-to-end flows.
- Use debug/profile/release modes intentionally.

## Platform and adaptive design

- Platform integration overview: https://docs.flutter.dev/platform-integration
- Adaptive and responsive design: https://docs.flutter.dev/ui/adaptive-responsive
- Material widgets: https://docs.flutter.dev/ui/widgets/material
- Cupertino widgets: https://docs.flutter.dev/ui/widgets/cupertino

Guidance:

- Choose Material, Cupertino, or adaptive components based on the product requirements.
- Keep shared business logic reusable across platforms.

## Working style for Copilot

- Prefer official docs-backed code over speculative patterns.
- When multiple approaches are possible, choose the one most directly supported by Flutter docs.
- When debugging layout or state issues, explain the issue in Flutter terms: widget tree, constraints, rebuilds, and state ownership.