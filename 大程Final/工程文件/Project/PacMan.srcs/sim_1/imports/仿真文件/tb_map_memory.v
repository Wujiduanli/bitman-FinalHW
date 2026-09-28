//============================================================================
// tb_map_memory.v — map_memory 模块功能仿真测试平台
//============================================================================
// 仿真目标 (对应 README_仿真说明.md 第2节):
//   1. 验证 MAP ROM 上电初始化 — 迷宫布局正确 (墙壁/通道/幽灵房/出生点)
//   2. 验证 PELLET RAM 上电初始化 — 仅空地/出生点有豆子, 墙壁/幽灵房无豆子
//   3. 验证双端口同时读取 — Port A (VGA) 和 Port B (游戏逻辑) 可独立读取
//   4. 验证同步写入 (吃豆) — pellet_we=1 时清除指定位置豆子
//   5. 验证豆子初始化 (pellet_init) — 全局恢复所有豆子 + pellet_total 计数
//   6. 验证写入优先级 — init_active 期间 pellet_we 与 init 地址冲突时 pellet_we 优先
//
// 波形分析要点:
//   - ROM/RAM 读为组合逻辑: addr 变化后, map_type 和 pellet 立即更新
//   - pellet_we=1 时, pellet_ram[addr_b] 在下一个时钟上升沿更新 (同步写)
//   - pellet_init 的初始化扫描 768 个周期, init_addr 从 0 到 767
//============================================================================

`timescale 1ns / 1ps

module tb_map_memory;

    // ======== 信号声明 ========
    reg         clk;
    reg         rst;

    // Port A (VGA 读)
    reg  [9:0]  addr_a;
    wire [1:0]  map_type_a;
    wire        pellet_a;

    // Port B (游戏逻辑)
    reg  [9:0]  addr_b;
    wire [1:0]  map_type_b;
    wire        pellet_b;
    reg         pellet_we;
    reg         pellet_din;
    reg         pellet_init;

    wire [9:0]  pellet_total;

    // ======== 测试变量 ========
    integer     pass_cnt, fail_cnt;
    integer     i;
    reg [9:0]   conflict_addr;
    reg [4:0]   conflict_row, conflict_col;

    // ======== 被测模块实例化 ========
    map_memory uut (
        .clk          (clk),
        .rst          (rst),
        .addr_a       (addr_a),
        .map_type_a   (map_type_a),
        .pellet_a     (pellet_a),
        .addr_b       (addr_b),
        .map_type_b   (map_type_b),
        .pellet_b     (pellet_b),
        .pellet_we    (pellet_we),
        .pellet_din   (pellet_din),
        .pellet_init  (pellet_init),
        .pellet_total (pellet_total)
    );

    // ======== 100MHz 时钟生成 ========
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ======== 辅助函数 ========
    // 将 row, col 转换为地址 {row[4:0], col[4:0]}
    function [9:0] addr_of;
        input [4:0] row, col;
        begin
            addr_of = {row, col};
        end
    endfunction

    // ======== 辅助任务 ========
    // 验证指定网格的 map_type 和 pellet 是否符合预期
    task verify_grid;
        input [4:0] row, col;
        input [1:0] exp_type;    // 期望的地图类型
        input       exp_pellet;  // 期望的豆子状态
        input [8*32:0] desc;     // 描述
        begin
            addr_a = {row, col};
            #1;  // 组合逻辑稳定
            if (map_type_a === exp_type && pellet_a === exp_pellet) begin
                $display("  ✓ Grid(%0d,%0d) %s: map=%0d pellet=%0d",
                         row, col, desc, map_type_a, pellet_a);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  ✗ Grid(%0d,%0d) %s: map=%0d (期望%0d) pellet=%0d (期望%0d)",
                         row, col, desc, map_type_a, exp_type, pellet_a, exp_pellet);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // 吃豆: 清除指定位置的豆子
    task eat_pellet;
        input [4:0] row, col;
        begin
            @(posedge clk);
            pellet_we  <= 1'b1;
            pellet_din <= 1'b0;
            addr_b     <= {row, col};
            @(posedge clk);
            pellet_we  <= 1'b0;
        end
    endtask

    // ======== 仿真主流程 ========
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        $display("==============================================");
        $display(" map_memory 模块功能仿真");
        $display("==============================================");
        $display(" 测试项:");
        $display("   1. ROM 上电初始化 — 迷宫布局");
        $display("   2. RAM 上电初始化 — 豆子分布");
        $display("   3. 双端口独立读取");
        $display("   4. 同步写入 (吃豆)");
        $display("   5. pellet_init 全局豆子恢复");
        $display("   6. 写入优先级 (pellet_we > init 同地址冲突)");
        $display("==============================================");

        // ---- 初始化 ----
        rst        = 1'b1;
        addr_a     = 10'd0;
        addr_b     = 10'd0;
        pellet_we  = 1'b0;
        pellet_din = 1'b0;
        pellet_init = 1'b0;
        #50;
        rst = 1'b0;
        #20;
        $display("[%0t] 复位释放, ROM/RAM 已在 initial 块中完成初始化...", $time);
        #100;

        // ================================================================
        // 测试 1: ROM 上电初始化 — 验证迷宫布局
        // ================================================================
        $display("\n--- 测试 1: MAP ROM 迷宫布局验证 ---");

        // 外圈墙壁 — 第 0 行和第 23 行
        $display("  外圈墙壁:");
        verify_grid(5'd0,  5'd0,  2'b01, 1'b0, "左上角");
        verify_grid(5'd0,  5'd15, 2'b01, 1'b0, "顶部中间");
        verify_grid(5'd0,  5'd31, 2'b01, 1'b0, "右上角");
        verify_grid(5'd23, 5'd0,  2'b01, 1'b0, "左下角");
        verify_grid(5'd23, 5'd15, 2'b01, 1'b0, "底部中间");
        verify_grid(5'd23, 5'd31, 2'b01, 1'b0, "右下角");

        // 通道 — Row 1, Col 1-30
        $display("  通道:");
        verify_grid(5'd1, 5'd1,  2'b00, 1'b1, "内部通道");
        verify_grid(5'd1, 5'd15, 2'b00, 1'b1, "通道中间");
        verify_grid(5'd1, 5'd30, 2'b00, 1'b1, "通道右边缘");

        // 幽灵房 — Row 13, Col 13-18
        $display("  幽灵房:");
        verify_grid(5'd13, 5'd13, 2'b10, 1'b0, "幽灵房左上");
        verify_grid(5'd13, 5'd15, 2'b10, 1'b0, "幽灵房中间");
        verify_grid(5'd13, 5'd18, 2'b10, 1'b0, "幽灵房右上");

        // 幽灵房墙壁 — Row 12, Col 12-19
        $display("  幽灵房墙壁:");
        verify_grid(5'd12, 5'd13, 2'b01, 1'b0, "幽灵房上方墙壁");
        verify_grid(5'd12, 5'd18, 2'b01, 1'b0, "幽灵房上方墙壁右");

        // 幽灵房门 — Row 12, Col 15-16
        $display("  幽灵房门:");
        verify_grid(5'd12, 5'd15, 2'b00, 1'b0, "房门左");
        verify_grid(5'd12, 5'd16, 2'b00, 1'b0, "房门右");

        // 吃豆人出生点 — Row 16, Col 16
        $display("  出生点:");
        verify_grid(5'd16, 5'd16, 2'b11, 1'b1, "吃豆人出生点");

        // 边缘竖直通道 — Col 1 和 Col 30
        $display("  边缘竖直通道:");
        verify_grid(5'd5, 5'd1,  2'b00, 1'b1, "左边缘通道");
        verify_grid(5'd5, 5'd30, 2'b00, 1'b1, "右边缘通道");

        // ================================================================
        // 测试 2: PELLET RAM 豆子分布
        // ================================================================
        $display("\n--- 测试 2: PELLET RAM 豆子分布验证 ---");

        $display("  通道位置应有豆子:");
        verify_grid(5'd1, 5'd1,  2'b00, 1'b1, "通道(1,1)");
        verify_grid(5'd4, 5'd10, 2'b00, 1'b1, "通道(4,10)");

        $display("  墙壁位置应无豆子:");
        verify_grid(5'd0, 5'd0,  2'b01, 1'b0, "墙壁(0,0)");
        verify_grid(5'd23, 5'd15, 2'b01, 1'b0, "墙壁(23,15)");

        $display("  幽灵房应无豆子:");
        verify_grid(5'd13, 5'd15, 2'b10, 1'b0, "幽灵房(13,15)");

        $display("  出生点应有豆子:");
        verify_grid(5'd16, 5'd16, 2'b11, 1'b1, "出生点(16,16)");

        // ================================================================
        // 测试 3: 双端口独立读取
        // ================================================================
        $display("\n--- 测试 3: 双端口独立读取 ---");

        // 不同地址
        addr_a = {5'd1, 5'd1};
        addr_b = {5'd13, 5'd15};
        #5;
        if (map_type_a === 2'b00 && pellet_a === 1'b1) begin
            $display("  ✓ Port A → Grid(1,1):  map=%0d pellet=%0d", map_type_a, pellet_a);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ Port A → Grid(1,1): 异常 (map=%0d pellet=%0d)", map_type_a, pellet_a);
            fail_cnt = fail_cnt + 1;
        end
        if (map_type_b === 2'b10 && pellet_b === 1'b0) begin
            $display("  ✓ Port B → Grid(13,15): map=%0d pellet=%0d", map_type_b, pellet_b);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ Port B → Grid(13,15): 异常 (map=%0d pellet=%0d)", map_type_b, pellet_b);
            fail_cnt = fail_cnt + 1;
        end

        // 同一地址
        addr_a = {5'd16, 5'd16};
        addr_b = {5'd16, 5'd16};
        #5;
        if (map_type_a === map_type_b && pellet_a === pellet_b &&
            map_type_a === 2'b11 && pellet_a === 1'b1) begin
            $display("  ✓ 双端口同地址 Grid(16,16): 数据一致 map=%0d pellet=%0d",
                     map_type_a, pellet_a);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ 双端口同地址 异常: A(map=%0d p=%0d) B(map=%0d p=%0d)",
                     map_type_a, pellet_a, map_type_b, pellet_b);
            fail_cnt = fail_cnt + 1;
        end

        // ================================================================
        // 测试 4: 同步写入 (吃豆)
        // ================================================================
        $display("\n--- 测试 4: 同步写入 (吃豆) ---");

        // 先确认出生点有豆子
        addr_b = {5'd16, 5'd16};
        #5;
        $display("  吃豆前: Grid(16,16) pellet=%0d", pellet_b);

        // 执行吃豆
        eat_pellet(5'd16, 5'd16);

        // 验证豆子已被清除
        #5;
        if (pellet_b === 1'b0) begin
            $display("  ✓ 吃豆后: Grid(16,16) pellet=%0d", pellet_b);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  ✗ 吃豆后: Grid(16,16) pellet=%0d (期望 0)", pellet_b);
            fail_cnt = fail_cnt + 1;
        end

        // 多吃几个豆子
        eat_pellet(5'd1, 5'd1);
        eat_pellet(5'd1, 5'd5);
        eat_pellet(5'd4, 5'd15);

        // 验证被吃豆子
        $display("  验证被吃豆子 (应为 0):");
        verify_grid(5'd1, 5'd1,  2'b00, 1'b0, "被吃(1,1)");
        verify_grid(5'd1, 5'd5,  2'b00, 1'b0, "被吃(1,5)");
        verify_grid(5'd4, 5'd15, 2'b00, 1'b0, "被吃(4,15)");

        // 验证未被吃的豆子仍然存在
        $display("  验证未吃豆子 (应为 1):");
        verify_grid(5'd9, 5'd10, 2'b00, 1'b1, "未吃(9,10)");

        // ================================================================
        // 测试 5: pellet_init 全局豆子恢复
        // ================================================================
        $display("\n--- 测试 5: pellet_init 全局豆子恢复 ---");

        // 发出 pellet_init 脉冲 (单周期)
        @(posedge clk);
        pellet_init <= 1'b1;
        $display("[%0t] 发出 pellet_init 脉冲", $time);
        @(posedge clk);
        pellet_init <= 1'b0;

        // 等待初始化完成 (768 cycles × 10ns = 7.68μs, 等待 8μs)
        $display("  等待豆子初始化完成 (768 cycles)...");
        #8000;

        // 检查 pellet_total
        #10;
        $display("  pellet_total = %0d (豆子总数)", pellet_total);

        // 验证之前被吃掉的豆子已恢复
        $display("  验证豆子已恢复 (应为 1):");
        verify_grid(5'd16, 5'd16, 2'b11, 1'b1, "出生点(16,16)");
        verify_grid(5'd1, 5'd1,  2'b00, 1'b1, "通道(1,1)");
        verify_grid(5'd4, 5'd15, 2'b00, 1'b1, "通道(4,15)");

        // ================================================================
        // 测试 6: 写入优先级 (pellet_we > init 同地址冲突)
        // ================================================================
        // 优先级验证原理:
        //   init_active 期间, init_addr 从 0 扫描到 767.
        //   若 pellet_we=1 且 addr_b == init_addr:
        //     条件 !pellet_we || (init_addr != addr_b) 为 FALSE
        //     → init 跳过该地址, pellet_we 的写入优先.
        //
        // 测试方法:
        //   1. 触发 pellet_init, init_addr 从 0 开始递增
        //   2. 等待 N 个周期后 (此时 init_addr ≈ N),
        //      在同周期精确发出 pellet_we 指向 addr_b = N,
        //      确保 init_addr == addr_b 且 pellet_we=1.
        //   3. 等待 init 完成, 验证该地址的豆子未被恢复 (pellet=0).
        $display("\n--- 测试 6: 写入优先级验证 ---");

        // 选择目标地址: addr = {5'd4, 5'd10} = 4*32 + 10 = 138
        // init 从地址 0 开始, 在触发后第 (138+1)=139 个周期处理地址 138
        // 我们在第 139 个周期同时发出 pellet_we 指向同一地址
        begin
            conflict_row = 5'd4;
            conflict_col = 5'd10;
            conflict_addr = {conflict_row, conflict_col};  // = 138

            // 触发 pellet_init
            @(posedge clk);
            pellet_init <= 1'b1;
            @(posedge clk);
            pellet_init <= 1'b0;

            // init_state 在第2个周期开始处理 init_addr=0
            // 第3个周期: init_addr=1
            // ...
            // 第 139 个周期: init_addr=138 ← 在这里冲突!
            // 所以从触发后等待 139-2+1 = 138 个周期
            //   (触发占1个周期, 处理从地址0开始是第2个周期)
            //
            // 实际上: 触发后第1个周期 → init 处理地址 0
            //         触发后第 k 个周期 → init 处理地址 k-1
            // 所以处理地址 138 是在触发后第 139 个周期
            // 前138个周期已经过去(触发时用了1个周期),
            // 需要再等待 138-1 = 137 个周期
            repeat (137) @(posedge clk);

            // 此时 init_addr 即将处理地址 138,
            // 在同一周期发出 pellet_we 指向同一地址
            pellet_we  <= 1'b1;
            pellet_din <= 1'b0;
            addr_b     <= conflict_addr;
            $display("[%0t] 冲突周期: init_addr≈%0d, addr_b=%0d, pellet_we=1",
                     $time, conflict_addr, conflict_addr);

            @(posedge clk);
            pellet_we <= 1'b0;

            // 等待 init 完成 (剩余约 768-138 = 630 周期 ≈ 6.3μs)
            #6500;

            // 验证: 冲突地址的豆子应保持为 0 (pellet_we 优先)
            verify_grid(conflict_row, conflict_col, 2'b00, 1'b0, "冲突地址(4,10)-pellet_we优先");

            // 其他位置的豆子应被恢复
            verify_grid(5'd16, 5'd16, 2'b11, 1'b1, "出生点-已恢复");
            verify_grid(5'd1, 5'd1,  2'b00, 1'b1, "通道(1,1)-已恢复");
        end

        // ================================================================
        // 仿真总结
        // ================================================================
        #100;
        $display("\n==============================================");
        $display(" map_memory 仿真完成");
        $display(" 通过: %0d / 失败: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" 结果: 全部测试通过 ✓");
        else
            $display(" 结果: 存在 %0d 项失败 ✗", fail_cnt);
        $display("==============================================");
        $display(" 波形检查清单:");
        $display("   1. ROM 组合逻辑读取: addr 变化 → map_type/pellet 立即更新");
        $display("   2. RAM 同步写入: 数据在时钟上升沿后更新");
        $display("   3. pellet_init 状态机: init_addr 从 0 遍历到 767");
        $display("   4. init_active 完成初始化后自动清除");
        $display("   5. pellet_total 在初始化完成后保持最终计数值");
        $display("==============================================");

        #1000;
        $finish;
    end

endmodule
