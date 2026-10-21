---
name: integrations-guardrails
description: Guardrails and known pitfalls for code integrating SharePoint (CSOM), DocuSign, AWS S3 and Piano Analytics in .NET APIs. Load before reading, debugging, reviewing or modifying code that touches these integrations.
compatibility: opencode
---
# External integrations guardrails

## General
- Never change authentication flows, certificates, token acquisition, scopes or credentials handling without explicit approval. Stop and ask.
- Many production bugs in these integrations come from environment differences (configuration, permissions, fonts, tokens, network), not from code. Check configuration per environment before changing code.
- Every call takes a CancellationToken and has explicit timeout handling.
- Never log tokens, document contents, signer names or emails.
- Tests mock the port (Application interface), never the vendor SDK directly in handler tests.

## SharePoint / CSOM
- `ClientContext` is IDisposable: always `using`.
- CSOM batches requests: nothing is sent before `ExecuteQueryAsync()`. Count round trips; avoid one `ExecuteQueryAsync` per item in loops.
- `Load(...)` only the properties you need.
- Large files: use the chunked upload (StartUpload / ContinueUpload / FinishUpload). Keep the upload id and offsets consistent; a failure in the middle must cancel or clean up the upload session.
- A file's name is `File.Name` (`FileLeafRef` on its list item, `ListItem.Name`), always with its extension. `DisplayName` is that name without its extension by default, and `Title` is a separate metadata column (empty, typed by someone, filled by a flow or promoted from the properties of an Office document): neither is a file name. A wrapper or a migration that maps a "title" or a display name where the old code read `Name` loses the extension.
- Resolving files or folders by URL can be non-recursive: a lookup that works for files at the root can fail for files in subfolders. Check how the path is resolved before blaming the upload logic.
- Server-relative URLs: build them from validated segments, encode special characters, reject `..`.
- Shared NuGet packages wrapping CSOM may contain the bug: confirm whether the faulty code is in the repository or in the package before patching. After a version change of such a package, compare its query building (CAML, `Load` / `Include`) between the two versions first.
- Throttling (HTTP 429/503): respect `Retry-After`, exponential backoff, never tight retry loops.
- Uploads do not create missing folders: create the folder tree explicitly before a batch upload.
- Lists above 5,000 items (list view threshold): queries must filter on indexed columns and page (`RowLimit` + `ListItemCollectionPosition`); a list that crosses the threshold makes old queries slow or failing without any code change.
- Managed metadata (taxonomy) fields: write a `TaxonomyFieldValue` with `TermGuid`, `Label` and `WssId = -1`.
- Certificate (app-only) authentication that works locally but fails once deployed (`invalid_client`, wrong identity): compare the client id, tenant id and certificate thumbprint of each environment's configuration and the App Registration the certificate is uploaded to; it is configuration or an Entra admin action, not code.

## DocuSign
- Validate PDFs before sending (magic number `%PDF`, size, not encrypted unless expected, page count if relevant). DocuSign rejects some valid-looking PDFs.
- Envelope ids are technical identifiers; treat them as tracking data when sent to analytics (pseudonymize with SHA-256).
- Rendering differences between environments (fonts, signature styles) usually come from account or brand configuration, not code. Compare account settings first.
- Tokens: JWT grant / OAuth handling is sensitive. Token errors on specific APIs (e.g. evidence/certificate APIs) often come from missing scopes or consent, not code.
- Webhooks (Connect): verify HMAC signatures; handlers must be idempotent (DocuSign retries).
- Batch processing: respect API rate limits; process with bounded parallelism.

## AWS S3
- Never build object keys from raw user input: whitelist characters, reject `..` and leading `/`.
- Stream uploads and downloads; do not load whole files in memory.
- Presigned URLs: shortest reasonable expiry, correct HTTP method, never logged in full.
- Credentials come from the environment/role chain, never from code or committed config.
- Handle `NoSuchKey` explicitly (404 in API), not as a generic 500.
- AWS SDK for .NET v4: collections of responses are `null` when empty (`response.S3Objects ?? []`) and value types are nullable (`response.IsTruncated == true`). Shared packages written for v3 can crash on an empty prefix.
- `ListObjectsV2` with `Delimiter = "/"` returns only the first level: objects in sub-prefixes are in `CommonPrefixes`. An empty `S3Objects` without exception means the request worked and matched nothing (prefix, case, bucket, objects already moved), never a credentials problem (that is a 403).

## Piano Analytics
- Tracking is subject to CNIL/GDPR consent rules: no tracking call for users without valid consent unless the event is in the exempted category approved by the organization.
- No personal data in events. Pseudonymize identifiers (SHA-256) when an identifier is needed.
- Tracking must never block or fail the business operation: fire-and-forget with error logging, or an outbox, according to existing code.
