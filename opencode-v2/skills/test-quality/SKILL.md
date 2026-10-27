---
name: test-quality
description: Judges whether .NET or front-end tests really prove what they claim - assertions that can fail for the right reason, exact expected values, error and denial paths, boundaries, no false confidence from tests that only run lines - with a severity per finding and the exact fix. Load before reporting tests you wrote (test-guardian, coder), and when reviewing the tests of a branch or of a merge request (checker). Complements test-lint.sh, which finds the mechanical cases.
compatibility: opencode
---
# Test quality: tests that would catch the bug

`sh ~/.config/opencode/scripts/test-lint.sh` finds what a file shows on its own (no assertion, a focused or skipped test, a real clock, a sleep, an assertion that cannot fail). This skill is the judgment it cannot make: would these tests fail if the code under them were wrong? A green test that cannot fail gives false confidence; a line covered by a test that asserts nothing about it is not protected (a safety net at 80 % of its lines can be such a net).

## The question for each test
Name one realistic wrong version of the code (a boundary moved by one, a guard removed, a constant changed, a field not set, the wrong exception) and check that an assertion of the test fails on it. When none would, the test is weak. When you cannot name a wrong version that would pass, the test is fine: say so, never invent a finding.

## Blocking: false confidence
- No assertion on what the behavior decides: the only check is « no exception », `Assert.NotNull(result)` alone, or a mock verification of a call that the code makes whatever its input.
- A test that calls the public methods to cover lines (`var result = sut.Method(x);`) and asserts nothing about `result`: one finding for the class, every test listed.
- A self-referential or always-true assertion: `Assert.Equal(dto.Name, dto.Name)`, an expected value computed with the code under test (`Assert.Equal(sut.Compute(x), sut.Compute(x))`), `Assert.True(true)`. A serialize/deserialize round trip with a non-trivial input is legitimate.
- An async assertion not awaited (`Assert.ThrowsAsync` without `await`, `expect(promise).resolves` without `await` or `return`, an `async void` test): it passes silently.
- An exception swallowed by the test (`try { act(); } catch { }`) or asserted only in a `catch` (`catch (Exception e) { Assert.Fail(e.Message); }`): use `Assert.Throws<T>` / `ThrowsAsync<T>`, `Should().Throw<T>()`, `expect(fn).toThrow(...)`.
- A transformation tested with an input that is already in the expected form (trimming `"abc"`, encoding a string without a character to encode, a sanitizer fed a safe value): a code that does nothing passes. The input must need the transformation, and the expected value is written in the test.

## Major: blind spots
- The expected value is not exact: `Assert.NotEqual(old, result)`, `Assert.True(total > 0)`, `Contains` where the whole value is known. Write the exact value, derived by hand from the input (`Assert.Equal(118.80m, invoice.Total)` for 99.00 + 20 %).
- One allowed result does not prove the denial: a permission, a validation or a guard is tested on both sides (accepted AND rejected, the role that may AND the role that may not). A security fix always has its rejected input.
- Boundaries: for a guard `value >= limit`, the tests at `limit - 1`, `limit` and `limit + 1`; for `<= 0`, zero AND a negative value; empty, null and whitespace are three cases when the code treats them apart.
- An exception asserted by its base type (`Assert.Throws<Exception>`, `toThrow()` with no type or message): assert the exact type, and the message or the parameter name when the contract says it.
- One returned field asserted, the others the behavior sets left unchecked (a mapping, a created entity, a response body): assert each field the behavior decides, or the whole object against an expected one written in the test.
- A state change or a side effect not checked: the method saves, sends or publishes, and the test asserts only its return value. Read the state back (a new `DbContext`, the fake repository, the request the fake handler received).
- Shared mutable state between tests (a static list, a static fake, a database not reset), or a test that needs another one to run first: it passes alone and fails in the suite, or the reverse.
- Over-mocking: more set-up than test, a mock of a type the test owns, call counts or call order asserted where the outcome would say the same: the test breaks when the code is refactored without a bug.

## Minor
- A name that does not say the behavior (`Test1`, `ShouldWork`); several behaviors in one test of 30 lines and more; three near-identical tests that differ by one value (a `[Theory]`/`[TestCase]`/`[DataRow]` or `it.each`; separate boundary tests are not duplicates); a value whose origin is not obvious with neither a name nor a comment; an assertion message that repeats the assertion; `Console.WriteLine` left in a test.

## Before you report your own tests
1. For each behavior of your mission (each acceptance criterion, each branch of the method of the problem, each public method of the net): the test that covers it, and the wrong version of the code that this test would catch. A behavior without one: write the test, or say why in the report.
2. Every blocking and major point above: fixed in your tests.
3. Then `test-lint.sh <your test files>` (its blocking and major findings fixed), then the proof the procedure asks for (green twice, red twice).
Never change an existing test of the repository to make it stronger in a run that did not ask for it: say it in the report (« Points d'attention »).

## Review (checker, /review)
- Report with the severity above, `file:line`, the realistic wrong version of the code that would pass, and the exact replacement (the assertion with its expected value). One finding per systemic issue, its tests listed. Count what you reviewed (« 14 tests relus »).
- Tests that are good: say it first, in one line, with what they protect (« les bornes 0, 1 et 100 du calcul et le refus d'un rôle Lecteur »). Never raise a severity to have something to say.
- Not findings: table-driven tests, explicit set-up in each test instead of a shared one, short clear tests, a `Thread.Sleep` in an integration test that measures a real delay on purpose (say it), a boolean assertion on a meaningful property (`Assert.True(result.IsValid)`).

Adapted for the pack from the skills test-anti-patterns, assertion-quality and test-gap-analysis of github.com/dotnet/skills (MIT License, Copyright (c) .NET Foundation and Contributors): NOTICE.md.
