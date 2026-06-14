# Hakanai-AI/.github

Org-defaults repo: shared CI (reusable workflows + composite actions) and
org-level community-health files. Tracked in **ops#287** (consolidate the
duplicated per-plugin workflows that drift — the ops#286 root cause).

## Composite actions

### `dist-conformance` (`.github/actions/dist-conformance`)
Asserts a plugin's published dist is complete and its `plugin.json` metadata
matches source before the dist is committed. Guards the ops#286 drift class
(missing `launcher.mjs`, un-synced `displayName`/metadata).

Use as a step in the `sync-dist` job, **after** the copy and **before** the dist
commit, so a failure blocks a bad dist from shipping:

```yaml
- name: Conformance check (block incomplete/stale dist)
  uses: Hakanai-AI/.github/.github/actions/dist-conformance@v1
  with:
    dist_dir: dist
    source_plugin_json: .claude-plugin/plugin.json
    expected_version: ${{ steps.version.outputs.version }}
```

Pin to a tag (`@v1`), never `@main` — these are org-wide blast radius.

## Access

Private repo; Actions access set to **organization** so private plugin repos can
consume these actions/workflows.

## Roadmap (ops#287)

Phase 1 (this): `dist-conformance` action + wire the 7 binary plugins.
Phase 2: consolidate `notify-webhook`, `test-go`, `release-goreleaser`,
`auto-approve`, `release-please`, `ci` into reusable workflows — one at a time,
parity-checked.
