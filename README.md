# cocoapods-podgenerate 🚀

**CocoaPods 性能加速插件** — 专为 150+ Pod 依赖的大型项目优化 `pod install`。

在使用 CocoaPods 管理 150+ 甚至更多 Pod 依赖的大型项目中，`pod install` **第3步（Generating Pods project）** 和 **第4步（Integrating client project）** 是主要瓶颈。本插件通过多补丁协同工作，显著降低这些步骤的耗时。

---

## 效果

> 测试环境：150 pods · 26源文件+3资源/pod · ObjC+Swift混编 · 6 targets
>
> v0.1.0–v0.1.2: Apple M3 Pro  
> v0.1.6: Apple M3 (对比脚本见 `example/compare.sh`，包含 A/B/C 三方对照)

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

### v0.1.2 新增优化

| 补丁                                 | 优化目标                                         | `pod install` 步骤 |
| ---------------------------------- | -------------------------------------------- |:----------------:|
| `multi_project_generator_patch.rb` | 并行化 PodTargetInstaller（150 pod 同时安装）         | 第3步              |
| `cache_analyzer_patch.rb`          | 并行化 cache key MD5 计算                         | 第3步              |
| `installer_patch.rb` (增强)          | 并行化 configure_schemes                        | 第3步              |
| `project_writer_patch.rb` (增强)     | 并行化 cleanup_projects + recreate_user_schemes | 第3步              |
| `user_integrator_patch.rb` (增强)    | 并行化 xcconfig override 警告                     | 第4步              |
| `profiler.rb` (增强)                 | 子步骤计时分析                                      | 调试               |

### v0.1.x 完整优化列表

| 补丁                                 | 优化目标                                                   | 步骤  |
| ---------------------------------- | ------------------------------------------------------ |:---:|
| `multi_project_generator_patch.rb` | 并行化 PodTargetInstaller                                 | 3   |
| `project_patch.rb`                 | pod_group O(n) → O(1) 哈希缓存                             | 3   |
| `project_writer_patch.rb`          | SHA256 摘要比对 + 并行 cleanup/schemes/save                  | 3   |
| `installer_patch.rb`               | 强制增量模式 + 跳过无变更生成 + 并行 integrate + 并行 configure_schemes | 3   |
| `cache_analyzer_patch.rb`          | 并行 cache key MD5 计算                                    | 3   |
| `analyzer_patch.rb`                | 依赖解析结果缓存                                               | 1   |
| `user_integrator_patch.rb`         | 多 target 并行集成 + 并行保存 + 并行 xcconfig 警告                  | 4   |

---

## 使用方式

### 安装

```bash
gem install cocoapods-podgenerate
```

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
POD_GENERATE_DEBUG=1 pod install
```

输出示例（v0.1.2 新增子步骤计时）：

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
│   └── cocoapods-podgenerate/
│       ├── rb                  # 入口，激活所有补丁
│       ├── command.rb                   # pod podgenerate CLI 命令
│       ├── hooks.rb                     # :pre_install hook
│       ├── patches/
│       │   ├── installer_patch.rb       # 强制增量 + 跳过 + 并行集成 + 并行 schemes
│       │   ├── multi_project_generator_patch.rb  # 并行 PodTargetInstaller (v0.1.2)
│       │   ├── project_patch.rb         # pod_group 哈希缓存
│       │   ├── project_writer_patch.rb  # 增量写入 + 并行 cleanup/schemes/save
│       │   ├── analyzer_patch.rb        # 依赖解析缓存
│       │   ├── cache_analyzer_patch.rb  # 并行 cache key 计算 (v0.1.2)
│       │   └── user_integrator_patch.rb # 多 target 并行集成 + 并行 xcconfig 警告
│       ├── parallel/
│       │   ├── thread_pool.rb           # 线程池封装
│       │   └── batch_processor.rb       # 批处理工具
│       └── benchmark/
│           └── profiler.rb              # 性能分析器（含子步骤计时）
└── spec/                                # 测试（待补充）
```

---

## 测试

项目包含完整的性能测试框架，支持三种方案的横向对比：

| 方案 | 说明 |
|:---:|:----:|
| ExampleA | 本地路径插件 + Podfile `plugin` 声明 |
| ExampleB | 纯原生 CocoaPods（无插件）基准 |
| ExampleC | 生产 gem 插件 + Podfile `plugin` 声明 |

```bash
cd example

# 增强 pod 模板（添加更多源文件和资源）
ruby enhance_pods.rb

# 生成 150 个测试 pod
ruby generate_podfile.rb

# A/B/C 三方对比测试（首次干净安装 + 增量安装 + 性能表格）
bash compare.sh

# 多 target 场景测试（6 个 target）
ruby multi_target_test.rb
```

---

## 兼容性

- **CocoaPods**: >= 1.10.0
- **Ruby**: >= 3.0
- **Platform**: macOS (Xcode 项目集成)
- 不影响 Xcode 编译产物，仅优化 `pod install` 过程

## License

MIT
