# Code Review Guidelines

Review the project and the proposed changes thoroughly and independently, applying the judgment of a senior software engineer. Passing tests, documentation claims, and earlier reviews, including AI reviews, are inputs to investigate. Verify the behavior yourself.

Trace relevant paths through the source, Git diff, upstream and downstream callers, API contracts, tests, historical design decisions, and real gameplay data. Read enough surrounding code to understand the behavior at normal entry points and across lifecycle boundaries.

## Review dimensions

### 1. Correctness

- Check that the logic solves the underlying problem and preserves existing behavior outside the intended change.
- Inspect conditions, boundary cases, formulas, and unit conversions. Verify assumptions against the contract and observed inputs.
- Check whether fallbacks are appropriate and whether they hide a failure that callers need to see.

### 2. Data integrity

- Verify the authority, reliability, and freshness of each source. Distinguish static, live, derived, and inferred data.
- Preserve the meanings of `nil`, zero, an empty string, an empty table, and a snapshot that has yet to arrive.
- Look for incorrect merge precedence, stale caches, duplicate records, incorrect identity matching, and data contamination.
- Make uncertainty visible when the available data cannot establish a fact.

### 3. State management

- Check for races, out-of-order delivery, and repeated events. Identify who owns each piece of state and where multiple modules maintain it.
- Verify cache invalidation, initialization, teardown, reload, and run transitions. Look for state carried over from an earlier run.
- Exercise delayed, missing, and incomplete snapshots.

### 4. Performance

- Prioritize `OnUpdate`, combat events, nameplates, world markers, effects, damage meters, and ability cooldowns.
- Look for excessive polling, repeated API requests, redundant scans, sorting and rendering, and frequent allocation of temporary tables, strings, Frames, or Textures.
- Check whether hidden or disabled UI modules still do unnecessary work, and whether disabling debug or diagnostics removes unnecessary overhead.
- Look for leaks, unbounded caches or histories, and costs that grow with run duration, enemy count, or event volume.
- Consider caching, event coalescing, incremental updates, and object reuse where appropriate. Use existing profilers and comparable measurements when possible. Preserve data accuracy and UI responsiveness.

### 5. Reliability

- Check handling of unexpected, missing, or malformed API data, along with initialization order and dependency loading.
- Look for silently swallowed errors. Verify recovery after request failure and assess retry and degradation behavior.
- Check whether a failure in one module can affect unrelated features.

### 6. Compatibility

- Check the actual game client and Lua runtime, differences between Reborn and the original game, and existing compatibility fixes.
- Verify locale-sensitive behavior, especially in English and Simplified Chinese, and coexistence with other addons.
- Check for unintended changes to native UI handlers, globals, or HUD elements managed by other addons.
- Exercise the existing module and Game HUD controls in both modes. Verify that disabling the replacement restores native visuals, visibility and interactions independently, including when the replacement cannot render. Check immediate switching where practical and keep diagnostic and history data independent of presentation.
- Preserve compatibility with existing settings, SavedVariables, and historical data. Consider the cost of future upstream synchronization.

### 7. Maintainability

- Check whether the code and names communicate intent and whether functions and control flow remain understandable.
- Look for duplication, dead code, obsolete implementations, unused compatibility branches, magic numbers, implicit dependencies, and reimplementations of existing helpers.
- Prefer a simpler, reliable implementation when it meets the same requirements. Avoid refactors motivated solely by line count or aesthetics.

### 8. Architecture and design

- Check whether modules have clear responsibilities and whether new features fit the existing architecture.
- Look for inappropriate coupling, cycles, responsibility leakage, and modules that accumulate too many responsibilities.
- Check the separation of data acquisition, processing, state ownership, and UI presentation. Identify duplicate parsing or state maintenance across modules.
- Assess the value and maintenance cost of added frameworks, abstraction layers, or modules. Prefer local improvements and require a clear benefit for any broad rewrite.
- Compare the change with existing renderers, settings, formatters, positioning, localization, caches and providers. Extend them where they meet the requirement and preserve the established design.

### 9. Test quality

- Assess what tests prove beyond their number and pass rate. Look for assertions on observable behavior and mocks that reflect the actual game API.
- Check coverage of boundaries, failure paths, and lifecycle changes. Confirm regression tests would have failed before the fix.
- Investigate assertions changed to accept incorrect behavior. Flag redundant, low-value, or implementation-bound tests.
- Use real session captures and replay fixtures when they can verify behavior. Distinguish mocked tests, recorded-data replay, and in-game validation.

### 10. Security and licensing

- Check how untrusted inputs and external data are handled. Look for unnecessary dynamic code execution and unbounded imports or storage.
- Check logs, diagnostics, and build artifacts for sensitive data.
- Verify the provenance and redistribution terms of third-party code, assets, metadata, and game data. Check compliance with the project and third-party licenses.

### 11. User experience

- Check that displayed information is accurate, timely, and easy to understand. Look for stale or misleading values, flicker, layout shifts, and erratic cooldown changes.
- Check whether the change preserves established UI style, settings, and interaction patterns. Consider visual load and the actual value of new features to players.

### 12. Documentation

- Verify that documentation matches the code and makes API contracts and data sources explicit.
- Check that important design decisions have a rationale and that known limitations, unverified behavior, and technical debt are recorded accurately.
- Prefer comments that explain the reasons behind decisions. Check that a new developer or Codex session can continue the work using the project documentation.

## Common pitfalls in AI-generated changes

- APIs, fields, or events that do not exist, or speculation presented as verified fact.
- Symptom fixes that leave the underlying defect in place, or broad defensive checks that obscure a logic error.
- General-purpose machinery for a narrow need, scope expansion, duplicated helpers, or obsolete code left after a refactor.
- Fallbacks that supply plausible but incorrect data.
- Test changes that accommodate a broken implementation.
- Completion claims made before sufficient verification, or documentation that misstates actual behavior.

## AZ Reborn review checklist

- Check Reborn API usage against official documentation, accessible native implementations, and real gameplay observations.
- Verify handling of replaced AZS global tables, delayed updates, and invalidated snapshots.
- Verify identity matching for abilities, jewelry, bosses, elites, and guardians.
- Check whether ability upgrade history misattributes a global stat change to a specific ability upgrade.
- Keep jewelry base effects, actual equipped effects, and character-wide totals distinct.
- Verify racial cooldown synchronization and Rift, Time, and Endless boss states and timers.
- Verify Curse and Hex recognition, deduplication, and lifecycle handling.
- Check abilities, gear, and history for cross-run contamination.
- Inspect the hot paths for nameplates, world markers, ability effects, and the Meter.
- Preserve existing Reborn compatibility fixes. Verify any assumption carried over from the original game.
- Keep features within the project's purpose. SurvivorUI Reborn improves the accuracy, completeness, reliability, and performance of existing SurvivorUI features in Reborn. Evaluate proposed additions against that purpose.

## Reporting findings

For each finding, provide the following:

- A finding ID, severity, and confidence level.
- File paths, function names, and exact line numbers.
- A description, root cause, and concrete triggering scenario.
- Supporting source code, API documentation, or runtime evidence.
- Impact on users, functionality, performance, or maintenance cost.
- The smallest practical fix, possible regressions, and tests or validation needed.

| Severity | Meaning |
| --- | --- |
| P0 | Blocking crash, severe data error, or unavailable core functionality. |
| P1 | Clear functional defect, important regression, or significant performance or reliability issue. |
| P2 | Edge-case defect, localized maintainability issue, or performance improvement with a practical benefit. |
| P3 | Minor, non-blocking readability, naming, or style issue. |
| Observation | Unverified risk, design question, or future optimization opportunity. |

Distinguish confirmed findings, well-supported findings awaiting reproduction, potential risks needing more evidence, optional optimizations, and implementations that are sound as written. Report the reproduction environment and limits of each claim. Only report issues supported by the evidence.

End the report with:

1. An overall code quality assessment.
2. Findings in severity order.
3. A recommended fix order.
4. Areas to leave unchanged and why.
5. Checks still requiring in-game validation.
6. An assessment of test quality and coverage.
7. A conclusion on merge and release readiness.
8. Issues that must be resolved before release.

Preserve technical terminology, API names, and code identifiers in the report.

## Review principles

- Prioritize correctness, empirical evidence, simplicity, reliability, and user value.
- Address root causes before adding defensive checks. Keep fixes local where practical.
- Weigh likelihood, severity, implementation cost and regression risk against verified native guarantees. Prioritize practical gameplay failures. Document acceptable limits and justify additional polling, state machines or compatibility layers with a demonstrated need. A finding can be resolved with evidence when a code change adds little value.
- Base performance recommendations on measurements whenever possible.
- Avoid unnecessary churn. Treat personal style preferences as preferences and time-box review and refactoring.
- During an independent review, leave production code unchanged. Existing tests, temporary verification scripts, and runtime data analysis are appropriate.
