---
kind: incident
id: <% tp.date.now("YYYY-MM-DD-HHmmss") %>
title: ""
status: open
trust: draft
module: ""
subsystem: ""
route: ""
symbol: ""
error_signature: ""
error_signature_hash: ""
tags: [incident]
related_files: []
related_tests: []
related_notes: []
failed_attempt_ids: []
last_verified_commit: ""
related_blobs: {}
superseded_by:
stale_candidate: false
owner:
created: <% tp.date.now("YYYY-MM-DD") %>
reviewed:
---

# Summary

One-paragraph description of the issue and why it mattered.

# Evidence

- Trigger:
- Observed behavior:
- Verification target:

# Root cause

Concise, factual cause statement.

# Fix

What changed and why it is the smallest proven fix.

# Failed attempts

- Attempt:
  Reason rejected:

# Verification

- Tests run:
- Build checks:
- Manual validation:

# Links

- Architecture:
- Decision:
- PR / commit:
