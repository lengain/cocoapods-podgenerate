# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build gem from source
cd PodGenerate && gem build cocoapods-podgenerate.gemspec

# Install built gem locally
gem install cocoapods-podgenerate-0.1.6.gem

# Publish to RubyGems
gem push cocoapods-podgenerate-0.1.6.gem

# Run performance comparison test (A/B/C)
cd example && bash compare.sh

# Generate test pods (150 pods, 26 source files + 3 resources each)
cd example && ruby enhance_pods.rb && ruby generate_podfile.rb

# Run multi-target test (6 targets)
cd example && ruby multi_target_test.rb

# Run a specific Example project with the plugin
cd example/ExampleA && bundle exec pod install
cd example/ExampleB && pod install              # no plugin
cd example/ExampleC && bundle exec pod install

# Manual debug run (verbose)
cd example/ExampleA && bundle exec pod install --verbose
COCOAPODS_PODGENERATE_DEBUG=1 bundle exec pod install
```

## Architecture

This is a **CocoaPods plugin** that accelerates `pod install` for 150+ pod projects. All optimizations are implemented as monkey-patches (`Module#prepend`) applied at plugin load time.

### Activation Flow

```
cocoapods_plugin.rb          # CLAide plugin discovery entry point
    └── cocoapods-podgenerate.rb  # Main entry: require patches + auto-activate
          ├── patches/*.rb        # 7 monkey-patches applied via prepend
          ├── hooks.rb            # :pre_install hook registration (fallback activation)
          └── benchmark/profiler.rb  # Optional sub-step timing analysis
```

**Two activation paths:**
1. **TracePoint auto-activation** (primary): When `Pod::HooksManager` is defined, immediately calls `Pod::PodGenerate.activate`. Otherwise uses a TracePoint on `:class` events to detect HooksManager loading, with 500-event safety guard.
2. **`:pre_install` hook** (fallback): Registered via `hooks.rb` as a CocoaPods hook, fires during install flow if TracePoint missed.

### Patch Layers (applied in order)

| Patch | Optimizes | CocoaPods Step |
|---|---|---|
| `installer_patch.rb` | Force incremental mode, skip no-change project gen, parallel integrate + schemes | 3/4 |
| `project_patch.rb` | Hash cache for pod_group lookup O(n)→O(1) | 3 |
| `project_writer_patch.rb` | SHA256 delta check, parallel save/cleanup/schemes | 3 |
| `analyzer_patch.rb` | Resolution result cache (skip Molinillo resolver) | 1 |
| `user_integrator_patch.rb` | Parallel xcconfig override warnings, multi-target parallel integration | 4 |
| `multi_project_generator_patch.rb` | Parallel PodTargetInstaller (one thread per pod target) | 3 |
| `cache_analyzer_patch.rb` | Parallel cache key MD5 computation | 3 |

### Key Design Choices

- **`Module#prepend` over `alias_method`** — prepend adds a module to the ancestor chain, making `super` work naturally. All patches use this pattern.
- **Idempotent activation** — `@activated` guard in `PodGenerate.activate` prevents double-prepend (which would corrupt the ancestor chain).
- **Incremental optimization** — Plugins force `incremental_installation` + `generate_multiple_pod_projects` CocoaPods options. The key insight is that for no-change pod installs, the entire project generation can be skipped.
- **Resource-aware parallelism** — Thread pool size is `max(2, min(nproc-1, 16))`. Pool timeout is 120s.
- **Atomic cache writes** — Resolution cache files use write-to-temp + rename pattern to prevent corruption.
- **Self-containment** — Unlike typical CocoaPods plugins that only register hooks, this plugin directly monkey-patches internal classes, so it must be compatible with specific CocoaPods versions.

### Compatibility Notes

- **CocoaPods >= 1.10.0** (v0.1.6+ verified against 1.16.2)
- `ResolverSpecification` in CocoaPods 1.16.2 wraps `Specification` with no direct `#version` — patches must use `respond_to?` guards before accessing spec properties.
- Cached resolution result objects may be `ResolverSpecification` or raw `Specification` depending on CocoaPods version; patches handle both.

## Project Structure

```
PodGenerate/
├── lib/
│   ├── cocoapods_plugin.rb                     # CLAide discovery hook
│   └── cocoapods-podgenerate/
│       ├── cocoapods-podgenerate.rb            # Entry point + auto-activation
│       ├── command.rb                          # CLI: pod podgenerate
│       ├── hooks.rb                            # pre_install hook
│       ├── patches/                            # 7 monkey-patches
│       └── benchmark/
│           └── profiler.rb                     # Timing instrumentation
├── example/
│   ├── compare.sh                              # A/B/C performance test
│   ├── enhance_pods.rb / generate_podfile.rb   # Test pod generation
│   ├── multi_target_test.rb                    # 6-target test
│   └── ExampleA/ ExampleB/ ExampleC/           # Test projects
├── cocoapods-podgenerate.gemspec               # v0.1.6
└── README.md                                   # Full docs + benchmarks
```

## Versioning & Release

1. Bump `spec.version` in `cocoapods-podgenerate.gemspec`
2. Build: `gem build cocoapods-podgenerate.gemspec`
3. Commit, tag (`git tag v0.X.Y`), push to GitHub
4. Publish: `gem push cocoapods-podgenerate-0.X.Y`
5. Create GitHub Release with changelog notes
6. Update benchmark in `README.md` after re-running `example/compare.sh`
