#=======================================================
# add_sim_files.tcl — 将所有仿真文件添加到 Vivado 工程
# 在 Vivado Tcl Console 中运行:
#   source PacMan.srcs/sim_1/add_sim_files.tcl
#=======================================================

# 仿真文件目录 (相对于工程根目录)
set sim_dir "PacMan.srcs/sim_1/imports/仿真文件"

# 添加所有仿真 testbench 文件
add_files -fileset sim_1 -norecurse [glob ${sim_dir}/tb_*.v]

# 添加仿真辅助文件 (clk_div 仿真版, 可替代 MMCM 原语仿真)
add_files -fileset sim_1 -norecurse ${sim_dir}/clk_div_sim.v

# 添加设计源文件到仿真 (若尚未在 sim_1 中)
add_files -fileset sim_1 -norecurse PacMan.srcs/sources_1/new/*.v

# 设置顶层仿真模块 (可按需修改)
# set_property top tb_game_logic_fsm [get_filesets sim_1]
# set_property top tb_clk_div          [get_filesets sim_1]
# set_property top tb_map_memory       [get_filesets sim_1]
# set_property top tb_vga_display      [get_filesets sim_1]
# set_property top tb_ps2_keyboard     [get_filesets sim_1]
# set_property top tb_seg_display      [get_filesets sim_1]
# set_property top tb_buzzer_ctrl      [get_filesets sim_1]
# set_property top tb_top_pacman       [get_filesets sim_1]

puts "============================================"
puts "  仿真文件添加完成!"
puts "  请在 Vivado 中设置顶层仿真模块:"
puts "    tb_clk_div       — 时钟管理"
puts "    tb_map_memory    — 地图存储"
puts "    tb_game_logic_fsm — 游戏逻辑 FSM"
puts "    tb_vga_display   — VGA 显示驱动"
puts "    tb_ps2_keyboard  — PS/2 键盘"
puts "    tb_seg_display   — 七段数码管"
puts "    tb_buzzer_ctrl   — 蜂鸣器"
puts "    tb_top_pacman    — 顶层集成"
puts "============================================"
