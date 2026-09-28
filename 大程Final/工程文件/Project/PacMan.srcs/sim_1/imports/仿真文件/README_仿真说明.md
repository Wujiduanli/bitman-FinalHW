# 仿真文件说明

## 文件夹内容

| 文件名 | 对应被测模块 | 仿真类型 |
|--------|-------------|----------|
| `tb_clk_div.v` | `clk_div` | 模块级功能仿真 (defparam 加速) |
| `tb_map_memory.v` | `map_memory` | 模块级功能仿真 |
| `tb_game_logic_fsm.v` | `game_logic_fsm` | 模块级功能仿真 |
| `tb_vga_display.v` | `vga_display` | 模块级功能仿真 |
| `tb_ps2_keyboard.v` | `ps2_keyboard` | 模块级功能仿真 |
| `tb_seg_display.v` | `seg_display` | 模块级功能仿真 |
| `tb_buzzer_ctrl.v` | `buzzer_ctrl` | 模块级功能仿真 |
| `tb_top_pacman.v` | `top_pacman` | 顶层集成仿真 |

## 运行方式

### Vivado 仿真 (推荐)

1. 打开 Vivado 工程
2. 添加源文件：`src/*.v` (所有设计源文件)
3. 添加仿真文件：`仿真文件/tb_*.v`
4. 注意：`clk_div.v` 中的 MMCME2_BASE 为 Xilinx 原语，Vivado 仿真器原生支持。`tb_clk_div.v` 使用 `defparam` 加速 game_clk/scan_clk 分频参数
5. 设置顶层仿真模块 (如 `tb_game_logic_fsm`)
6. Run Simulation → Run Behavioral Simulation

### 命令行仿真 (Icarus Verilog / ModelSim)

```bash
# 示例: 编译并运行 tb_map_memory
iverilog -o sim_map src/map_memory.v 仿真文件/tb_map_memory.v
vvp sim_map
```

注意：`clk_div.v` 使用 MMCM 原语，在 Icarus 中不可用。请在 Vivado xsim 中运行仿真。
`map_memory.v` 使用 `initial` 块初始化，在大多数仿真器中均可正常工作。

## 各模块仿真要点

### 1. clk_div — 时钟管理模块

**仿真关注信号：**
- `vga_clk`: 周期约 39.84ns (25.098MHz)
- `game_clk`: 单周期脉冲 (~10Hz，仿真中加速)
- `scan_clk`: 50% 占空比方波 (~1kHz)
- `locked`: MMCM 锁定指示

**波形分析要点：**
- `game_clk` 为**单周期脉冲**而非连续方波 — 每个 Tick 只触发一次 FSM 状态转换
- `scan_clk` 为 50% 占空比连续方波 — 直接驱动七段码动态扫描状态机
- `vga_clk` 由 MMCM 生成，与 100MHz 系统时钟独立

**上板现象对应：**
- VGA 显示正常 = MMCM 锁定成功 (25.098MHz 偏差 0.31%，显示器可接受)
- 游戏速度正常 = game_clk 约 10Hz (每 100ms 移动一次)
- 数码管无闪烁 = scan_clk 约 1kHz (每位刷新率 250Hz)

---

### 2. map_memory — 地图存储模块

**仿真关注信号：**
- `addr_a` / `map_type_a` / `pellet_a`：Port A (VGA) 组合逻辑读
- `addr_b` / `map_type_b` / `pellet_b`：Port B 组合逻辑读
- `pellet_we` / `pellet_din`：同步写入
- `pellet_init` / `init_active` / `init_addr`：初始化状态机
- `pellet_total`：豆子总数

**波形分析要点：**
- **组合逻辑读取**：`addr_a` 变化后，`map_type_a` 和 `pellet_a` 在同一仿真时间步立即更新（无时钟延迟）
- **同步写入**：`pellet_we=1` 时，`pellet_ram[addr_b]` 在**下一个时钟上升沿**才更新（寄存器写延迟）
- **双端口独立**：Port A 和 Port B 可同时读取不同地址，数据互不干扰
- **初始化状态机**：`pellet_init` 触发后，`init_addr` 从 0 逐周期递增到 767（共 768 周期 ≈ 7.68μs），`init_active` 完成时自动清除
- **写入优先级**：同一周期 `pellet_we` 和 `pellet_init` 冲突时，`pellet_we` 优先（防止刚吃的豆子被恢复）

**上板现象对应：**
- 迷宫墙壁显示正确 = ROM 每个 32×24 网格的 2-bit 数据正确初始化
- 豆子显示/消失正确 = RAM 同步写入时序正确，组合逻辑读无延迟
- 重新开始后豆子恢复 = `pellet_init` 状态机正常工作 (768 周期后全部恢复)

---

### 3. game_logic_fsm — 游戏逻辑状态机

**仿真关注信号：**
- `game_state`：主状态 (IDLE/PLAY/GAMEOVER/WIN)
- `play_sub`：PLAY 子状态 (P_IDLE→P_CALC→P_CHECK→P_PELLET→P_GHOST→P_IDLE)
- `pac_x` / `pac_y`：吃豆人坐标
- `ghost_x` / `ghost_y`：幽灵坐标
- `pac_dir` / `ghost_dir`：方向寄存器
- `map_addr`：地图查询地址 (在子状态间切换)
- `pellet_we` / `pellet_waddr`：吃豆写信号
- `score`：分数
- `sound_event`：音效事件类型

**波形分析要点：**
- **主状态跳转**：`start_game` 脉冲 → IDLE→PLAY, 碰撞 → PLAY→GAMEOVER, 吃光→WIN
- **子状态流水线**：每个 `game_tick` 触发一次 P_IDLE→P_CALC→P_CHECK→P_PELLET→P_GHOST→P_IDLE 循环
- **P_IDLE**：采样方向键，锁存 `pac_dir`
- **P_CALC**：组合逻辑计算下一步坐标，发送 `map_addr` 查询目标格
- **P_CHECK**：读取 `map_type` 判断是否墙壁，锁存 `pellet_latch`（关键：避免时序竞争）
- **P_PELLET**：若 `pac_moved && pellet_latch`，触发 `pellet_we=1`，`score+1`，`sound_event=EAT`
- **P_GHOST**：更新幽灵坐标，实体碰撞检测，Win 条件判定
- **碰撞检测**：双重检查 — ROM 地图类型检查 + 坐标范围边界检查
- **坐标边界保护**：`pac_nx`/`pac_ny` 组合逻辑中 `x==0?x:x-1` 防止下溢

**上板现象对应：**
- 键盘控制角色移动流畅 = 10Hz Tick + 方向持续电平采样正确
- 吃豆人顶墙停止 = 双重墙壁检测有效 (ROM 类型 + 坐标边界)
- 吃豆时分数增加 + 蜂鸣器响 = `pellet_we`/`score`/`sound_event` 信号链正确
- 被幽灵抓住→GAMEOVER 画面 = 实体碰撞检测 (坐标相等判断) 触发

---

### 4. vga_display — VGA 显示驱动

**仿真关注信号：**
- `h_cnt` / `v_cnt`：像素/行计数器
- `HSYNC` / `VSYNC`：行/场同步信号
- `grid_col` / `grid_row`：网格坐标
- `sub_x` / `sub_y`：格内像素偏移
- `map_addr`：地图读地址
- `active`：有效显示区域
- `VGA_R` / `VGA_G` / `VGA_B`：RGB 输出
- 跨时钟域同步信号：`pac_x_s1`→`pac_x_s2`, `gs_s1`→`gs_s2`

**波形分析要点：**
- **时序参数**：一帧 = 800×525 = 420,000 像素周期 ≈ 16.7ms (60Hz)
- **HSYNC**：低电平在 h_cnt 656-751 (共 96 cycles，约 3.8μs)，其余为高
- **VSYNC**：低电平在 v_cnt 490-491 (共 2 lines, 约 64μs)，其余为高
- **有效区域**：`active = (h_cnt<640) && (v_cnt<480)`，在此区域外 RGB 全 0
- **网格追踪**：`sub_x` 每像素 +1 (0→19)，`grid_col` 每 20 像素 +1 (0→31)
- **无除法器**：通过计数器实现 `/20` 和 `%20` 运算，避免组合逻辑除法器
- **CDC 同步**：`pac_x_s2` 比 `pac_x` 延迟 2 个 VGA 时钟周期 (~80ns)，对肉眼无影响
- **图层优先级**：黑色背景 < 墙壁 < 豆子 < 吃豆人 < 幽灵 < UI 叠加 (代码按此顺序覆盖)

**上板现象对应：**
- VGA 显示器正常显示 = 时序参数正确，显示器锁定同步信号
- 吃豆人/幽灵在正确位置 = CDC 同步 + 网格坐标追踪正确
- 豆子显示为小白点 = 4×4 像素 (in_dot) 在 20×20 格子内居中
- IDLE 画面绿色边框 + Pac-Man 图标 = 坐标范围判断正确
- WIN 画面金色边框叠加 = 图层优先级，UI 覆盖在游戏画面之上
- GAMEOVER 幽灵变白色 = game_state_s 条件渲染正确

---

### 5. ps2_keyboard — PS/2 键盘接口

**仿真关注信号：**
- `ps2_clk` / `ps2_data`：PS/2 总线信号
- `ps2_clk_sync0/1/2`：三级同步器输出
- `negedge_ps2_clk` / `negedge_ps2_clk_shift`：下降沿检测
- `bit_count`：位计数器 (0→10)
- `frame_buffer`：11-bit 帧缓冲区
- `frame_ready`：帧接收完成脉冲
- `scan_code`：提取的 8-bit 扫描码
- `waiting_e0` / `waiting_f0` / `extended_key`：解析状态标志
- `up/down/left/right`：黄方方向输出 (持续电平)
- `p2_up/down/left/right`：红方方向输出 (持续电平)
- `start_game` / `reset_game`：单周期脉冲

**波形分析要点：**
- **三级同步**：`ps2_clk` (异步) → `sync0` → `sync1` → `sync2`，每级延迟 1 个 100MHz 周期 (10ns)
- **下降沿检测**：`negedge_ps2_clk = !sync1 && sync2`，产生 1 周期宽脉冲
- **帧接收**：每个 PS/2 时钟下降沿采样 `ps2_data`，逐位写入 `frame_buffer[bit_count]`
- **帧时序**：Start(0) → D0→D7 (LSB first) → Parity(奇) → Stop(1)，共 11 bits
- **Make 码**：方向键 1 字节 (W=1D) 或 2 字节 (↑=E0+75)，置对应电平为 1
- **Break 码**：F0+码 (普通) 或 E0+F0+码 (扩展)，清零对应电平
- **持续电平输出**：方向信号在 Make/Break 之间保持，不受 Typematic Repeat 影响
- **特殊键脉冲**：`start_game`/`reset_game` 在 `frame_ready` 时产生单周期脉冲

**上板现象对应：**
- 键盘插入后角色可控制 = PS/2 协议握手正常，扫描码解析正确
- 按一次键角色不会多动 = 持续电平输出 + 10Hz game_tick 采样 (自然限制速率)
- 松键角色停止 = Break 码正确清零方向电平
- 双人控制独立 = 黄方 (WASD Make/Break) 和红方 (方向键 E0 Make/Break) 状态机正交
- Enter 开始 / ESC 复位 = 特殊键脉冲经过顶层 OR 后触发状态跳转

---

### 6. seg_display — 七段数码管驱动

**仿真关注信号：**
- `score_full`：16-bit 输入分数
- `bcd`：20-bit BCD 结果 (组合逻辑)
- `scan_state`：扫描状态 (0→1→2→3)
- `AN`：位选信号 (共阳低有效)
- `SEGMENT`：段选信号 (共阳低有效)
- `bcd_digit`：当前扫描位的 BCD 值

**波形分析要点：**
- **Double-Dabble 转换**：纯组合逻辑 function，16 次循环迭代，每次判断 ≥5 则 +3 再左移
- **转换结果**：`bcd = bin2bcd(score_full)`，16-bit 最大 65535 → 5 位 BCD (仅用低 4 位)
- **动态扫描**：`scan_state` 在 `clk_scan` 驱动下每周期 +1 (0→1→2→3→0→...)
- **AN 位选**：1110(个位) → 1101(十位) → 1011(百位) → 0111(千位)，每次仅 1 位为 0
- **段码编码**：共阳特性 — `0`=点亮, `1`=熄灭，dp 始终为 1 (不点亮)
- **段顺序**：dp-g-f-e-d-c-b-a (MSB→LSB)
- **扫描频率**：~1kHz / 4 = 250Hz 每位刷新率 (远超 60Hz 闪烁阈值)

**上板现象对应：**
- 数码管显示数字 = BCD 转换 + 段码查表正确
- 4 位同时显示 (视觉) = 动态扫描频率 > 60Hz，利用人眼视觉暂留
- 显示无闪烁 = 250Hz/位的刷新率远高于临界闪烁频率 (约 50Hz)
- 亮度均匀 = 每位点亮时间相等 (各 25% 占空比)
- 分数准确变化 = Double-Dabble 算法处理任意 0-9999 范围的二进制输入

---

### 7. buzzer_ctrl — 蜂鸣器控制器

**仿真关注信号：**
- `sound_event`：音效事件 (01=EAT, 10=DEATH, 11=WIN)
- `last_event`：边沿检测寄存器
- `playing`：播放状态标志
- `half_period`：当前半周期计数值
- `freq_cnt`：频率计数器
- `duration_cnt`：持续时间计数器
- `switch_cnt`：WIN 模式频率切换计数器

**波形分析要点：**
- **DDFS 原理**：`freq_cnt` 从 0 递增到 `half_period-1`，到达后翻转 `buzzer` 并清零计数器
- **800Hz (EAT)**：半周期 = 62,500 cycles (625μs)，方波周期 = 1.25ms
- **200Hz (DEATH)**：半周期 = 250,000 cycles (2.5ms)，方波周期 = 5ms — 频率为 EAT 的 1/4
- **WIN 交替**：`switch_cnt` 在 WIN 模式下递增，每 250ms 在 1000Hz/1500Hz 间切换
- **边沿触发**：检测 `sound_event != last_event`，避免电平触发导致的重复播放
- **持续时间**：`duration_cnt` 达到 `total_duration` 后自动清零 `playing`
- **方波对称**：50% 占空比，在半周期翻转确保对称

**上板现象对应：**
- 吃豆时短促高音 = 800Hz × 100ms，清脆响亮
- 死亡时低沉长音 = 200Hz × 500ms，低沉有分量感
- 胜利时上升音效 = 1000/1500Hz 交替 × 1s，旋律有上升感
- 无按键时蜂鸣器静音 = `sound_event=00` 时 `sound_active=0`，buzzer=0
- 音量适中 = 50% 占空比方波驱动蜂鸣器

---

### 8. top_pacman — 顶层集成

**仿真关注信号：**
- 所有子模块接口信号
- `RSTN` → `rst` 反相
- `SW[0]/SW[1]` 去抖后的 `sw0_rise`/`sw1_rise`
- `start_sig` = `kbd_start | sw0_rise`
- `reset_sig` = `kbd_reset | sw1_rise`
- `prev_state` / `pellet_init` (豆子初始化触发)
- `map_addr_b` 多路复用选择
- `LED` 状态编码

**波形分析要点：**
- **复位反相**：`wire rst = ~RSTN` — 连续赋值，无延迟
- **开关去抖**：SW[0] 经过 2-FF 同步器 + 上升沿检测，输出单周期 `sw0_rise` 脉冲
- **信号合并**：`start_sig` 和 `reset_sig` 为键盘和开关的 OR 逻辑
- **pellet_init**：检测 `prev_state != PLAY && game_state == PLAY`，产生单周期脉冲
- **地址多路复用**：`map_addr_b = pellet_we ? pellet_waddr : game_map_addr`
- **跨时钟域**：100MHz (游戏逻辑) ↔ 25MHz (VGA)，通过 set_false_path 豁免时序

**上板现象对应：**
- 按复位按钮系统复位 = RSTN 反相 + 各模块 rst 信号正确
- 拨 SW[0] 开始游戏 = 2-FF 去抖 + 上升沿检测 + start_sig 合并
- LED 正确指示状态 = game_state 编码到 LED 的组合逻辑
- 整体系统协调工作 = 所有子模块实例化和互连正确

---

## 仿真与上板对照总结

| 功能点 | 仿真验证 | 上板现象 |
|--------|---------|----------|
| VGA 显示 | HSYNC/VSYNC 时序 + RGB 图层 | 显示器正常显示游戏画面 |
| 键盘输入 | PS/2 11-bit 帧解析 | 按键控制角色移动 |
| 游戏逻辑 | 状态机 + 碰撞检测 + 吃豆 | 游戏规则正确运行 |
| 地图存储 | ROM/RAM 双端口读写 | 迷宫和豆子正确显示 |
| 分数显示 | BCD 转换 + 动态扫描 | 数码管实时更新分数 |
| 音效 | DDFS 方波频率 + 持续时间 | 蜂鸣器发出正确音调 |
| 时钟管理 | MMCM + 分频器 | 系统各时钟域正常工作 |
| 复位/开始 | 去抖 + 信号合并 | 按钮/开关正确响应 |
