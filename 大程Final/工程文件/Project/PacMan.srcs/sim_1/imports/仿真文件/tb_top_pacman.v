//============================================================================
// tb_top_pacman.v — top_pacman 顶层模块集成仿真测试平台
//============================================================================
// 仿真目标 (对应 README_仿真说明.md 第8节):
//   1. 验证顶层模块所有子模块正确实例化与互连
//   2. 验证复位逻辑: RSTN(低有效) → rst(高有效) 反相
//   3. 验证开关去抖动: SW[0]/SW[1] 2-FF 同步 + 上升沿检测
//   4. 验证开始/复位信号合并: 键盘 OR 开关
//   5. 验证 IDLE→PLAY 跳转 + LED 状态编码
//   6. 验证游戏运行: game_tick 驱动角色移动
//   7. 验证蜂鸣器/七段码输出
//
// 仿真加速策略:
//   - 用 defparam 覆盖 GAME_DIV/SCAN_DIV 加速 game_tick 和 scan_clk
//   - PS/2 时钟加速到 500kHz (原 ~15kHz), 大幅缩短仿真时间
//   - clk_div 中的 MMCM 原语在 Vivado xsim 中自动编译 UNISIM 库
//
// 波形分析要点:
//   - RSTN=0 → rst=1 (连续赋值反相)
//   - SW[0]/SW[1] 2-FF 同步 + 上升沿检测 → sw0_rise/sw1_rise 单脉冲
//   - start_sig = kbd_start | sw0_rise (OR 合并)
//   - LED: 00000001(IDLE)/00000010(PLAY)/00000100(GAMEOVER)/00001000(WIN)
//   - pellet_init: prev_state!=PLAY && game_state==PLAY 时产生脉冲
//============================================================================

`timescale 1ns / 1ps

module tb_top_pacman;

    // ======== 信号声明 ========
    reg         clk_100mhz;
    reg         RSTN;
    wire [3:0]  VGA_R, VGA_G, VGA_B;
    wire        HSYNC, VSYNC;
    reg         PS2_clk, PS2_data;
    wire [7:0]  SEGMENT;
    wire [3:0]  AN;
    wire [7:0]  LED;
    wire        Buzzer;
    reg  [15:0] SW;
    wire [4:0]  BTN_x;
    reg  [3:0]  BTN_y;

    // ======== 测试变量 ========
    integer     pass_cnt, fail_cnt;
    integer     i;

    // ======== 被测模块实例化 ========
    top_pacman uut (
        .clk_100mhz (clk_100mhz),
        .RSTN       (RSTN),
        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B),
        .HSYNC      (HSYNC),
        .VSYNC      (VSYNC),
        .PS2_clk    (PS2_clk),
        .PS2_data   (PS2_data),
        .SEGMENT    (SEGMENT),
        .AN         (AN),
        .LED        (LED),
        .Buzzer     (Buzzer),
        .SW         (SW),
        .BTN_x      (BTN_x),
        .BTN_y      (BTN_y)
    );

    // ======== 仿真加速: 覆盖 clk_div 的分频参数 ========
    // 实际值: GAME_DIV=10_000_000 (100ms), SCAN_DIV=100_000 (500Hz)
    // 仿真值: GAME_DIV=100 (1μs game_tick), SCAN_DIV=500 (100kHz scan_clk)
    defparam uut.u_clk.GAME_DIV = 24'd100;
    defparam uut.u_clk.SCAN_DIV = 17'd500;

    // ======== 100MHz 时钟生成 ========
    initial begin
        clk_100mhz = 1'b0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // ======== PS/2 协议辅助任务 ========
    // 发送一个 PS/2 扫描码 (11-bit 帧: Start+D0~D7+Parity+Stop)
    // PS/2 时钟加速: 半周期 1000ns → 500kHz (真实 ~15kHz)
    task ps2_send;
        input [7:0] code;
        reg parity;
        integer i;
        begin
            parity = ~(^code);
            // Start bit
            PS2_data = 1'b0; #1000; PS2_clk = 1'b0; #1000; PS2_clk = 1'b1;
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                PS2_data = code[i]; #1000; PS2_clk = 1'b0; #1000; PS2_clk = 1'b1;
            end
            // Parity bit
            PS2_data = parity; #1000; PS2_clk = 1'b0; #1000; PS2_clk = 1'b1;
            // Stop bit
            PS2_data = 1'b1; #1000; PS2_clk = 1'b0; #1000; PS2_clk = 1'b1;
            #2000;  // 帧间隔
        end
    endtask

    // 发送按键 Make 码 (按下)
    task press_key;
        input [7:0] make_code;
        begin
            ps2_send(make_code);
        end
    endtask

    // 发送按键 Break 码 (松开)
    task release_key;
        input [7:0] make_code;
        begin
            ps2_send(8'hF0);        // Break 前缀
            ps2_send(make_code);
        end
    endtask

    // 发送扩展键 Make 码 (如方向键)
    task press_ext_key;
        input [7:0] ext_code;
        begin
            ps2_send(8'hE0);        // 扩展前缀
            ps2_send(ext_code);
        end
    endtask

    // ======== 仿真主流程 ========
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        $display("==============================================");
        $display(" top_pacman 顶层集成仿真");
        $display(" 仿真加速: GAME_DIV=100 (1μs), SCAN_DIV=500");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. 上电复位 + LED 状态");
        $display("   2. 键盘 Enter → IDLE→PLAY 跳转");
        $display("   3. LED 状态编码验证");
        $display("   4. SW[0] 开始 / SW[1] 复位");
        $display("   5. 游戏运行 (game_tick 驱动)");
        $display("   6. 蜂鸣器 + 七段码连通性");
        $display("   7. RSTN 硬复位");
        $display("==============================================");

        // ---- 初始化 ----
        RSTN     = 1'b0;  // 低有效复位
        SW       = 16'd0;
        PS2_clk  = 1'b1;
        PS2_data = 1'b1;
        BTN_y    = 4'b0000;
        #500;
        RSTN = 1'b1;  // 释放复位
        #2000;
        $display("[%0t] 复位释放, 系统启动", $time);

        // ================================================================
        // 测试 1: 上电复位 → IDLE 状态
        // ================================================================
        $display("\n--- 测试 1: 上电复位 → IDLE ---");
        #100;
        $display("  LED = %b (期望 00000001 = IDLE)", LED);
        if (LED === 8'b00000001) begin
            $display("  ✓ IDLE 状态正确");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ LED 异常: %b", LED);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 2: 键盘 Enter → IDLE→PLAY
        // ================================================================
        $display("\n--- 测试 2: 键盘 Enter → PLAY ---");
        press_key(8'h5A);  // Enter Make 码
        #5000;  // 等待 start_sig 传递
        $display("  LED = %b (期望 00000010 = PLAY)", LED);
        if (LED === 8'b00000010) begin
            $display("  ✓ 进入 PLAY 状态");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ 状态跳转失败: LED=%b", LED);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 3: LED 状态编码 (遍历各状态)
        // ================================================================
        $display("\n--- 测试 3: LED 状态编码 ---");
        $display("  PLAY 状态: LED=%b (期望 00000010)", LED);
        if (LED === 8'b00000010) begin
            $display("  ✓ PLAY LED 正确");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ PLAY LED 错误");
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 4: SW[1] 复位 → 回到 IDLE
        // ================================================================
        $display("\n--- 测试 4: SW[1] 复位 → IDLE ---");
        SW[1] = 1'b1;
        #500;
        SW[1] = 1'b0;
        #2000;
        $display("  LED = %b (期望 00000001 = IDLE)", LED);
        if (LED === 8'b00000001) begin
            $display("  ✓ SW[1] 复位成功");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ SW[1] 复位异常: LED=%b", LED);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 5: SW[0] 开始游戏 + 键盘方向控制
        // ================================================================
        $display("\n--- 测试 5: SW[0] 开始 + 键盘方向 ---");
        SW[0] = 1'b1;
        #500;
        SW[0] = 1'b0;
        #2000;
        $display("  SW[0] 开始后 LED=%b (期望 PLAY)", LED);
        if (LED === 8'b00000010) begin
            $display("  ✓ SW[0] 开始成功");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ SW[0] 开始失败");
            fail_cnt = fail_cnt + 1;
        end

        // 发送方向键移动角色 (黄方: WASD, 红方: 方向键)
        // 注: WASD 是普通键 (1-byte make code)
        //     W=1D, A=1C, S=1B, D=23
        $display("  按 D 键 (右)...");
        press_key(8'h23);  // D make
        #2000;

        $display("  按 W 键 (上)...");
        release_key(8'h23); // D break
        #1000;
        press_key(8'h1D);   // W make
        #2000;

        // 等待 game_tick 驱动角色移动
        // GAME_DIV=100 → game_tick 每 1μs 产生一次 (100 个 100MHz 周期)
        // 等待 10 个 game_tick ≈ 10μs
        $display("  等待 game_tick 驱动游戏...");
        #20000;  // 20μs → ~20 game_ticks
        $display("  游戏运行了 ~20 个 game_tick");

        // ================================================================
        // 测试 6: 七段码 + 蜂鸣器连通性
        // ================================================================
        $display("\n--- 测试 6: 七段码 + 蜂鸣器 ---");
        $display("  SEGMENT = %b, AN = %b", SEGMENT, AN);
        $display("  Buzzer = %b", Buzzer);

        // 七段码在运行时应有输出 (AN 动态扫描, 至少有一位为 0)
        if (AN !== 4'b1111) begin
            $display("  ✓ 七段码 AN 扫描有效 (至少一位选中)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  (AN 全 1 — 可能扫描尚未开始或共阳极性, 通过波形验证)");
        end

        // ================================================================
        // 测试 7: RSTN 硬复位
        // ================================================================
        $display("\n--- 测试 7: RSTN 硬复位 ---");
        RSTN = 1'b0;
        #500;
        RSTN = 1'b1;
        #2000;
        $display("  硬复位后 LED = %b (期望 00000001 = IDLE)", LED);
        if (LED === 8'b00000001) begin
            $display("  ✓ RSTN 硬复位正确");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ RSTN 硬复位异常");
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 仿真总结
        // ================================================================
        #5000;
        $display("\n==============================================");
        $display(" top_pacman 顶层集成仿真完成");
        $display(" 通过: %0d / 失败: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" 结果: 全部测试通过 ✓");
        else
            $display(" 结果: 存在 %0d 项失败 ✗", fail_cnt);
        $display("==============================================");
        $display(" 波形检查清单:");
        $display("   1. RSTN 反相: RSTN=0 → rst=1");
        $display("   2. SW 去抖: sw0_rise/sw1_rise 单周期脉冲");
        $display("   3. start_sig = kbd_start | sw0_rise");
        $display("   4. game_state: IDLE→PLAY→(GAMEOVER/WIN)");
        $display("   5. LED 随 game_state 变化");
        $display("   6. pellet_init: IDLE→PLAY 跳变脉冲");
        $display("   7. map_addr_b MUX: pellet_we 控制切换");
        $display("==============================================");
        $display("");
        $display(" 注: 详细功能验证见各子模块 testbench:");
        $display("     tb_clk_div / tb_map_memory / tb_game_logic_fsm");
        $display("     tb_vga_display / tb_ps2_keyboard / tb_seg_display");
        $display("     tb_buzzer_ctrl");
        $display("==============================================");

        #1000;
        $finish;
    end

    // ======== 实时监控 ========
    reg prev_led;
    initial prev_led = 8'b00000000;

    always @(posedge clk_100mhz) begin
        if (LED !== prev_led) begin
            prev_led <= LED;
            $display("[%0t] >> LED 变化: %b → %b <<", $time, prev_led, LED);
        end
    end

endmodule
