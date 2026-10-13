# SDK intake

This directory holds the vendor SDK. Its contents are **gitignored**.

## Placement (State A → B)

Download the multi-part SDK and place the extracted folder here:

```text
sdk/vendor/tspi_1m_linux_kernel6.1_sdk_20260807/
```

The folder should contain the vendor `extract_sdk.sh` and the SDK tarballs
(packaging details vary by release; scripts detect, they do not assume).

Then run:

```bash
make sdk-check     # detect state + print what is present
make sdk-extract   # idempotent: run the vendor extractor
make sdk-sync      # idempotent: local .repo sync -> sdk/work/tspi-linux-sdk
```

## Working tree (State C → D)

The extracted/synced tree lives at:

```text
sdk/work/tspi-linux-sdk/
```

Override names with `SDK_VENDOR_DIRNAME` / `SDK_WORK_DIRNAME` in
`config/versions.env` if the vendor uses different directory names.

## States

| State | Meaning |
|-------|---------|
| A | SDK absent — only repository scaffolding is possible |
| B | downloaded multi-part folder present (`extract_sdk.sh`) |
| C | extracted tree with `.repo/` but incomplete worktree |
| D | fully synced worktree (kernel tree present) |
| E | baseline vendor build artifacts exist |

`scripts/sdk/inspect.sh` detects and reports the current state.
