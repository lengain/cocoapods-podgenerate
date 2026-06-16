# cocoapods-podgenerate 🚀

**CocoaPods 性能加速插件** — 专为 150+ Pod 依赖的大型项目优化 `pod install`。

在使用 CocoaPods 管理 150+ 甚至更多 Pod 依赖的大型项目中，`pod install` **第3步（Generating Pods project）** 和 **第4步（Integrating client project）** 是主要瓶颈。本插件通过多补丁协同工作，显著降低这些步骤的耗时。

---

## 效果

> 测试环境：150 pods · 26源文件+3资源/pod · ObjC+Swift混编 · 6 targets
>
> v0.1.0–v0.1.2: Apple M3 Pro  
> v0.1.6: Apple M3（对比脚本见 `example/compare.sh`，包含 A/B/C 三方对照）

| 版本         | 场景       | 耗时        | 相比上个版本提升     | 相比无插件提升  |
|:----------:| -------- |:---------:|:------------:|:--------:|
| v0.1.0     | 干净安装     | 4.88s     | —            | —        |
| v0.1.0     | 增量安装     | 4.22s     | —            | —        |
| v0.1.1     | 干净安装     | 5.61s     | —            | —        |
| v0.1.1     | 增量安装     | 1.52s     | **+64%**     | **+68%** |
| v0.1.2     | 干净安装     | 5.18s     | **+7.7%** 🚀 | —        |
| v0.1.2     | 增量安装     | 1.14s     | **+25%** 🚀  | **+75%** |
| **v0.1.6** | **干净安装** | **7.47s** | — †           | **-2.3%** |
| **v0.1.6** | **增量安装** | **1.67s** | — †           | **+76.8%** 🚀 |

> † v0.1.6 测试环境为 Apple M3（与之前 M3 Pro 不同），干净安装的绝对耗时不可直接比较。但**增量安装相对无插件的加速比（+76.8%）** 是同一环境下的横向对比结果，可反映真实收益。

### 增量安装对比明细（v0.1.6）

| 方案 | 插件来源 | Podfile plugin | 首次安装 | 增量安装 | 相对无插件加速 |
|:---:|:------:|:-------------:|:-------:|:-------:|:----------:|
| A | 本地路径 | ✅ | 7.18s | 1.70s | **+76.4%** |
| B | 无 | ❌ | 7.30s | 7.21s | 基准 |
| C | 生产 gem 0.1.6 | ✅ | 7.47s | 1.67s | **+76.8%** 🚀 |

---

## 功能

### 补丁总览

| 补丁                                 | 优化目标                                                   | 步骤  | 引入版本 |
| ---------------------------------- | ------------------------------------------------------ |:---:|:------:|
| `installer_patch.rb`               | 强制增量模式 + 跳过无变更生成 + 并行 integrate + 并行 configure_schemes | 3/4 | v0.1.1 |
| `project_patch.rb`                 | pod_group O(n) → O(1) 哈希缓存                             | 3   | v0.1.1 |
| `project_writer_patch.rb`          | SHA256 摘要比对 + 并行 cleanup/schemes/save                  | 3   | v0.1.1 |
| `analyzer_patch.rb`                | 依赖解析结果缓存                                               | 1   | v0.1.1 |
| `user_integrator_patch.rb`         | 多 target 并行集成 + 并行保存 + 并行 xcconfig 警告                  | 4   | v0.1.1 |
| `multi_project_generator_patch.rb` | 并行化 PodTargetInstaller（150 pod 同时安装）                  | 3   | v0.1.2 |
| `cache_analyzer_patch.rb`          | 并行 cache key MD5 计算                                     | 3   | v0.1.2 |
| `profiler.rb`                      | 子步骤计时分析（调试）                                          | 调试  | v0.1.2 |

### 版本历史

| 版本 | 变更 |
|:---:|:----|
| v0.1.0 | 初始版本 |
| v0.1.1 | 增量安装从 4.22s → 1.52s（+64%）；跳过无变更项目生成；并行集成 |
| v0.1.2 | 并行化 PodTargetInstaller + cache key + schemes；子步骤计时分析 |
| v0.1.3 | Bug fixes from audit |
| v0.1.4 | Comprehensive bug fix（包含 CocoaPods 1.16.2 `ResolverSpecification` 兼容修复） |
| v0.1.5 | （内部版本） |
| v0.1.6 | 正式发布 CocoaPods 1.16.2 兼容修复；增加 A/B/C 三方对比测试框架 |
| **v0.1.7** | **修复 3 个并发 bug：`pool.post` rescue 绑定错误 + 线程异常裸传播 + `analyzer_patch` 缩进** |
| **v0.1.8** | **Flutter 兼容性：`resolve_cross_project_dependencies` + 跳过路径 `@pods_project=nil` 修复** |
| **v0.1.9** | **Flutter 兼容性加强：跨项目依赖解析扩展到全部 `generated_projects`** |
| **v0.1.10** | **代码审查改进：调试日志 + 统一 Flutter 测试脚本** |

---

## 使用方式

### 安装

```bash
gem install cocoapods-podgenerate
```

要求 Ruby >= 3.0、CocoaPods >= 1.10.0。

### 在 Podfile 中启用

```ruby
plugin 'cocoapods-podgenerate'
```

### 执行

```bash
pod install
```

插件会自动激活并输出性能报告。

### 调试模式

```bash
COCOAPODS_PODGENERATE_DEBUG=1 pod install
```

输出示例：

```
[cocoapods-podgenerate] Performance Report:
    Resolve dependencies              0.35s (2.5%)
    Download dependencies             0.01s (0.0%)
      Create and save projects        4.34s (30.8%)
    Generate Pods project             4.38s (31.1%)
    Integrate user project            0.02s (0.1%)
    Write lockfiles                   0.04s (0.3%)
  Total install!                      4.96s (35.2%)
```

---

## 项目结构

```
PodGenerate/
├── cocoapods-podgenerate.gemspec       # Gem 规范
├── Gemfile
├── lib/
│   ├── cocoapods_plugin.rb             # CLAide 插件发现入口
│   └── cocoapods-podgenerate/
│       ├── cocoapods-podgenerate.rb    # 入口，激活所有补丁
│       ├── command.rb                  # pod podgenerate CLI 命令
│       ├── hooks.rb                    # :pre_install hook
│       ├── patches/
│       │   ├── installer_patch.rb      # 强制增量 + 跳过 + 并行集成 + 并行 schemes
│       │   ├── multi_project_generator_patch.rb  # 并行 PodTargetInstaller (v0.1.2)
│       │   ├── project_patch.rb        # pod_group 哈希缓存
│       │   ├── project_writer_patch.rb # 增量写入 + 并行 cleanup/schemes/save
│       │   ├── analyzer_patch.rb       # 依赖解析缓存
│       │   ├── cache_analyzer_patch.rb # 并行 cache key 计算 (v0.1.2)
│       │   └── user_integrator_patch.rb# 多 target 并行集成 + 并行 xcconfig 警告
│       ├── parallel/
│       │   ├── thread_pool.rb          # 线程池封装
│       │   └── batch_processor.rb      # 批处理工具
│       └── benchmark/
│           └── profiler.rb             # 性能分析器（含子步骤计时）
└── example/                            # 性能测试框架
    ├── compare.sh                      # A/B/C 三方对比（首轮 + 增量）
    ├── enhance_pods.rb                 # 增强 pod 模板
    ├── generate_podfile.rb             # 生成 150 个测试 pod
    ├── multi_target_test.rb            # 多 target 场景测试
    ├── complex_podfile_test.rb         # 复杂 Podfile 兼容性测试（abstract_target + inherit! + test_spec）
    ├── run_complex_test.rb             # 复杂 Podfile 测试运行器
    ├── run_flutter_test.rb             # Flutter 兼容性测试（内联 + load podhelper.rb 双模式）
    ├── run_flutter_integration_test.rb # Flutter Add-to-App 集成测试
    ├── run_with_plugin.rb              # 手动加载插件运行（调试用）
    ├── Gemfile                         # ExampleA/C 的 Gemfile
    ├── ExampleA/                       # 本地路径插件工程
    ├── ExampleB/                       # 纯原生 CocoaPods 基准工程
    └── ExampleC/                       # 生产 gem 插件工程
```

---

## 测试

项目包含完整的性能测试框架，支持三种方案的横向对比：

| 方案 | 说明 | 运行方式 |
|:---:|:----|:--------:|
| ExampleA | 本地路径插件 + Podfile `plugin` 声明 | `bundle exec pod install` |
| ExampleB | 纯原生 CocoaPods（无插件）基准 | `pod install` |
| ExampleC | 生产 gem 插件 + Podfile `plugin` 声明 | `bundle exec pod install` |

```bash
cd example

# 增强 pod 模板（添加更多源文件和资源）
ruby enhance_pods.rb

# 生成 150 个测试 pod
ruby generate_podfile.rb

# A/B/C 三方对比测试（首次干净安装 + 增量安装 + 性能表格）
bash compare.sh

# 手动调试：在指定 Example 目录运行
cd ExampleC && bundle exec pod install --verbose

# 多 target 场景测试（6 个 target）
ruby ../multi_target_test.rb

# 复杂 Podfile 兼容性测试（abstract_target + inherit! + test_spec 等）
ruby ../complex_podfile_test.rb

# Flutter 兼容性测试（内联 depends_on_flutter / load podhelper.rb）
ruby ../run_flutter_test.rb          # Mode A: 内联
ruby ../run_flutter_test.rb --b     # Mode B: load podhelper.rb

# Flutter Add-to-App 完整集成测试
ruby ../run_flutter_integration_test.rb
```

> **注意**：`compare.sh` 会自动管理系统 gem 的安装/卸载，确保 ExampleB 不被插件影响。运行过程中会临时卸载 cocoapods-podgenerate gem，运行完 B 后重新安装。

---

## 兼容性

- **CocoaPods**: >= 1.10.0（v0.1.6+ 已验证 CocoaPods 1.16.2）
- **Ruby**: >= 3.0
- **Platform**: macOS（Xcode 项目集成）
- **Flutter**: v0.1.8+ 完全兼容 Flutter Add-to-App `load podhelper.rb` 集成模式
- 不影响 Xcode 编译产物，仅优化 `pod install` 过程

### Flutter 集成注意

本插件强制启用 `generate_multiple_pod_projects`，这会导致 Xcodeproj 无法解析跨项目的 `PBXTargetDependency` 引用（`dependency.target` 返回 `nil`）。Flutter 的 `depends_on_flutter` 递归遍历依赖链时会因此崩溃。

**v0.1.8+** 新增 `resolve_cross_project_dependencies` 机制，在 post-install hooks 执行前将所有子项目的 target 引用挂载到 `PBXTargetDependency.target` 上，确保 `depends_on_flutter` 递归遍历不会遇到 `nil`。如果你在 Flutter 项目中使用此插件，请确保版本 >= v0.1.9。

## License

MIT
