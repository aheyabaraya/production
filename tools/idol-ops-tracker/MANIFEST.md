# File Manifest

| Path | Responsibility |
|---|---|
| `start.py` | Dependency-free local launcher |
| `idol_ops_tracker/server.py` | Loopback HTTP server, static UI, whitelisted action endpoint |
| `idol_ops_tracker/store.py` | Validated atomic JSON store with tool-root write restriction |
| `idol_ops_tracker/actions.py` | Allowed mutations and locked-baseline protection |
| `idol_ops_tracker/validation.py` | Schema, enum, date, reference, and weight validation |
| `idol_ops_tracker/derive.py` | Strict completion, schedule, attention, decision, and AI read-models |
| `idol_ops_tracker/operations.py` | MV family/main/sub read-model, MV/CF deadline, and registered worker projection; run/harness read-only |
| `idol_ops_tracker/sources.py` | Metadata-only path and read-only Git probes |
| `idol_ops_tracker/paths.py` | Canonical roots and repo path-escape guard |
| `idol_ops_tracker/constants.py` | Status vocabulary and writable-field allowlists |
| `data/tracker.json` | Single tracker-owned state file and initial IDOL-focused portfolio |
| `web/index.html` | Dashboard structure and dialogs |
| `web/styles.css` | Responsive local UI styling |
| `web/workers.css` | Full MV worker browser styling |
| `web/app.js` | Rendering and approved tracker actions |
| `web/compact.html` | Peek/Compact/Expanded macOS panel structure |
| `web/compact.css` | Three-size floating-panel and run-family styling |
| `web/compact.js` | Read-only family/run switcher, deadline, and worker summary renderer |
| `web/favicon.svg` | Local dashboard icon |
| `macos/Sources/IDOLOpsWidget/main.m` | Native AppKit `NSPanel`, persisted three-size control, menu bar control, and local server lifecycle |
| `macos/Resources/Info.plist` | Menu-bar app bundle metadata; no Dock icon |
| `macos/build-app.sh` | Local Objective-C build, bundle assembly, and ad-hoc signing |
| `dist/IDOL Ops Control.app` | Ignored generated app bundle |
| `tests/test_tracker.py` | Completion, evidence, isolation, store, and local API tests |
