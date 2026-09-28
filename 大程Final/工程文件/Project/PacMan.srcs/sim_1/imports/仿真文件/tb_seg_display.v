//============================================================================
// tb_seg_display.v — seg_display 模块功能仿真测试平台
//============================================================================
// 仿真目标:
//   1. 验证 Double-Dabble BCD 转换: 二进制 → BCD (0-9999)
//   2. 验证动态扫描状态机: scan_state 0→1→2→3 循环
//   3. 验证 AN 位选信号: 共阳, 低有效 (1110→1101→1011→0111)
//   4. 验证 SEGMENT 段选信号: 共阳, 低有效, 正确的 7 段编码
//   5. 验证扫描频率: ~1kHz (在仿真中加速观察)
//   6. 验证 0-9 各数字的段码正确性
//   7. 验证复位行为: SEGMENT=全灭, AN=全灭
//
// 波形分析要点:
//   - BCD 转换使用组合逻辑 function, 输入变化后立即输出
//   - 动态扫描由 clk_scan 驱动, 每周期切换扫描位
//   - AN 信号: 每次仅 1 位为 0, 其余为 1 (共阳低有效)
//   - SEGMENT: 8-bit 编码 dp-g-f-e-d-c-b-a, 低电平点亮
//   - 4 位完整扫描周期 = 4 × clk_scan 周期
//   - Double-Dabble: 二进制→BCD 纯组合逻辑, 无时钟, 零延迟 (函数)
//   - 1kHz 扫描频率 (每位 250μs) 高于人眼闪烁感知阈值
//
// 上板现象对应:
//   - 数码管亮度均匀: 动态扫描每位点亮时间相等
//   - 无闪烁: 扫描频率 > 60Hz 临界闪烁频率 (实际 250Hz/位刷新)
//   - 正确显示分数: BCD 转换无误 + 段码查表正确
//============================================================================

`timescale 1ns / 1ps

module tb_seg_display;

    // ======== 信号声明 ========
    reg         clk;
    reg         clk_scan;
    reg         rst;
    reg  [7:0]  score;
    reg  [15:0] score_full;
    wire [7:0]  SEGMENT;
    wire [3:0]  AN;

    // ======== 被测模块实例化 ========
    seg_display uut (
        .clk        (clk),
        .clk_scan   (clk_scan),
        .rst        (rst),
        .score      (score),
        .score_full (score_full),
        .SEGMENT    (SEGMENT),
        .AN         (AN)
    );

    // ======== 时钟生成 ========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz
    end

    // 扫描时钟: ~1MHz (仿真加速, 便于波形观察)
    initial begin
        clk_scan = 1'b0;
        forever #500 clk_scan = ~clk_scan;  // 1MHz, 周期 1000ns
    end

    // ======== 辅助任务 ========
    // 验证一个数字的段码
    task check_digit;
        input [3:0] digit;
        input [7:0] expected_seg;
        reg [7:0] actual;
        begin
            // 设置分数为该数字 (放在千位以便在 AN=0111 时观察)
            score_full = {digit, 12'd0};  // 该数字 × 4096
            // 等待扫描到千位 (AN == 4'b0111)
            repeat (4) @(posedge clk_scan);
            wait(AN == 4'b0111);
            #10;
            actual = SEGMENT;
            if (actual == expected_seg)
                $display("  数字 %0d: SEGMENT=%b ✓", digit, actual);
            else
                $display("  数字 %0d: SEGMENT=%b (期望 %b) ✗", digit, actual, expected_seg);
        end
    endtask

    // ======== 仿真主流程 ========
    initial begin
        $display("==============================================");
        $display(" seg_display 模块功能仿真");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. Double-Dabble BCD 转换");
        $display("   2. 动态扫描状态机");
        $display("   3. AN 位选信号 (共阳低有效)");
        $display("   4. SEGMENT 段码表 (0-9)");
        $display("   5. 不同分数的正确显示");
        $display("   6. 复位行为");
        $display("==============================================");

        // ---- 初始化 ----
        rst        = 1'b1;
        score      = 8'd0;
        score_full = 16'd0;
        #100;
        rst = 1'b0;
        #50;

        // ================================================================
        // 测试 1: 复位后默认状态
        // ================================================================
        $display("\n--- 测试 1: 复位后默认状态 ---");
        #200;
        $display("  score=0 时 AN = %b, SEGMENT = %b", AN, SEGMENT);

        // ================================================================
        // 测试 2: 动态扫描状态机 — AN 循环
        // ================================================================
        $display("\n--- 测试 2: 动态扫描 AN 位选信号 ---");
        $display("  观察 4 位扫描循环...");

        score_full = 16'd1234;  // 设置分数为 1234

        // 等待扫描状态机运行, 记录 4 个 AN 状态
        @(negedge clk_scan);  // 等待扫描时钟边沿
        #10;
        $display("  scan_state=0 (个位): AN=%b, SEGMENT=%b (应显示 4)", AN, SEGMENT);

        @(negedge clk_scan);
        #10;
        $display("  scan_state=1 (十位): AN=%b, SEGMENT=%b (应显示 3)", AN, SEGMENT);

        @(negedge clk_scan);
        #10;
        $display("  scan_state=2 (百位): AN=%b, SEGMENT=%b (应显示 2)", AN, SEGMENT);

        @(negedge clk_scan);
        #10;
        $display("  scan_state=3 (千位): AN=%b, SEGMENT=%b (应显示 1)", AN, SEGMENT);

        // ================================================================
        // 测试 3: SEGMENT 段码表验证 (0-9)
        // ================================================================
        $display("\n--- 测试 3: 段码表验证 (共阳, 低有效) ---");
        $display("  段顺序: dp-g-f-e-d-c-b-a (MSB→LSB)");

        // 0: 8'b11000000
        score_full = 16'd0;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 0: SEGMENT=%b (期望 11000000), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b11000000) ? "✓" : "✗");

        // 1-9 逐一验证
        score_full = 16'd1;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 1: SEGMENT=%b (期望 11111001), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b11111001) ? "✓" : "✗");

        score_full = 16'd2;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 2: SEGMENT=%b (期望 10100100), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10100100) ? "✓" : "✗");

        score_full = 16'd3;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 3: SEGMENT=%b (期望 10110000), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10110000) ? "✓" : "✗");

        score_full = 16'd4;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 4: SEGMENT=%b (期望 10011001), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10011001) ? "✓" : "✗");

        score_full = 16'd5;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 5: SEGMENT=%b (期望 10010010), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10010010) ? "✓" : "✗");

        score_full = 16'd6;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 6: SEGMENT=%b (期望 10000010), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10000010) ? "✓" : "✗");

        score_full = 16'd7;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 7: SEGMENT=%b (期望 11111000), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b11111000) ? "✓" : "✗");

        score_full = 16'd8;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 8: SEGMENT=%b (期望 10000000), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10000000) ? "✓" : "✗");

        score_full = 16'd9;
        repeat (4) @(negedge clk_scan);
        wait(AN == 4'b0111);
        #10;
        $display("  数字 9: SEGMENT=%b (期望 10010000), 检查: %s",
                 SEGMENT, (SEGMENT == 8'b10010000) ? "✓" : "✗");

        // ================================================================
        // 测试 4: Double-Dabble BCD 转换验证
        // ================================================================
        $display("\n--- 测试 4: Double-Dabble BCD 转换验证 ---");

        // 验证典型值
        // 0 → BCD: 0
        score_full = 16'd0;
        #2000;
        $display("  score=0 → BCD=0");

        // 255 → BCD: 0255
        score_full = 16'd255;
        #2000;
        $display("  score=255 → 应显示 0255");

        // 1000 → BCD: 1000
        score_full = 16'd1000;
        #2000;
        $display("  score=1000 → 应显示 1000");

        // 9999 → BCD: 9999
        score_full = 16'd9999;
        #2000;
        $display("  score=9999 → 应显示 9999");

        // ================================================================
        // 测试 5: 游戏实际分数值
        // ================================================================
        $display("\n--- 测试 5: 游戏典型分数值 ---");
        score = 8'd42;   // 游戏中吃了 42 个豆子
        score_full = {8'd0, score};
        #2000;
        $display("  score=42 (游戏中典型值)");

        score = 8'd100;
        score_full = {8'd0, score};
        #2000;
        $display("  score=100");

        // ================================================================
        // 测试 6: 复位行为
        // ================================================================
        $display("\n--- 测试 6: 复位行为 ---");
        rst = 1'b1;
        #100;
        @(negedge clk_scan);
        #10;
        $display("  复位期间: AN=%b (应为全 1), SEGMENT=%b", AN, SEGMENT);
        rst = 1'b0;
        #50;

        // ================================================================
        // 测试 7: AN 位选独占性验证
        // ================================================================
        $display("\n--- 测试 7: AN 位选独占性 — 每次仅 1 位选中 ---");

        score_full = 16'd8888;  // 全相同便于观察
        @(negedge clk_scan);
        #10;
        $display("  AN[0]=%b, AN[1]=%b, AN[2]=%b, AN[3]=%b", AN[0], AN[1], AN[2], AN[3]);
        $display("  (共阳: 0=选中该位, 1=熄灭 — 每次应仅 1 位为 0)");

        @(negedge clk_scan);
        #10;
        $display("  AN[0]=%b, AN[1]=%b, AN[2]=%b, AN[3]=%b", AN[0], AN[1], AN[2], AN[3]);

        @(negedge clk_scan);
        #10;
        $display("  AN[0]=%b, AN[1]=%b, AN[2]=%b, AN[3]=%b", AN[0], AN[1], AN[2], AN[3]);

        @(negedge clk_scan);
        #10;
        $display("  AN[0]=%b, AN[1]=%b, AN[2]=%b, AN[3]=%b", AN[0], AN[1], AN[2], AN[3]);

        // ================================================================
        // 仿真完成
        // ================================================================
        #5000;
        $display("\n==============================================");
        $display(" seg_display 仿真完成");
        $display(" 请检查波形:");
        $display("   1. scan_state: 0→1→2→3 循环 (clk_scan 驱动)");
        $display("   2. AN: 1110→1101→1011→0111 循环 (共阳低有效)");
        $display("   3. SEGMENT 随 scan_state 切换不同数字");
        $display("   4. BCD 转换: 组合逻辑, 无延迟, score 变化后立即更新");
        $display("   5. 段码编码: 共阳, 0=亮/1=灭, dp 始终为 1");
        $display("   6. 每个 scan_state 期间 SEGMENT 保持不变");
        $display("");
        $display(" 上板现象对应:");
        $display("   - 1kHz 扫描: 每位 250μs, 视觉无闪烁");
        $display("   - 共阳驱动: AN 低电平选中, 高电平熄灭");
        $display("   - 亮度由扫描占空比决定 (25%%/位)");
        $display("==============================================");
        $finish;
    end

endmodule
