#=============================================================================
# sword_pacman.xdc — 吃豆人游戏 管脚约束文件
# 基于 Sword-VGA-PS2.ucf 翻译为 XDC 格式
# 目标: Sword Kintex 7 (XC7K160/325)
# Vivado 约束格式 (XDC)
#=============================================================================

# ======== 系统时钟 100MHz ========
set_property PACKAGE_PIN AC18     [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS18  [get_ports clk_100mhz]
create_clock -period 10.000 -name clk_100mhz [get_ports clk_100mhz]

# ======== MMCM 输出时钟约束 ========
# VGA 25MHz 由 MMCM 生成, Vivado 自动推导。加跨时钟域豁免。
set_false_path -from [get_clocks clk_100mhz] -to [get_clocks -include_generated_clocks clk_100mhz]
set_false_path -from [get_clocks -include_generated_clocks clk_100mhz] -to [get_clocks clk_100mhz]
# 关键: 豁免游戏逻辑(100MHz) ↔ VGA(25MHz) 之间的所有路径
set_false_path -from [get_cells -hier -filter {NAME =~ *u_game/*}] -to [get_cells -hier -filter {NAME =~ *u_vga/*}]
set_false_path -from [get_cells -hier -filter {NAME =~ *u_vga/*}] -to [get_cells -hier -filter {NAME =~ *u_game/*}]

# ======== 复位按钮 RSTN ========
set_property PACKAGE_PIN W13      [get_ports RSTN]
set_property IOSTANDARD LVCMOS18  [get_ports RSTN]

# ======== VGA 输出 (12-bit RGB = R4:G4:B4) ========
# Red
set_property PACKAGE_PIN N21      [get_ports {VGA_R[0]}]
set_property PACKAGE_PIN N22      [get_ports {VGA_R[1]}]
set_property PACKAGE_PIN R21      [get_ports {VGA_R[2]}]
set_property PACKAGE_PIN P21      [get_ports {VGA_R[3]}]
set_property IOSTANDARD LVCMOS33  [get_ports {VGA_R[*]}]
set_property SLEW FAST            [get_ports {VGA_R[*]}]

# Green
set_property PACKAGE_PIN R22      [get_ports {VGA_G[0]}]
set_property PACKAGE_PIN R23      [get_ports {VGA_G[1]}]
set_property PACKAGE_PIN T24      [get_ports {VGA_G[2]}]
set_property PACKAGE_PIN T25      [get_ports {VGA_G[3]}]
set_property IOSTANDARD LVCMOS33  [get_ports {VGA_G[*]}]
set_property SLEW FAST            [get_ports {VGA_G[*]}]

# Blue
set_property PACKAGE_PIN T20      [get_ports {VGA_B[0]}]
set_property PACKAGE_PIN R20      [get_ports {VGA_B[1]}]
set_property PACKAGE_PIN T22      [get_ports {VGA_B[2]}]
set_property PACKAGE_PIN T23      [get_ports {VGA_B[3]}]
set_property IOSTANDARD LVCMOS33  [get_ports {VGA_B[*]}]
set_property SLEW FAST            [get_ports {VGA_B[*]}]

# HSYNC / VSYNC
set_property PACKAGE_PIN M22      [get_ports HSYNC]
set_property PACKAGE_PIN M21      [get_ports VSYNC]
set_property IOSTANDARD LVCMOS33  [get_ports {HSYNC VSYNC}]
set_property SLEW FAST            [get_ports {HSYNC VSYNC}]

# ======== PS/2 键盘 ========
set_property PACKAGE_PIN N18      [get_ports PS2_clk]
set_property PACKAGE_PIN M19      [get_ports PS2_data]
set_property IOSTANDARD LVCMOS33  [get_ports {PS2_clk PS2_data}]
# set_property PULLUP TRUE          [get_ports {PS2_clk PS2_data}]

# ======== 蜂鸣器 (Arduino 子板) ========
set_property PACKAGE_PIN AF24     [get_ports Buzzer]
set_property IOSTANDARD LVCMOS33  [get_ports Buzzer]

# ======== 七段码 (Arduino 子板, 共阳动态扫描) ========
# 段选 SEGMENT[7:0]
set_property PACKAGE_PIN AB22     [get_ports {SEGMENT[0]}]
set_property PACKAGE_PIN AD24     [get_ports {SEGMENT[1]}]
set_property PACKAGE_PIN AD23     [get_ports {SEGMENT[2]}]
set_property PACKAGE_PIN Y21      [get_ports {SEGMENT[3]}]
set_property PACKAGE_PIN W20      [get_ports {SEGMENT[4]}]
set_property PACKAGE_PIN AC24     [get_ports {SEGMENT[5]}]
set_property PACKAGE_PIN AC23     [get_ports {SEGMENT[6]}]
set_property PACKAGE_PIN AA22     [get_ports {SEGMENT[7]}]
set_property IOSTANDARD LVCMOS33  [get_ports {SEGMENT[*]}]

# 位选 AN[3:0]
set_property PACKAGE_PIN AD21     [get_ports {AN[0]}]
set_property PACKAGE_PIN AC21     [get_ports {AN[1]}]
set_property PACKAGE_PIN AB21     [get_ports {AN[2]}]
set_property PACKAGE_PIN AC22     [get_ports {AN[3]}]
set_property IOSTANDARD LVCMOS33  [get_ports {AN[*]}]

# ======== LED (Arduino 子板, 8个) ========
set_property PACKAGE_PIN AB26     [get_ports {LED[0]}]
set_property PACKAGE_PIN W24      [get_ports {LED[1]}]
set_property PACKAGE_PIN W23      [get_ports {LED[2]}]
set_property PACKAGE_PIN AB25     [get_ports {LED[3]}]
set_property PACKAGE_PIN AA25     [get_ports {LED[4]}]
set_property PACKAGE_PIN W21      [get_ports {LED[5]}]
set_property PACKAGE_PIN V21      [get_ports {LED[6]}]
set_property PACKAGE_PIN W26      [get_ports {LED[7]}]
set_property IOSTANDARD LVCMOS33  [get_ports {LED[*]}]

# ======== 开关 SW[15:0] ========
set_property PACKAGE_PIN AA10     [get_ports {SW[0]}]
set_property PACKAGE_PIN AB10     [get_ports {SW[1]}]
set_property PACKAGE_PIN AA13     [get_ports {SW[2]}]
set_property PACKAGE_PIN AA12     [get_ports {SW[3]}]
set_property PACKAGE_PIN Y13      [get_ports {SW[4]}]
set_property PACKAGE_PIN Y12      [get_ports {SW[5]}]
set_property PACKAGE_PIN AD11     [get_ports {SW[6]}]
set_property PACKAGE_PIN AD10     [get_ports {SW[7]}]
set_property PACKAGE_PIN AE10     [get_ports {SW[8]}]
set_property PACKAGE_PIN AE12     [get_ports {SW[9]}]
set_property PACKAGE_PIN AF12     [get_ports {SW[10]}]
set_property PACKAGE_PIN AE8      [get_ports {SW[11]}]
set_property PACKAGE_PIN AF8      [get_ports {SW[12]}]
set_property PACKAGE_PIN AE13     [get_ports {SW[13]}]
set_property PACKAGE_PIN AF13     [get_ports {SW[14]}]
set_property PACKAGE_PIN AF10     [get_ports {SW[15]}]
set_property IOSTANDARD LVCMOS15  [get_ports {SW[*]}]

# ======== 按钮 (阵列键盘 → 独立键模式) ========
# BTN_x[4:0] → K_ROW[4:0]  (输出, 固定为 00000)
set_property PACKAGE_PIN V17      [get_ports {BTN_x[0]}]
set_property PACKAGE_PIN W18      [get_ports {BTN_x[1]}]
set_property PACKAGE_PIN W19      [get_ports {BTN_x[2]}]
set_property PACKAGE_PIN W15      [get_ports {BTN_x[3]}]
set_property PACKAGE_PIN W16      [get_ports {BTN_x[4]}]
set_property IOSTANDARD LVCMOS18  [get_ports {BTN_x[*]}]

# BTN_y[3:0] → K_COL[3:0]  (输入)
set_property PACKAGE_PIN V18      [get_ports {BTN_y[0]}]
set_property PACKAGE_PIN V19      [get_ports {BTN_y[1]}]
set_property PACKAGE_PIN V14      [get_ports {BTN_y[2]}]
set_property PACKAGE_PIN W14      [get_ports {BTN_y[3]}]
set_property IOSTANDARD LVCMOS18  [get_ports {BTN_y[*]}]

# ======== 时钟约束 (VGA 25MHz 派生时钟) ========
# Vivado 会自动追踪 clk_div 生成的时钟, 此处创建生成时钟约束
# create_generated_clock -name clk_vga -source [get_pins u_clk_div/vga_clk_reg/Q] \
#     -divide_by 4 [get_pins u_clk_div/vga_clk_reg/Q]
# 注: 如果使用 MMCM 生成 VGA 时钟, 则不需要以上约束
