# Feature: StampIt grouping for ContinousOperation
## Status
Implemented and committed.
## Commit
6854390
## Summary
The existing rule only matched titles containing the exact marker "[ContinuousOperation]" and did case-sensitive token checks, so an incoming issue titled "[ContinousOperation]" with lower-case "stampit" would not group. The rule now accepts the misspelled marker and performs case-insensitive matching in stack frames and stacktrace text so those issues group correctly.
## Changes
- backend/kahu/src/rules/continuous-operation-stampit-stacktrace-rule.ts: accept both title markers and use case-insensitive token matching.
- backend/data/develop-requests/mmjdoh1s87lh.md: implementation report.
## Build Status
- backend/kahu: npm run build
## Testing Notes
Trigger the rule by ingesting a Sentry issue titled "[ContinousOperation]" that includes "stampit" (any case) in stack frames or stacktrace text; it should group under ContinuousOperationStampItStacktrace.
