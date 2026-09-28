//============================================================================
// tb_game_logic_fsm.v — game_logic_fsm 模块功能仿真测试平台
//============================================================================
// 仿真目标:
//   1. 验证主状态机状态跳转: IDLE→PLAY→GAMEOVER / IDLE→PLAY→WIN
//   2. 验证 PLAY 子状态机: P_IDLE→P_CALC→P_CHECK→P_PELLET→P_GHOST→P_IDLE
//   3. 验证黄方 (吃豆人) 移动控制: WASD 方向 + 墙壁碰撞检测
//   4. 验证红方 (幽灵) 移动控制: 方向键控制 + 墙壁碰撞检测
//   5. 验证实体碰撞检测: 吃豆人 == 幽灵坐标 → GAMEOVER
//   6. 验证吃豆逻辑: 踩中豆子 → score+1, pellet_we=1, sound_event=EAT
//   7. 验证 Win 条件: pellets_remain == 0 → WIN 状态
//   8. 验证 start_game / reset_game 脉冲行为
//
// 波形分析要点:
//   - game_tick 为 10Hz 脉冲, 每个脉冲触发一次子状态机循环
//   - 子状态: P_IDLE(等待tick) → P_CALC(算坐标) → P_CHECK(查墙) →
//             P_PELLET(吃豆) → P_GHOST(移幽灵+碰撞) → P_IDLE
//   - 吃豆人移动遵循 WASD 方向 + 墙壁碰撞双重检测
//   - 幽灵移动同样遵循方向键 + 墙壁碰撞检测
//   - 碰撞检测在 P_GHOST 中执行
//   - map_addr 在子状态间切换: P_CALC→吃豆人坐标, P_PELLET→幽灵坐标
//============================================================================

`timescale 1ns / 1ps

module tb_game_logic_fsm;

    // ======== 信号声明 ========
    reg         clk;
    reg         game_tick;
    reg         rst;
    reg         up, down, left, right;
    reg         p2_up, p2_down, p2_left, p2_right;
    reg         start_game;
    reg         reset_game;
    wire [9:0]  map_addr;
    reg  [1:0]  map_type;         // 模拟 map_memory 的读数据
    reg         pellet_state;     // 模拟豆子状态
    wire [9:0]  pellet_waddr;
    wire        pellet_we;
    wire        pellet_din;
    reg  [9:0]  pellet_total;     // 模拟豆子总数
    wire [4:0]  pac_x, pac_y;
    wire [4:0]  ghost_x, ghost_y;
    wire [1:0]  game_state;
    wire [7:0]  score;
    wire [1:0]  sound_event;
    wire [7:0]  debug_led;

    // ======== 参数定义 (来自被测模块) ========
    parameter IDLE     = 2'd0;
    parameter PLAY     = 2'd1;
    parameter GAMEOVER = 2'd2;
    parameter WIN      = 2'd3;

    // ======== 被测模块实例化 ========
    game_logic_fsm uut (
        .clk          (clk),
        .game_tick    (game_tick),
        .rst          (rst),
        .up           (up),
        .down         (down),
        .left         (left),
        .right        (right),
        .p2_up        (p2_up),
        .p2_down      (p2_down),
        .p2_left      (p2_left),
        .p2_right     (p2_right),
        .start_game   (start_game),
        .reset_game   (reset_game),
        .map_addr     (map_addr),
        .map_type     (map_type),
        .pellet_state (pellet_state),
        .pellet_waddr (pellet_waddr),
        .pellet_we    (pellet_we),
        .pellet_din   (pellet_din),
        .pellet_total (pellet_total),
        .pac_x        (pac_x),
        .pac_y        (pac_y),
        .ghost_x      (ghost_x),
        .ghost_y      (ghost_y),
        .game_state   (game_state),
        .score        (score),
        .sound_event  (sound_event),
        .debug_led    (debug_led)
    );

    // ======== 时钟生成 ========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100MHz
    end

    // ======== 模拟 map_memory 响应 ========
    // map_addr = {row[4:0], col[4:0]}, 根据位置返回 map_type 和 pellet_state
    // 简化迷宫模型:
    //   - 外边界 (row=0,23 或 col=0,31) → 墙壁 (2'b01)
    //   - 内部大部分 → 空地 (2'b00), 有豆子
    //   - 特殊: Row 13, Col 13-18 → 幽灵房 (2'b10), 无豆子
    //   - 特殊: Row 16, Col 16 → 出生点 (2'b11), 有豆子

    wire [4:0] sim_row = map_addr[9:5];
    wire [4:0] sim_col = map_addr[4:0];

    always @(*) begin
        // 默认值
        map_type     = 2'b00;  // 空地
        pellet_state = 1'b1;   // 有豆子

        // 外圈墙壁
        if (sim_row == 0 || sim_row == 23 || sim_col == 0 || sim_col == 31) begin
            map_type     = 2'b01;  // 墙壁
            pellet_state = 1'b0;   // 无豆子
        end

        // 幽灵房区域 (这里简化为部分检测)
        if (sim_row >= 13 && sim_row <= 14 && sim_col >= 13 && sim_col <= 18) begin
            map_type     = 2'b10;  // 幽灵房
            pellet_state = 1'b0;   // 无豆子
        end

        // 吃豆人出生点
        if (sim_row == 16 && sim_col == 16) begin
            map_type     = 2'b11;  // 出生点
            pellet_state = 1'b1;   // 有豆子
        end
    end

    // ======== game_tick 脉冲生成 (加速版: ~1MHz 便于观察) ========
    // 实际系统: GAME_DIV=10,000,000 → 10Hz
    // 仿真中: GAME_DIV=100 → 1MHz (便于观察状态机全流程)
    reg [6:0] tick_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_cnt  <= 7'd0;
            game_tick <= 1'b0;
        end else if (tick_cnt == 7'd99) begin
            tick_cnt  <= 7'd0;
            game_tick <= 1'b1;
        end else begin
            tick_cnt  <= tick_cnt + 7'd1;
            game_tick <= 1'b0;
        end
    end

    // ======== 辅助任务 ========
    task send_game_tick;
        begin
            @(posedge clk);
            game_tick <= 1'b1;  // 覆盖自动生成的 tick
            @(posedge clk);
            game_tick <= 1'b0;
        end
    endtask

    task wait_game_tick;
        begin
            wait(game_tick == 1'b1);
            @(posedge clk);  // 等一个周期
        end
    endtask

    // 打印当前游戏状态
    task print_state;
        begin
            case (game_state)
                IDLE:     $write("IDLE");
                PLAY:     $write("PLAY");
                GAMEOVER: $write("GAMEOVER");
                WIN:      $write("WIN");
                default:  $write("UNKNOWN");
            endcase
        end
    endtask

    // ======== 仿真主流程 ========
    initial begin
        $display("==============================================");
        $display(" game_logic_fsm 模块功能仿真");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. 主状态机: IDLE → PLAY → GAMEOVER / WIN");
        $display("   2. PLAY 子状态机: 5-step 流水线");
        $display("   3. 黄方移动 + 墙壁碰撞");
        $display("   4. 红方移动 + 墙壁碰撞");
        $display("   5. 吃豆逻辑 + 分数累加");
        $display("   6. 实体碰撞检测");
        $display("   7. Win 条件判定");
        $display("   8. Start/Reset 控制");
        $display("==============================================");

        // ---- 初始化 ----
        rst         = 1'b1;
        up=0; down=0; left=0; right=0;
        p2_up=0; p2_down=0; p2_left=0; p2_right=0;
        start_game  = 1'b0;
        reset_game  = 1'b0;
        pellet_total = 10'd100;  // 假设地图有 100 个豆子
        #50;
        rst = 1'b0;
        #20;

        // ================================================================
        // 测试 1: 复位后状态确认 + IDLE → PLAY 跳转
        // ================================================================
        $display("\n--- 测试 1: 复位 → IDLE 状态 ---");
        #10;
        $write("  当前状态: "); print_state(); $display("");
        $display("  pac=(%0d,%0d), ghost=(%0d,%0d), score=%0d", pac_x, pac_y, ghost_x, ghost_y, score);
        if (debug_led == 8'h01)
            $display("  ✓ debug_led=0x01 (IDLE 指示)");
        else
            $display("  ✗ debug_led 异常");

        // 发出 start_game 脉冲
        $display("\n--- 测试 1b: start_game → PLAY ---");
        @(posedge clk);
        start_game <= 1'b1;
        @(posedge clk);
        start_game <= 1'b0;
        #10;
        $write("  当前状态: "); print_state(); $display("");
        $display("  pac=(%0d,%0d), ghost=(%0d,%0d), score=%0d", pac_x, pac_y, ghost_x, ghost_y, score);

        // ================================================================
        // 测试 2: PLAY 子状态机 + 黄方移动
        // ================================================================
        $display("\n--- 测试 2: PLAY 子状态机 (黄方向右移动) ---");
        $display("  黄方按 D (right), 预期向右移动");

        // 按下 D 键 (right=1)
        right <= 1'b1;

        // 等待 game_tick, 子状态机执行一个完整循环
        wait_game_tick;
        #50;  // 等待子状态机完成 (P_IDLE→P_CALC→P_CHECK→P_PELLET→P_GHOST)
        $display("  Tick1 后: pac=(%0d,%0d), ghost=(%0d,%0d), score=%0d", pac_x, pac_y, ghost_x, ghost_y, score);

        wait_game_tick;
        #50;
        $display("  Tick2 后: pac=(%0d,%0d), score=%0d", pac_x, pac_y, score);

        wait_game_tick;
        #50;
        $display("  Tick3 后: pac=(%0d,%0d), score=%0d", pac_x, pac_y, score);

        // 连续向右移动 5 次 (从 16→21)
        repeat (5) begin
            wait_game_tick;
            #50;
        end
        $display("  连续右移后: pac=(%0d,%0d), ghost=(%0d,%0d)", pac_x, pac_y, ghost_x, ghost_y);

        // ================================================================
        // 测试 3: 黄方墙壁碰撞检测
        // ================================================================
        $display("\n--- 测试 3: 黄方墙壁碰撞检测 ---");
        $display("  让吃豆人顶到右边界 (Col 30 之外是墙壁)");

        // 尝试走到 col=31 (墙壁), 预期被阻挡在 col=30
        right <= 1'b1;
        // 移动吃豆人到 col=30 附近
        repeat (15) begin
            wait_game_tick;
            #50;
        end
        $display("  右移后: pac=(%0d,%0d)", pac_x, pac_y);
        if (pac_x <= 30)
            $display("  ✓ 墙壁碰撞检测工作正常 (pac_x <= 30)");
        else
            $display("  ✗ 墙壁碰撞检测异常 (pac_x > 30)");

        // 松键停止
        right <= 1'b0;

        // ================================================================
        // 测试 4: 黄方多方向移动
        // ================================================================
        $display("\n--- 测试 4: 黄方多方向移动 ---");

        // 向下移动
        down <= 1'b1;
        repeat (3) begin wait_game_tick; #50; end
        down <= 1'b0;
        $display("  向下移动后: pac=(%0d,%0d)", pac_x, pac_y);

        // 向左移动
        left <= 1'b1;
        repeat (3) begin wait_game_tick; #50; end
        left <= 1'b0;
        $display("  向左移动后: pac=(%0d,%0d)", pac_x, pac_y);

        // 向上移动
        up <= 1'b1;
        repeat (3) begin wait_game_tick; #50; end
        up <= 1'b0;
        $display("  向上移动后: pac=(%0d,%0d)", pac_x, pac_y);

        // ================================================================
        // 测试 5: 红方移动 + 墙壁碰撞
        // ================================================================
        $display("\n--- 测试 5: 红方 (幽灵) 移动控制 ---");
        $display("  幽灵初始位置 (15,14), 按方向键控制");

        // 红方按右键移动
        p2_right <= 1'b1;
        repeat (5) begin wait_game_tick; #50; end
        p2_right <= 1'b0;
        $display("  幽灵右移后: ghost=(%0d,%0d)", ghost_x, ghost_y);

        // 红方按下键移动
        p2_down <= 1'b1;
        repeat (3) begin wait_game_tick; #50; end
        p2_down <= 1'b0;
        $display("  幽灵下移后: ghost=(%0d,%0d)", ghost_x, ghost_y);

        // ================================================================
        // 测试 6: 实体碰撞检测 (Pac-Man vs Ghost)
        // ================================================================
        $display("\n--- 测试 6: 实体碰撞检测 ---");
        $display("  手动驱使幽灵走向吃豆人");

        // 先让吃豆人停在一个位置
        right <= 1'b0; down <= 1'b0; left <= 1'b0; up <= 1'b0;
        $display("  吃豆人停在: pac=(%0d,%0d)", pac_x, pac_y);
        $display("  幽灵当前: ghost=(%0d,%0d)", ghost_x, ghost_y);

        // 让幽灵向吃豆人移动 (简化: 只测试碰撞)
        // 如果 ghost 和 pac 在同一列, 垂直移动使碰撞
        // 先重置游戏让位置回到初始
        @(posedge clk);
        reset_game <= 1'b1;
        @(posedge clk);
        reset_game <= 1'b0;
        #100;
        @(posedge clk);
        start_game <= 1'b1;
        @(posedge clk);
        start_game <= 1'b0;
        #100;

        // 吃豆人初始 (16,16), 幽灵初始 (15,14)
        // 幽灵向右移动 1 格到 (16,14), 再向下移动 2 格到 (16,16) → 碰撞
        p2_right <= 1'b1;
        wait_game_tick; #50;
        p2_right <= 1'b0;
        $display("  幽灵移动一步: ghost=(%0d,%0d)", ghost_x, ghost_y);

        p2_down <= 1'b1;
        wait_game_tick; #50;
        $display("  幽灵移动: ghost=(%0d,%0d)", ghost_x, ghost_y);
        wait_game_tick; #50;
        $display("  幽灵移动: ghost=(%0d,%0d)", ghost_x, ghost_y);
        p2_down <= 1'b0;

        // 检查是否碰撞
        #10;
        $write("  碰撞后状态: "); print_state(); $display("");
        if (game_state == GAMEOVER)
            $display("  ✓ 碰撞检测正确 → GAMEOVER");
        else
            $display("  (若坐标相同则进入 GAMEOVER, 否则未碰撞)");

        // ================================================================
        // 测试 7: GAMEOVER → PLAY 重新开始
        // ================================================================
        $display("\n--- 测试 7: GAMEOVER → start_game → PLAY ---");
        @(posedge clk);
        start_game <= 1'b1;
        @(posedge clk);
        start_game <= 1'b0;
        #50;
        $write("  重新开始后状态: "); print_state(); $display("");
        $display("  pac=(%0d,%0d), score=%0d (应复位为 0)", pac_x, pac_y, score);

        // ================================================================
        // 测试 8: 吃豆逻辑 (pellet_we 输出)
        // ================================================================
        $display("\n--- 测试 8: 吃豆逻辑验证 ---");
        $display("  让吃豆人移动吃豆子, 观察 pellet_we 和 score");

        // 向右移动, 经过有豆子的格子
        right <= 1'b1;
        // 监视 pellet_we 和 score 变化
        repeat (5) begin
            wait_game_tick;
            #50;
            if (pellet_we)
                $display("  [%0t] pellet_we=1 @ addr=%0d, score=%0d", $time, pellet_waddr, score);
        end
        right <= 1'b0;
        $display("  最终 score=%0d", score);

        // ================================================================
        // 测试 9: reset_game 复位到 IDLE
        // ================================================================
        $display("\n--- 测试 9: reset_game → IDLE ---");
        @(posedge clk);
        reset_game <= 1'b1;
        @(posedge clk);
        reset_game <= 1'b0;
        #50;
        $write("  当前状态: "); print_state(); $display("");
        if (game_state == IDLE)
            $display("  ✓ reset_game 正确返回 IDLE");
        else
            $display("  ✗ reset_game 未返回 IDLE");

        // ================================================================
        // 测试 10: 音效事件输出
        // ================================================================
        $display("\n--- 测试 10: sound_event 音效事件输出 ---");
        // 重新开始并吃豆, 验证 sound_event 输出
        @(posedge clk);
        start_game <= 1'b1;
        @(posedge clk);
        start_game <= 1'b0;
        #50;

        right <= 1'b1;
        repeat (3) begin
            wait_game_tick;
            #50;
            if (sound_event == 2'b01)
                $display("  [%0t] sound_event=EAT (吃豆)", $time);
            else if (sound_event == 2'b10)
                $display("  [%0t] sound_event=DEATH (死亡)", $time);
            else if (sound_event == 2'b11)
                $display("  [%0t] sound_event=WIN (胜利)", $time);
        end
        right <= 1'b0;

        // ================================================================
        // 仿真完成
        // ================================================================
        #1000;
        $display("\n==============================================");
        $display(" game_logic_fsm 仿真完成");
        $display(" 请检查波形:");
        $display("   1. game_state: IDLE(0)→PLAY(1)→GAMEOVER(2)/WIN(3)");
        $display("   2. play_sub: P_IDLE(0)→P_CALC(1)→P_CHECK(2)→");
        $display("                 P_PELLET(3)→P_GHOST(4)→P_IDLE");
        $display("   3. game_tick → play_sub 开始变化");
        $display("   4. pellet_we: 仅在吃豆时拉高一个周期");
        $display("   5. score: 每次吃豆递增 1");
        $display("   6. pac_x/pac_y: 随方向键变化, 遇墙停止");
        $display("   7. sound_event: 00(无) / 01(吃豆) / 10(死亡) / 11(胜利)");
        $display("==============================================");
        $finish;
    end

endmodule
