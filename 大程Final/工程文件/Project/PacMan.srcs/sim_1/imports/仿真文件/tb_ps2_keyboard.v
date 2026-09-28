//============================================================================
// tb_ps2_keyboard.v — ps2_keyboard 模块功能仿真测试平台
//============================================================================
// 仿真目标:
//   1. 验证 PS/2 11-bit 帧接收: Start(0)+8bit+Parity(奇)+Stop(1)
//   2. 验证 普通 Make 码解析: W=1D, A=1C, S=1B, D=23
//   3. 验证 普通 Break 码解析: F0+码 → 方向电平归零
//   4. 验证 扩展 Make 码解析: E0+码 (方向键 → p2_up/down/left/right)
//   5. 验证 扩展 Break 码解析: E0+F0+码 → 方向电平归零
//   6. 验证 特殊键: Enter(5A)→start_game 脉冲, ESC(76)→reset_game 脉冲
//   7. 验证 同步器+边沿检测: PS/2_clk 下降沿采样 ps2_data
//   8. 验证 长按 Typematic: 多个 Make 码不产生多次移动
//
// 波形分析要点:
//   - PS/2 时钟频率 ~10-16kHz, clk 周期 ~60-100μs
//   - 三级同步器: ps2_clk → ps2_clk_sync0 → ps2_clk_sync1 → ps2_clk_sync2
//   - 边沿检测: negedge_ps2_clk = !ps2_clk_sync1 && ps2_clk_sync2
//   - negedge_ps2_clk_shift 额外打一拍确保数据稳定
//   - 一帧 11 bits × ~80μs ≈ 880μs 传输时间
//   - Make 码触发方向电平置 1, Break 码触发清零
//   - 扩展键通过 waiting_e0 / extended_key 状态位跟踪
//   - start_game / reset_game 为单周期脉冲
//============================================================================

`timescale 1ns / 1ps

module tb_ps2_keyboard;

    // ======== 信号声明 ========
    reg         clk;
    reg         rst;
    reg         ps2_clk;
    reg         ps2_data;
    wire        up, down, left, right;
    wire        p2_up, p2_down, p2_left, p2_right;
    wire        start_game;
    wire        reset_game;

    // ======== 被测模块实例化 ========
    ps2_keyboard uut (
        .clk        (clk),
        .rst        (rst),
        .ps2_clk    (ps2_clk),
        .ps2_data   (ps2_data),
        .up         (up),
        .down       (down),
        .left       (left),
        .right      (right),
        .p2_up      (p2_up),
        .p2_down    (p2_down),
        .p2_left    (p2_left),
        .p2_right   (p2_right),
        .start_game (start_game),
        .reset_game (reset_game)
    );

    // ======== 时钟生成 ========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz
    end

    // ======== PS/2 协议辅助任务 ========
    // 计算奇校验位 — 使 data 中 1 的个数为奇数
    function calc_parity;
        input [7:0] data;
        begin
            calc_parity = ~(^data);  // 奇校验: 1 个数为奇数时 parity=0
        end
    endfunction

    // 发送一个 PS/2 字节 (8-bit data, 带 Start/Parity/Stop)
    // clk_period: PS/2 时钟半周期 (ns)
    task ps2_send_byte;
        input [7:0] data;
        input [31:0] clk_half_period;
        reg parity;
        integer i;
        begin
            parity = calc_parity(data);

            // 1. Start bit (拉低 data 线, 由设备产生 clk)
            ps2_data = 1'b0;
            #(clk_half_period);
            ps2_clk  = 1'b0;  // 下降沿
            #(clk_half_period);
            ps2_clk  = 1'b1;  // 上升沿

            // 2. 8 data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                ps2_data = data[i];
                #(clk_half_period);
                ps2_clk  = 1'b0;
                #(clk_half_period);
                ps2_clk  = 1'b1;
            end

            // 3. Parity bit
            ps2_data = parity;
            #(clk_half_period);
            ps2_clk  = 1'b0;
            #(clk_half_period);
            ps2_clk  = 1'b1;

            // 4. Stop bit
            ps2_data = 1'b1;
            #(clk_half_period);
            ps2_clk  = 1'b0;
            #(clk_half_period);
            ps2_clk  = 1'b1;

            // 释放总线
            #(clk_half_period * 2);
        end
    endtask

    // 发送 W 键 Make 码 (1D)
    task send_W_make;
        begin
            $display("  [%0t] 发送 W Make 码 (1D)...", $time);
            ps2_send_byte(8'h1D, 50000);  // ~10kHz PS/2 clock
        end
    endtask

    // 发送 W 键 Break 码 (F0 1D)
    task send_W_break;
        begin
            $display("  [%0t] 发送 W Break 码 (F0 1D)...", $time);
            ps2_send_byte(8'hF0, 50000);
            ps2_send_byte(8'h1D, 50000);
        end
    endtask

    // 发送方向键 ↑ Make 码 (E0 75)
    task send_UP_make;
        begin
            $display("  [%0t] 发送 ↑ Make 码 (E0 75)...", $time);
            ps2_send_byte(8'hE0, 50000);
            ps2_send_byte(8'h75, 50000);
        end
    endtask

    // 发送方向键 ↑ Break 码 (E0 F0 75)
    task send_UP_break;
        begin
            $display("  [%0t] 发送 ↑ Break 码 (E0 F0 75)...", $time);
            ps2_send_byte(8'hE0, 50000);
            ps2_send_byte(8'hF0, 50000);
            ps2_send_byte(8'h75, 50000);
        end
    endtask

    // ======== 仿真主流程 ========
    initial begin
        $display("==============================================");
        $display(" ps2_keyboard 模块功能仿真");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. 三级同步 + 下降沿检测");
        $display("   2. 普通 Make 码 (W/A/S/D)");
        $display("   3. 普通 Break 码 (F0+W/A/S/D)");
        $display("   4. 扩展 Make 码 (方向键)");
        $display("   5. 扩展 Break 码 (E0+F0+方向键)");
        $display("   6. 特殊键 (Enter/ESC 脉冲)");
        $display("   7. 长按 Typematic 处理");
        $display("==============================================");

        // ---- 初始化 ----
        rst      = 1'b1;
        ps2_clk  = 1'b1;  // PS/2 空闲高电平
        ps2_data = 1'b1;  // 空闲高电平
        #100;
        rst = 1'b0;
        #100;

        // ================================================================
        // 测试 1: 复位后默认状态
        // ================================================================
        $display("\n--- 测试 1: 复位后默认状态 ---");
        #100;
        $display("  上/下/左/右 = %0d/%0d/%0d/%0d (应为全 0)", up, down, left, right);
        $display("  p2上/下/左/右 = %0d/%0d/%0d/%0d (应为全 0)", p2_up, p2_down, p2_left, p2_right);

        // ================================================================
        // 测试 2: W 键 Make/Break 码
        // ================================================================
        $display("\n--- 测试 2: W 键 Make/Break 码 (普通方向键) ---");

        // 按下 W → up 应为 1
        send_W_make();
        #5000;
        $display("  W Make:  up=%0d (应=1)", up);

        // 松开 W → up 应为 0
        send_W_break();
        #5000;
        $display("  W Break: up=%0d (应=0)", up);

        // ================================================================
        // 测试 3: A/S/D 键 Make/Break 码
        // ================================================================
        $display("\n--- 测试 3: A/S/D 键 Make/Break 码 ---");

        // A (left)
        $display("  发送 A Make 码 (1C)...");
        ps2_send_byte(8'h1C, 50000);
        #5000;
        $display("  A Make:  left=%0d (应=1)", left);

        $display("  发送 A Break 码 (F0 1C)...");
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h1C, 50000);
        #5000;
        $display("  A Break: left=%0d (应=0)", left);

        // D (right)
        $display("  发送 D Make 码 (23)...");
        ps2_send_byte(8'h23, 50000);
        #5000;
        $display("  D Make:  right=%0d (应=1)", right);

        $display("  发送 D Break 码 (F0 23)...");
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h23, 50000);
        #5000;
        $display("  D Break: right=%0d (应=0)", right);

        // ================================================================
        // 测试 4: 扩展方向键 Make/Break
        // ================================================================
        $display("\n--- 测试 4: 扩展方向键 (E0 prefix) ---");

        // ↑ (上箭头)
        send_UP_make();
        #5000;
        $display("  ↑ Make:  p2_up=%0d (应=1)", p2_up);

        send_UP_break();
        #5000;
        $display("  ↑ Break: p2_up=%0d (应=0)", p2_up);

        // ↓ (下箭头) E0 72
        $display("  发送 ↓ Make 码 (E0 72)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'h72, 50000);
        #5000;
        $display("  ↓ Make:  p2_down=%0d (应=1)", p2_down);

        $display("  发送 ↓ Break 码 (E0 F0 72)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h72, 50000);
        #5000;
        $display("  ↓ Break: p2_down=%0d (应=0)", p2_down);

        // ← (左箭头) E0 6B
        $display("  发送 ← Make 码 (E0 6B)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'h6B, 50000);
        #5000;
        $display("  ← Make:  p2_left=%0d (应=1)", p2_left);

        $display("  发送 ← Break 码 (E0 F0 6B)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h6B, 50000);
        #5000;
        $display("  ← Break: p2_left=%0d (应=0)", p2_left);

        // → (右箭头) E0 74
        $display("  发送 → Make 码 (E0 74)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'h74, 50000);
        #5000;
        $display("  → Make:  p2_right=%0d (应=1)", p2_right);

        $display("  发送 → Break 码 (E0 F0 74)...");
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h74, 50000);
        #5000;
        $display("  → Break: p2_right=%0d (应=0)", p2_right);

        // ================================================================
        // 测试 5: 特殊键 (Enter / ESC)
        // ================================================================
        $display("\n--- 测试 5: 特殊功能键 ---");

        // Enter: 5A → start_game 脉冲
        $display("  发送 Enter Make 码 (5A)...");
        ps2_send_byte(8'h5A, 50000);
        #5000;
        $display("  Enter: start_game 脉冲检测");

        @(posedge clk);
        if (start_game) begin
            $display("  ✓ start_game 脉冲输出");
        end

        // ESC: 76 → reset_game 脉冲
        $display("  发送 ESC Make 码 (76)...");
        ps2_send_byte(8'h76, 50000);
        #5000;
        $display("  ESC: reset_game 脉冲检测");

        @(posedge clk);
        if (reset_game) begin
            $display("  ✓ reset_game 脉冲输出");
        end

        // 确认 start_game / reset_game 为单周期脉冲
        @(posedge clk);
        if (!start_game && !reset_game)
            $display("  ✓ start_game/reset_game 为单周期脉冲 (已清零)");
        else
            $display("  ✗ 脉冲宽度异常!");

        // ================================================================
        // 测试 6: 长按 Typematic 处理
        // ================================================================
        $display("\n--- 测试 6: 长按 Typematic 处理 ---");
        $display("  连续发送 5 个 W Make 码 (模拟长按重复)");

        // 方向输出为持续电平, 多次 Make 不影响输出
        repeat (5) begin
            ps2_send_byte(8'h1D, 50000);
            #2000;
        end
        $display("  连续 5 次 Make 后: up=%0d (应为 1, 不累积)", up);

        // 发送 Break 码应清零
        send_W_break();
        #5000;
        $display("  Break 后: up=%0d (应为 0)", up);

        // ================================================================
        // 测试 7: 同时多键按下
        // ================================================================
        $display("\n--- 测试 7: 多键同时按下 ---");
        $display("  同时按下 W(up) 和 D(right)...");

        send_W_make();
        #1000;
        ps2_send_byte(8'h23, 50000);  // D Make
        #5000;
        $display("  W+D: up=%0d, right=%0d (应为 1,1)", up, right);

        // 只松开 W
        send_W_break();
        #5000;
        $display("  松开 W: up=%0d, right=%0d (应为 0,1)", up, right);

        // 松开 D
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h23, 50000);
        #5000;
        $display("  松开 D: up=%0d, right=%0d (应为 0,0)", up, right);

        // ================================================================
        // 测试 8: 黄方/红方方向独立
        // ================================================================
        $display("\n--- 测试 8: 黄方/红方方向独立 ---");
        $display("  黄方按 W(上), 红方按 ↓(下) → 两条控制线独立");

        send_W_make();  // 黄上
        #1000;
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'h72, 50000);  // 红下
        #5000;
        $display("  黄上红下: up=%0d (应=1), p2_down=%0d (应=1)", up, p2_down);

        send_W_break();
        #1000;
        ps2_send_byte(8'hE0, 50000);
        ps2_send_byte(8'hF0, 50000);
        ps2_send_byte(8'h72, 50000);
        #5000;
        $display("  全部松开: up=%0d, p2_down=%0d (应为 0,0)", up, p2_down);

        // ================================================================
        // 仿真完成
        // ================================================================
        #5000;
        $display("\n==============================================");
        $display(" ps2_keyboard 仿真完成");
        $display(" 请检查波形:");
        $display("   1. PS/2 clk 三级同步: ps2_clk → sync0 → sync1 → sync2");
        $display("   2. 下降沿检测: negedge_ps2_clk (单周期脉冲)");
        $display("   3. frame_buffer 逐位接收: bit_count 0→10");
        $display("   4. frame_ready: 每 11 bits 产生一个脉冲");
        $display("   5. Make 码 → 方向输出: 按下 =1 (持续电平)");
        $display("   6. Break 码 → 方向输出: 松开 =0");
        $display("   7. E0 prefix → waiting_e0=1 → 扩展键识别");
        $display("   8. 扩展 Break: E0+F0 → waiting_f0=1, extended_key=1");
        $display("   9. Enter/ESC → start_game/reset_game 单周期脉冲");
        $display("  10. 方向键输出为持续电平, 由 10Hz game_tick 采样");
        $display("==============================================");
        $finish;
    end

endmodule
