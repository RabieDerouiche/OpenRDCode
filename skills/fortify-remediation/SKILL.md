---
name: fortify-remediation
description: Remediation patterns for common Fortify SAST categories in C#/.NET (modern, Blazor and legacy) and front-end TypeScript/JavaScript (log forging, path manipulation, SSRF, privacy violation, header manipulation, security headers, open redirect, injection, XSS, weak crypto, insecure randomness, SSL validation, hardcoded secrets, required value types, unreleased resources) and how to judge false positives. Load before triaging or fixing a Fortify issue.
compatibility: opencode
---
# Fortify remediation patterns for .NET

## General rules
- Follow the data flow from source (user input, HTTP header, file, external API) to sink (log, path, SQL, header, redirect). Fix at the sink or validate at the entry, never in the middle at random.
- Smallest change that removes the vulnerability. No refactoring.
- Never "fix" by suppressing: no pragma, no attribute, no rewriting the code just to hide it from the scanner.
- Add a test with a malicious input proving the fix.
- False positive = the value provably never comes from an untrusted source, or is already validated/encoded before the sink. Then the code stays as is and the developer marks it "Not an Issue" in SSC with a one-sentence justification. Typical case: Heap Inspection on constant strings such as OAuth grant type names (`client_credentials`): no secret is held in memory.

## Log Forging
Cause: untrusted data written to logs can inject fake lines (CR/LF).
- Use structured logging with message templates: `logger.LogWarning("Invalid file {FileName}", fileName)`.
- If the scanner still flags it or the sink is a plain-text log, sanitize: `value?.Replace("\r", string.Empty).Replace("\n", string.Empty)`.
- Prefer a single helper used everywhere (e.g. a `LogSanitizer.Sanitize` method) if the repository already has one.

## Privacy Violation / Sensitive data in logs
- Never log tokens, passwords, API keys, full emails, names, signer identities, document content.
- Log technical identifiers instead. If an identifier is itself personal or tracking data (e.g. sent to an analytics tool), pseudonymize it with SHA-256 (with a secret salt if the existing code uses one).

## Path Manipulation
- Never build a path directly from user input.
- Keep only the file name: `Path.GetFileName(input)`.
- If a sub-path is allowed: `var full = Path.GetFullPath(Path.Combine(baseDir, input));` then check `full.StartsWith(Path.GetFullPath(baseDir) + Path.DirectorySeparatorChar, StringComparison.Ordinal)`; otherwise reject.
- Same logic for SharePoint server-relative URLs and S3 keys built from input: whitelist characters, reject `..`.
- Route parameters (Blazor `[Parameter]`, MVC, minimal APIs): Fortify does not credit route constraints such as `{id:guid}` on a `string` parameter. Type the parameter (`Guid`, `int`) so that the value cannot carry a path.

## Server-Side Request Forgery (SSRF)
- Input that ends up in the URL of an outbound call (`HttpClient.GetAsync`, an SDK endpoint): build the URL from a base address in configuration plus validated segments (`Uri.EscapeDataString`, typed ids). Never take a scheme, a host or an absolute URL from input; when the host can vary, check it against an allowlist from configuration.

## Header Manipulation / Cookie Security
- Reject or strip CR/LF in any value written to a header.
- Cookies: `HttpOnly = true`, `Secure = true`, explicit `SameSite`.

## Open Redirect
- Only redirect to local URLs (`Url.IsLocalUrl(returnUrl)`) or to a whitelist of absolute URLs from configuration.

## SQL / Command Injection
- Parameterized queries only (`SqlParameter`, EF Core `FromSqlInterpolated`, Dapper parameters). Never `FromSqlRaw` with concatenation.
- Never pass user input to `Process.Start` arguments without strict whitelisting.

## Cross-Site Scripting (API returning HTML or reflected values)
- Return JSON with the proper content type. If HTML is produced, encode with `HtmlEncoder.Default.Encode`.
- Blazor: `MarkupString` renders raw HTML. Never use it on content from users, templates or external systems without the sanitizer the repository already uses; otherwise render it as text.

## Missing security headers (X-Content-Type-Options, X-Frame-Options, Content-Security-Policy...)
- On Kestrel (containers, Kubernetes) a `web.config` entry does nothing: add the headers in a middleware early in the pipeline, or with the framework's helper when there is one (ABP: `UseAbpSecurityHeaders()`). Check them on a running instance with `curl -I`, not only in the next scan.

## Model validation: `[Required]` on a non-nullable value type
- A missing `int`, `Guid`, `bool`, `DateTime` or enum binds to its default value and passes `[Required]`. Make the property nullable (`Guid?`), keep `[Required]` (or the validator rule), and read `.Value` after validation.

## Weak Cryptographic Hash / Weak Encryption
- Replace MD5/SHA1 used for security with SHA-256 (`SHA256.HashData`). If the hash is only a non-security checksum, it is a candidate false positive: justify it.
- Encryption: AES-GCM or the platform's Data Protection API. No ECB, no hardcoded IV.

## Insecure Randomness
- Tokens, ids, passwords, nonces: `RandomNumberGenerator.GetBytes` / `RandomNumberGenerator.GetInt32`. `Random` only for non-security uses (then justify).

## Insecure SSL / Certificate validation
- Remove `ServerCertificateCustomValidationCallback = (_, _, _, _) => true` and equivalent. If an internal CA is needed, trust that CA explicitly, never all certificates.

## Password Management: Hardcoded password / Password in configuration
- Move secrets out of code and committed appsettings: environment variables, secret store, or the platform's secret manager. Keep a placeholder in appsettings.
- Never commit the real value in the fix, even in tests.

## Unreleased Resource / Denial of Service
- Wrap `IDisposable` in `using` / `await using` (streams, `HttpResponseMessage`, CSOM `ClientContext`).
- Regex on user input: pass a timeout (`new Regex(pattern, options, TimeSpan.FromMilliseconds(200))`) or use `RegexOptions.NonBacktracking`.
- Uploads: limit size before reading the stream.

## Poor Error Handling
- Empty catch or `catch (Exception)` that swallows: log and rethrow, or handle a specific exception type.
- Do not return exception messages or stack traces to API clients.

## Mass Assignment / Overposting
- Bind requests to dedicated request records, never to domain entities.

## Legacy .NET Framework (WebForms, MVC 5)
- Keep `ValidateRequest`, `EnableViewStateMac` and anti-forgery tokens enabled; never disable them to make a scan or a feature pass.
- Encode output: `HttpUtility.HtmlEncode` / `<%: %>` in WebForms, `@` (not `Html.Raw`) in Razor.
- Session and forms authentication cookies: `requireSSL="true"` and `httpOnlyCookies="true"` in web.config.
- Do not upgrade the target framework or add packages unsupported by it as part of a security fix: fix the code with what the framework offers.

## Front-end (TypeScript / JavaScript)
- DOM XSS: never put untrusted data in `innerHTML`, `outerHTML`, `document.write`, `dangerouslySetInnerHTML`, or Angular `bypassSecurityTrust*`. Use text binding (`textContent`, `{{ }}`, JSX text) or the framework sanitizer.
- Open redirect: only navigate to relative routes or to a whitelist of origins from configuration.
- `postMessage`: always check `event.origin` against an allowed list; never use `*` as target origin with sensitive data.
- Tokens: prefer HttpOnly cookies managed by the backend; do not add new tokens to localStorage / sessionStorage.
- `eval`, `new Function`, `setTimeout` with a string: remove, replace with direct code.
- Dependency findings: upgrade the vulnerable package to the fixed version (`npm audit` lists it); do not ignore the finding without a justification.

