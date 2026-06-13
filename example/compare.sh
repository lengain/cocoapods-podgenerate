#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  CocoaPods 与 PodGenerate 插件 性能对比测试脚本
#  150 pods · ExampleA/B/C 三方对比
#
#  设计要点:
#    CocoaPods 的 PluginManager 会自动加载所有已安装 gem 中的
#    cocoapods_plugin.rb，不受 Podfile 中 plugin 指令影响。
#    为确保 ExampleB 是纯净的无插件基准，脚本在运行 B 之前
#    临时卸载 cocoapods-podgenerate gem，运行完再重装。
#
#  测试流程:
#    1. 卸载系统 cocoapods-podgenerate gem
#    2. 清理所有 Pods，运行 ExampleB（纯净无插件）
#    3. 重装 cocoapods-podgenerate gem（从本地源码构建 0.1.5）
#    4. 清理后运行 ExampleA（本地路径插件）和 ExampleC（生产 gem）
#    5. 增量阶段：不清除，重新运行 A/B/C
#    6. 输出对比表格
#
#  环境说明:
#    ExampleA: 有 Gemfile（本地路径 path:）+ 有 Podfile plugin
#    ExampleB: 无 Gemfile + 无 Podfile plugin（纯 CocoaPods 基准）
#    ExampleC: 有 Gemfile（生产 gem）+ 有 Podfile plugin
# ═══════════════════════════════════════════════════════════════════════

set -o pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
A_DIR="$BASE_DIR/ExampleA"
B_DIR="$BASE_DIR/ExampleB"
C_DIR="$BASE_DIR/ExampleC"
PODGEN_DIR="$(cd "$BASE_DIR/.." && pwd)"

# ── 配置 ──
LABEL0="ExampleA (本地路径插件)"
LABEL1="ExampleB (原生CocoaPods)"
LABEL2="ExampleC (生产gem插件)"

CMD0="cd '$A_DIR' && bundle exec pod install 2>&1"
CMD1="cd '$B_DIR' && pod install 2>&1"
CMD2="cd '$C_DIR' && bundle exec pod install 2>&1"

get_label() { case "$1" in 0) echo "$LABEL0" ;; 1) echo "$LABEL1" ;; 2) echo "$LABEL2" ;; esac; }
get_suf()   { case "$1" in 0) echo a ;; 1) echo b ;; 2) echo c ;; esac; }
get_dir()   { case "$1" in 0) echo "$A_DIR" ;; 1) echo "$B_DIR" ;; 2) echo "$C_DIR" ;; esac; }
get_cmd()   { case "$1" in 0) echo "$CMD0" ;; 1) echo "$CMD1" ;; 2) echo "$CMD2" ;; esac; }

read_val() { if [ -f "$1" ]; then tr -d '\n' < "$1"; else echo -n "?"; fi; }

fmt_time() {
  local v; v=$(read_val "$1")
  if [ "$v" = "?" ]; then printf "   ?    "
  else printf "%7ss" "$v"; fi
}

calc() { python3 -c "print($1)" 2>/dev/null || echo "?"; }

clean_all() {
  rm -rf "$A_DIR/Pods" "$A_DIR/Podfile.lock" \
         "$B_DIR/Pods" "$B_DIR/Podfile.lock" \
         "$C_DIR/Pods" "$C_DIR/Podfile.lock"
}
clean_ac() {
  # 只清理 A 和 C，保留 B 的 Pods（供增量阶段使用）
  rm -rf "$A_DIR/Pods" "$A_DIR/Podfile.lock" \
         "$C_DIR/Pods" "$C_DIR/Podfile.lock"
}

# ── gem 管理 ──

uninstall_podgen_gem() {
  local installed
  installed=$(gem list cocoapods-podgenerate 2>/dev/null | grep -E '^cocoapods-podgenerate' | sed 's/.*(\(.*\))/\1/' | sed 's/,.*//')
  if [ -n "$installed" ] && [ "$installed" != " " ]; then
    echo "  卸载系统 gem cocoapods-podgenerate (当前: $installed)..."
    gem uninstall cocoapods-podgenerate -a -x --force 2>/dev/null || true
    echo "     OK"
  else
    echo "  系统 gem cocoapods-podgenerate 已卸载"
  fi
}

install_podgen_gem() {
  local gemfile="$PODGEN_DIR/cocoapods-podgenerate-0.1.5.gem"
  if [ ! -f "$gemfile" ]; then
    echo "  构建 cocoapods-podgenerate 0.1.5 gem..."
    cd "$PODGEN_DIR"
    gem build cocoapods-podgenerate.gemspec -o "$(basename "$gemfile")" 2>/dev/null
    cd "$BASE_DIR"
  fi
  echo "  安装 cocoapods-podgenerate 0.1.5 gem..."
  gem install "$gemfile" 2>/dev/null | tail -1
  echo "     OK"
}

# ── 运行 + 解析 ──

run_one() {
  local idx="$1" phase="$2"
  local suf; suf=$(get_suf "$idx")
  local dir; dir=$(get_dir "$idx")
  local cmd; cmd=$(get_cmd "$idx")
  local label; label=$(get_label "$idx")
  local out_file="/tmp/compare_${suf}_p${phase}.txt"
  local time_file="/tmp/compare_${suf}_p${phase}_time.txt"
  local uc; uc=$(echo "$suf" | tr abc ABC)

  printf "  [%s] %s ... " "$uc" "$label"

  cd "$dir"
  /usr/bin/time bash -c "$cmd" >"$out_file" 2>"$time_file" || true

  local time_line
  time_line=$(tail -1 "$time_file" 2>/dev/null)
  local real_t user_t sys_t
  real_t=$(echo "$time_line" | awk '{print $1}')
  user_t=$(echo "$time_line" | awk '{print $3}')
  sys_t=$(echo "$time_line" | awk '{print $5}')

  local plugin_count pod_count done_line
  plugin_count=$(grep -c "\[cocoapods-podgenerate\]" "$out_file" 2>/dev/null || true)
  pod_count=$(grep -c "Installing PodGen_" "$out_file" 2>/dev/null || true)
  done_line=$(grep -o "Pod installation complete[^!]*" "$out_file" 2>/dev/null | head -1 || echo "")

  echo "$real_t"   > "/tmp/compare_val_${suf}_p${phase}_real"
  echo "$user_t"   > "/tmp/compare_val_${suf}_p${phase}_user"
  echo "$sys_t"    > "/tmp/compare_val_${suf}_p${phase}_sys"
  echo "$pod_count"   > "/tmp/compare_val_${suf}_p${phase}_pods"
  echo "$plugin_count" > "/tmp/compare_val_${suf}_p${phase}_plugin"
  echo "$done_line"    > "/tmp/compare_val_${suf}_p${phase}_done"

  printf "done  (real %ss)\n" "$real_t"
}

# ── 表格工具 ──
sep5() { printf "+%s+%s+%s+%s+%s+\n" "----------------------" "----------" "----------" "----------" "------------"; }
sep4() { printf "+%s+%s+%s+%s+\n" "----------------------" "------------" "------------" "------------"; }
sep3() { printf "+%s+%s+%s+\n" "----------------------" "--------------" "--------------"; }
print_row() { printf "| %-20s | %s | %s | %s | %s |\n" "$1" "$2" "$3" "$4" "$5"; }

label_by_suf() { case "$1" in a) echo "$LABEL0" ;; b) echo "$LABEL1" ;; c) echo "$LABEL2" ;; esac; }

# ══════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        CocoaPods x PodGenerate 性能对比测试                 ║"
echo "║        150 pods - 三方案例对比                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  测试方案:"
echo "    [A] $LABEL0"
echo "    [B] $LABEL1"
echo "    [C] $LABEL2"
echo ""
echo "  注: ExampleB 运行前会临时卸载系统 cocoapods-podgenerate gem"
echo "      以确保 B 是纯净无插件的原生 CocoaPods 基准。"
echo ""

# ══════════════════════════════════════════════════════
# 第一阶段：首次运行（干净安装）
# ══════════════════════════════════════════════════════

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  第一阶段：首次运行（干净安装）                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 1) 卸载系统 gem，运行 B（纯净无插件）
echo "━━━ 卸载系统 gem + 运行 ExampleB..."
clean_all
uninstall_podgen_gem
echo ""
run_one 1 1
echo ""

# 2) 重装 gem，运行 A 和 C（只清理 A/C，保留 B 的 Pods 供增量阶段）
echo "━━━ 重装 gem + 运行 ExampleA / ExampleC..."
install_podgen_gem
clean_ac
echo ""
run_one 0 1
run_one 2 1

echo ""
echo "  OK 第一阶段完成"
echo ""

# ══════════════════════════════════════════════════════
# 第二阶段：增量运行（无变化）
# ══════════════════════════════════════════════════════

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  第二阶段：增量运行（无变化）                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 增量运行：B 仍然无 gem，A/C 有 gem
run_one 1 2
run_one 0 2
run_one 2 2

echo ""
echo "  OK 第二阶段完成"
echo ""

# ══════════════════════════════════════════════════════
# 输出对比表格
# ══════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 测 试 结 果 对 比                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── 第一阶段 ──
echo "━━━ 第一阶段：首次运行（干净安装） ━━━"
echo ""
sep5
print_row "方案" "real" "user" "sys" "安装pod数"
sep5
for suf in a b c; do
  lbl=$(label_by_suf "$suf")
  r=$(fmt_time "/tmp/compare_val_${suf}_p1_real")
  u=$(fmt_time "/tmp/compare_val_${suf}_p1_user")
  sy=$(fmt_time "/tmp/compare_val_${suf}_p1_sys")
  p=$(read_val "/tmp/compare_val_${suf}_p1_pods")
  print_row "$lbl" "$r" "$u" "$sy" "$p"
done
sep5

rb=$(read_val "/tmp/compare_val_b_p1_real")
ra=$(read_val "/tmp/compare_val_a_p1_real")
rc=$(read_val "/tmp/compare_val_c_p1_real")
if [ "$rb" != "?" ] && [ "$ra" != "?" ] && [ "$rc" != "?" ]; then
  save_a=$(calc "round(($rb - $ra) / $rb * 100, 1)")
  save_c=$(calc "round(($rb - $rc) / $rb * 100, 1)")
  echo ""
  echo "  相对原生 CocoaPods（B）的加速:"
  echo "    [A] $LABEL0: ${save_a}%"
  echo "    [C] $LABEL2: ${save_c}%"
fi
echo ""

# ── 第二阶段 ──
echo "━━━ 第二阶段：增量运行（无变化） ━━━"
echo ""
sep5
print_row "方案" "real" "user" "sys" "新增pod数"
sep5
for suf in a b c; do
  lbl=$(label_by_suf "$suf")
  r=$(fmt_time "/tmp/compare_val_${suf}_p2_real")
  u=$(fmt_time "/tmp/compare_val_${suf}_p2_user")
  sy=$(fmt_time "/tmp/compare_val_${suf}_p2_sys")
  p=$(read_val "/tmp/compare_val_${suf}_p2_pods")
  print_row "$lbl" "$r" "$u" "$sy" "$p"
done
sep5

rb2=$(read_val "/tmp/compare_val_b_p2_real")
ra2=$(read_val "/tmp/compare_val_a_p2_real")
rc2=$(read_val "/tmp/compare_val_c_p2_real")
if [ "$rb2" != "?" ] && [ "$ra2" != "?" ] && [ "$rc2" != "?" ]; then
  save_a2=$(calc "round(($rb2 - $ra2) / $rb2 * 100, 1)")
  save_c2=$(calc "round(($rb2 - $rc2) / $rb2 * 100, 1)")
  echo ""
  echo "  相对原生 CocoaPods（B）的加速:"
  echo "    [A] $LABEL0: ${save_a2}%"
  echo "    [C] $LABEL2: ${save_c2}%"
fi
echo ""

# ── 首次 vs 增量 自身加速比 ──
echo "━━━ 首次 vs 增量 自身加速比 ━━━"
echo ""
sep4
printf "| %-20s | %-10s | %-10s | %-10s |\n" "方案" "首次 real" "增量 real" "加速比"
sep4
for suf in a b c; do
  lbl=$(label_by_suf "$suf")
  r1=$(read_val "/tmp/compare_val_${suf}_p1_real")
  r2=$(read_val "/tmp/compare_val_${suf}_p2_real")
  if [ "$r1" != "?" ] && [ "$r2" != "?" ]; then
    ratio=$(calc "round(($r1 - $r2) / $r1 * 100, 1)")
    printf "| %-20s | %10s | %10s | %10s%% |\n" "$lbl" "${r1}s" "${r2}s" "$ratio"
  fi
done
sep4
echo ""

# ── 插件活动情况 ──
echo "━━━ 插件激活状态 ━━━"
echo ""
sep3
printf "| %-20s | %-12s | %-12s |\n" "方案" "首次插件消息" "增量插件消息"
sep3
for suf in a b c; do
  lbl=$(label_by_suf "$suf")
  p1=$(read_val "/tmp/compare_val_${suf}_p1_plugin")
  p2=$(read_val "/tmp/compare_val_${suf}_p2_plugin")
  printf "| %-20s | %12s | %12s |\n" "$lbl" "${p1}条" "${p2}条"
done
sep3

echo ""
echo "═══ 测试完成 ═══"
echo ""
echo "详细输出文件:"
echo "  /tmp/compare_{a,b,c}_p{1,2}.txt     (完整 pod install 输出)"
echo "  /tmp/compare_val_{a,b,c}_p{1,2}_*   (解析后的指标)"
echo ""
