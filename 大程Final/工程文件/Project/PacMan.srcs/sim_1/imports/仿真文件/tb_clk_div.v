//============================================================================
// tb_clk_div.v — clk_div 模块功能仿真测试平台
//============================================================================
// 仿真目标 (对应 README_仿真说明.md 第1节):
//   1. 验证 VGA 时钟频率 (~25MHz, MMCM 生成)
//   2. 验证 game_clk 为单周期脉冲 (高电平持续 1 个 clk_100mhz 周期)
//   3. 验证 scan_clk 为 50% 占空比方波
//   4. 验证复位行为 — 复位期间输出保持 0
//
// 被测模块: clk_div (MMCM 原语版本, Vivado xsim 原生支持)
//   用 defparam 加速 game_clk/scan_clk 分频参数, 缩短仿真时间
//
// 波形分析要点:
//   - vga_clk: 由 MMCM 生成 ~25.098MHz (周期约 39.8ns)
//   - game_clk: 单周期高脉冲 — 确保 FSM 一个 Tick 只执行一次
//   - scan_clk: 50% 占空比连续方波 — 驱动七段码扫描状态机
//   - 仿真加速: GAME_DIV=100 (1μs), SCAN_DIV=500 (100kHz)
//============================================================================

`timescale 1ns / 1ps

module tb_clk_div;

    // ======== 信号声明 ========
    reg  clk_100mhz;
    reg  rst;
    wire vga_clk;
    wire game_clk;
    wire scan_clk;

    // ======== 测试用变量声明 ========
    integer       pass_cnt, fail_cnt;
    integer       i;
    integer       vga_start_time, vga_end_time, vga_period;
    integer       scan_rise_time, scan_fall_time, scan_next_rise_time;
    integer       scan_high_time, scan_period_time;
    integer       game_rise_time, game_fall_time;
    reg           game_is_pulse;

    // ======== 被测模块实例化 (MMCM 版本 + 仿真加速) ========
    // defparam 覆盖分频参数: 实际 GAME_DIV=10_000_000(100ms), SCAN_DIV=100_000(500Hz)
    defparam uut.GAME_DIV = 24'd100;
    defparam uut.SCAN_DIV = 17'd500;
    clk_div uut (
        .clk_100mhz (clk_100mhz),
        .rst        (rst),
        .vga_clk    (vga_clk),
        .game_clk   (game_clk),
        .scan_clk   (scan_clk)
    );

    // ======== 100MHz 时钟生成 (周期 10ns) ========
    initial begin
        clk_100mhz = 1'b0;
        forever #5 clk_100mhz = ~clk_100mhz;
    end

    // ======== 仿真主流程 ========
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        $display("==============================================");
        $display(" clk_div 模块功能仿真");
        $display(" 被测模块: clk_div_sim (仿真友好版)");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. VGA 时钟生成 (25MHz, 周期 ~40ns)");
        $display("   2. game_clk 单周期脉冲特性");
        $display("   3. scan_clk 50%% 占空比方波");
        $display("   4. 复位行为验证");
        $display("==============================================");

        // ---- 初始条件: 复位 ----
        rst = 1'b1;
        #200;  // 200ns 复位
        rst = 1'b0;
        #50;   // 等待稳定
        $display("[%0t] 复位释放, 开始测试...", $time);

        // ================================================================
        // 测试 1: VGA 时钟频率验证
        // ================================================================
        $display("--- 测试 1: VGA 时钟频率 ---");
        // 预期: vga_clk 周期约 40ns (25MHz)
        // 测量 100 个 vga_clk 周期的平均周期
        @(posedge vga_clk);
        vga_start_time = $time;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge vga_clk);
        end
        vga_end_time = $time;
        vga_period = (vga_end_time - vga_start_time) / 100;
        $display("  [%0t] 100 个 VGA 周期总时间: %0d ns", $time, vga_end_time - vga_start_time);
        $display("  [%0t] VGA 时钟平均周期: %0d ns (期望 ~40ns)", $time, vga_period);

        // 允许 ±5ns 误差 (一个 100MHz 半周期)
        if (vga_period >= 35 && vga_period <= 45) begin
            $display("  [%0t] ✓ 测试 1 通过: VGA 时钟频率正确 (~25MHz)", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [%0t] ✗ 测试 1 失败: VGA 时钟周期异常!", $time);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 2: game_clk 单周期脉冲验证
        // ================================================================
        $display("--- 测试 2: game_clk 脉冲特性 ---");
        // 预期: game_clk 为单周期脉冲 (高电平仅持续 1 个 100MHz 周期 = 10ns)
        // GAME_DIV=100, 所以 game_clk 每 1μs 产生一个脉冲
        // 等待 game_clk 上升沿
        @(posedge game_clk);
        game_rise_time = $time;
        $display("  [%0t] game_clk 上升沿", $time);

        // 在下一个 100MHz 时钟上升沿检查 game_clk 是否已清零 (单周期脉冲)
        @(posedge clk_100mhz);
        #1;  // 小延迟避免 delta 竞争
        game_fall_time = $time;
        game_is_pulse = (game_clk == 1'b0);

        if (game_is_pulse) begin
            $display("  [%0t] ✓ game_clk 为单周期脉冲 (宽度 ~10ns), 正确!", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [%0t] ✗ game_clk 未在下一周期清零 (宽度 > 10ns), 异常!", $time);
            fail_cnt = fail_cnt + 1;
        end

        // 再观察几个 game_clk 脉冲, 验证周期性
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge game_clk);
            $display("  [%0t] game_clk 第 %0d 个脉冲 (间隔验证)", $time, i + 2);
            @(posedge clk_100mhz);
            #1;
            if (game_clk != 1'b0) begin
                $display("  [%0t] ✗ game_clk 脉冲宽度异常!", $time);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ================================================================
        // 测试 3: scan_clk 频率与占空比
        // ================================================================
        $display("--- 测试 3: scan_clk 频率与占空比 ---");
        // 预期: SCAN_DIV=500, scan_clk 周期 = 1000 * 10ns = 10μs (100kHz)
        //       50% 占空比: 高电平 = 低电平 = 5μs
        @(posedge scan_clk);
        scan_rise_time = $time;
        $display("  [%0t] scan_clk 上升沿", $time);

        @(negedge scan_clk);
        scan_fall_time = $time;
        scan_high_time = scan_fall_time - scan_rise_time;
        $display("  [%0t] scan_clk 下降沿, 高电平时间: %0d ns", $time, scan_high_time);

        @(posedge scan_clk);
        scan_next_rise_time = $time;
        scan_period_time = scan_next_rise_time - scan_rise_time;
        $display("  [%0t] scan_clk 下一个上升沿, 周期: %0d ns", $time, scan_period_time);

        // 验证 50% 占空比 (高电平 = 半周期, 允许 ±1 个 100MHz 周期 = ±10ns)
        if (scan_high_time >= scan_period_time / 2 - 15 &&
            scan_high_time <= scan_period_time / 2 + 15) begin
            $display("  [%0t] ✓ scan_clk 占空比约 50%%, 正确!", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [%0t] ✗ scan_clk 占空比偏差过大 (高电平 %0d ns / 周期 %0d ns)!",
                     $time, scan_high_time, scan_period_time);
            fail_cnt = fail_cnt + 1;
        end

        // 验证 scan_clk 频率 (SCAN_DIV=500 →  100kHz, 周期 10,000ns)
        if (scan_period_time >= 9500 && scan_period_time <= 10500) begin
            $display("  [%0t] ✓ scan_clk 频率正确 (~100kHz, defparam加速)", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [%0t] ✗ scan_clk 频率异常 (周期 %0d ns)!", $time, scan_period_time);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 4: 复位行为
        // ================================================================
        $display("--- 测试 4: 复位行为 ---");
        #1000;
        rst = 1'b1;
        #50;
        // 复位期间, game_clk 和 scan_clk 应为 0
        // (vga_clk 由组合逻辑驱动, 也会被复位)
        if (game_clk == 1'b0 && scan_clk == 1'b0) begin
            $display("  [%0t] ✓ 复位期间 game_clk 和 scan_clk 均为 0", $time);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [%0t] ✗ 复位期间输出异常 (game_clk=%b, scan_clk=%b)!",
                     $time, game_clk, scan_clk);
            fail_cnt = fail_cnt + 1;
        end
        #100;
        rst = 1'b0;
        #50;

        // 复位释放后, 时钟应恢复正常
        // 等待一个 game_clk 脉冲确认恢复
        @(posedge game_clk);
        $display("  [%0t] ✓ 复位释放后 game_clk 恢复正常", $time);
        pass_cnt = pass_cnt + 1;

        // ================================================================
        // 仿真总结
        // ================================================================
        $display("==============================================");
        $display(" clk_div 仿真完成");
        $display(" 通过: %0d / 失败: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" 结果: 全部测试通过 ✓");
        else
            $display(" 结果: 存在 %0d 项失败 ✗", fail_cnt);
        $display("==============================================");
        $display(" 波形检查清单:");
        $display("   1. vga_clk: 由 MMCM 生成 ~25.098MHz (周期约 39.8ns)");
        $display("   2. game_clk: 每 100 个 100MHz 周期产生一个 10ns 宽脉冲");
        $display("   3. scan_clk: 每 500 个 100MHz 周期翻转, 50%% 占空比");
        $display("   4. 复位: 所有计数器清零, 输出为 0");
        $display("   5. 仿真加速: defparam GAME_DIV=100, SCAN_DIV=500");
        $display("==============================================");

        #1000;
        $finish;
    end

    // ======== 实时监控 ========
    always @(posedge game_clk) begin
        $display("[%0t] >> game_clk 脉冲触发 <<", $time);
    end

endmodule
