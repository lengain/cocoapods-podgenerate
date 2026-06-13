# cocoapods-podgenerate 🚀

**CocoaPods 性能加速插件** — 专为 150+ Pod 依赖的大型项目优化 `pod install`。

在使用 CocoaPods 管理 150+ 甚至更多 Pod 依赖的大型项目中，`pod install` **第3步（Generating Pods project）** 和 **第4步（Integrating client project）** 是主要瓶颈。本插件通过多补丁协同工作，显著降低这些步骤的耗时。

---

## 效果

> 测试环境：150 pods · 26源文件+3资源/pod · ObjC+Swift混编 · 6 targets · Apple M3 Pro

| 场景          | 无插件       | 带插件       | 节省        | 提升         |
| ----------- | --------- | --------- | --------- |:----------:|
| 干净安装（首次）    | 4.91s     | 4.88s     | 0.02s     | 持平         |
| **增量安装 🔄** | **4.84s** | **4.22s** | **0.62s** | **+12.9%** |

插件在**增量安装**场景下效果最显著——这是日常开发中最频繁的操作（修改代码后重新 `pod install`）。

---

## 功能

| 补丁                         | 优化目标                          | `pod install` 步骤 |
| -------------------------- | ----------------------------- |:----------------:|
| `project_patch.rb`         | pod_group O(n) → O(1) 哈希缓存    | 第3步              |
| `project_writer_patch.rb`  | SHA256 摘要比对，跳过未变项目的 sort+save | 第3步              |
| `installer_patch.rb`       | 并行化 PodTargetIntegrator 集成    | 第3步              |
| `analyzer_patch.rb`        | 依赖解析结果缓存，跳过 Molinillo         | 第1步              |
| `user_integrator_patch.rb` | 多 target 并行集成 + 并行保存项目        | 第4步              |

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

输出示例：

```
[cocoapods-podgenerate] Performance Report:
    Resolve dependencies              0.33s (3.9%)
    Download dependencies             0.01s (0.1%)
    Generate Pods project             3.79s (44.6%)
    Integrate user project            0.02s (0.2%)
  Total install!                      4.36s (51.2%)
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
│       │   ├── installer_patch.rb       # Pod 目标安装优化
│       │   ├── project_patch.rb         # pod_group 哈希缓存
│       │   ├── project_writer_patch.rb  # 增量项目保存
│       │   ├── analyzer_patch.rb        # 依赖解析缓存
│       │   └── user_integrator_patch.rb # 多 target 并行集成
│       ├── parallel/
│       │   ├── thread_pool.rb           # 线程池封装
│       │   └── batch_processor.rb       # 批处理工具
│       └── benchmark/
│           └── profiler.rb              # 性能分析器
└── spec/                                # 测试（待补充）
```

---

## 测试

项目包含完整的性能测试框架：

```bash
cd example

# 增强 pod 模板（添加更多源文件和资源）
ruby enhance_pods.rb

# 生成 150 个测试 pod
ruby generate_podfile.rb

# A/B 对比测试（ExampleA 带插件 vs ExampleB 无插件）
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
