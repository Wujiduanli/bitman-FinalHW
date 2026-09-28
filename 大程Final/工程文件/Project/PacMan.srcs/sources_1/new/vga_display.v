//============================================================================
// vga_display.v — VGA 显示驱动 (640x480 @ 60Hz)  修订版v2
// 使用计数器方法跟踪网格坐标 (避免除法器, 优化时序)
//
// 时序: Sync=96, Back=48, Active=640, Front=16 → Total=800
//        Sync=2,  Back=33, Active=480, Front=10 → Total=525
//
// 图层: 墙壁(蓝) → 豆子(白点) → 吃豆人(黄) → 幽灵(红)
//============================================================================

module vga_display (
    input  clk_vga,            // 25MHz 像素时钟
    input  rst,                // 异步复位 (高有效)

    // ---- 地图读取 ----
    output reg [9:0] map_addr,  // 网格地址 = {grid_row[4:0], grid_col[4:0]}
    input  [1:0] map_type,     // 地图类型 (组合逻辑, 来自 map_memory)
    input  pellet,             // 豆子状态 (组合逻辑)

    // ---- 游戏状态 ----
    input  [4:0] pac_x,        // 吃豆人网格X
    input  [4:0] pac_y,        // 吃豆人网格Y
    input  [4:0] ghost_x,      // 幽灵网格X
    input  [4:0] ghost_y,      // 幽灵网格Y
    input  [1:0] game_state,   // 00=IDLE, 01=PLAY, 10=GAMEOVER, 11=WIN

    // ---- VGA 输出 ----
    output reg [3:0] VGA_R,
    output reg [3:0] VGA_G,
    output reg [3:0] VGA_B,
    output HSYNC,
    output VSYNC
);

    // ======== 时序常量 ========
    parameter H_ACTIVE = 640;
    parameter H_FRONT  = 16;
    parameter H_SYNC   = 96;
    parameter H_BACK   = 48;
    parameter H_TOTAL  = 800;

    parameter V_ACTIVE = 480;
    parameter V_FRONT  = 10;
    parameter V_SYNC   = 2;
    parameter V_BACK   = 33;
    parameter V_TOTAL  = 525;

    parameter GRID_SZ  = 20;   // 每格像素 (640/32=20, 480/24=20)

    // ======== 跨时钟域同步器 (100MHz域 → 25MHz VGA域) ========
    // 游戏坐标和状态信号变化很慢 (~10Hz), 2-FF 同步足够安全
    reg [4:0] pac_x_s1,   pac_x_s2;
    reg [4:0] pac_y_s1,   pac_y_s2;
    reg [4:0] ghost_x_s1, ghost_x_s2;
    reg [4:0] ghost_y_s1, ghost_y_s2;
    reg [1:0] gs_s1,      gs_s2;

    always @(posedge clk_vga) begin
        pac_x_s1   <= pac_x;
        pac_x_s2   <= pac_x_s1;
        pac_y_s1   <= pac_y;
        pac_y_s2   <= pac_y_s1;
        ghost_x_s1 <= ghost_x;
        ghost_x_s2 <= ghost_x_s1;
        ghost_y_s1 <= ghost_y;
        ghost_y_s2 <= ghost_y_s1;
        gs_s1      <= game_state;
        gs_s2      <= gs_s1;
    end

    wire [4:0] pac_x_s   = pac_x_s2;
    wire [4:0] pac_y_s   = pac_y_s2;
    wire [4:0] ghost_x_s = ghost_x_s2;
    wire [4:0] ghost_y_s = ghost_y_s2;
    wire [1:0] game_state_s = gs_s2;

    // ======== 行列计数器 ========
    reg [9:0] h_cnt;       // 0~799
    reg [9:0] v_cnt;       // 0~524

    always @(posedge clk_vga or posedge rst) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == V_TOTAL - 1) ? 10'd0 : v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // ======== 同步信号 ========
    assign HSYNC = (h_cnt >= (H_ACTIVE + H_FRONT) &&
                    h_cnt <  (H_ACTIVE + H_FRONT + H_SYNC)) ? 1'b0 : 1'b1;
    assign VSYNC = (v_cnt >= (V_ACTIVE + V_FRONT) &&
                    v_cnt <  (V_ACTIVE + V_FRONT + V_SYNC)) ? 1'b0 : 1'b1;

    // 有效显示区域
    wire active = (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

    // ======== 网格坐标追踪 (计数器方式, 避免除法器) ========
    reg [4:0] grid_col;     // 当前列 0~31
    reg [4:0] grid_row;     // 当前行 0~23
    reg [4:0] sub_x;        // 格内X偏移 0~19
    reg [4:0] sub_y;        // 格内Y偏移 0~19

    always @(posedge clk_vga or posedge rst) begin
        if (rst) begin
            grid_col <= 5'd0;
            grid_row <= 5'd0;
            sub_x    <= 5'd0;
            sub_y    <= 5'd0;
        end else begin
            // ---- 水平方向 ----
            if (h_cnt == 0) begin
                grid_col <= 5'd0;
                sub_x    <= 5'd0;
            end else if (active) begin
                if (sub_x == GRID_SZ - 1) begin
                    sub_x    <= 5'd0;
                    grid_col <= (grid_col == 5'd31) ? 5'd0 : grid_col + 5'd1;
                end else begin
                    sub_x <= sub_x + 5'd1;
                end
            end

            // ---- 垂直方向 ----
            if (v_cnt == 0 && h_cnt == 0) begin
                grid_row <= 5'd0;
                sub_y    <= 5'd0;
            end else if (h_cnt == H_TOTAL - 1) begin
                // 注意: h_cnt=799时 active=0, 只能用 v_cnt 判断
                if (v_cnt < V_ACTIVE) begin
                    if (sub_y == GRID_SZ - 1) begin
                        sub_y    <= 5'd0;
                        grid_row <= (grid_row == 5'd23) ? 5'd0 : grid_row + 5'd1;
                    end else begin
                        sub_y <= sub_y + 5'd1;
                    end
                end
            end
        end
    end

    // ---- 地图地址 ----
    always @(posedge clk_vga) begin
        // 提前一周期计算: 下一像素的网格地址
        // 下一像素的 grid_col/row
        if (h_cnt == H_TOTAL - 1 && v_cnt == V_TOTAL - 1) begin
            map_addr <= {grid_row, grid_col};   // 将回绕
        end else begin
            // 由 grid_col/row 当前值给出地址 (已提前更新)
            map_addr <= {grid_row, grid_col};
        end
    end

    // ======== 颜色计算 (流水线: 在当前像素输出前一周期计算的颜色) ========
    // 简化: 直接使用当前 map_type/pellet 和当前坐标
    // 图层优先级: 墙壁背景 < 豆子 < 吃豆人 < 幽灵 < UI叠加

    wire is_pac   = (grid_col == pac_x_s)   && (grid_row == pac_y_s);
    wire is_ghost = (grid_col == ghost_x_s) && (grid_row == ghost_y_s);

    // 包围盒 (16×16 方块, 在20×20格子内)
    wire in_box = (sub_x >= 5'd2 && sub_x < 5'd18) &&
                  (sub_y >= 5'd2 && sub_y < 5'd18);

    // 豆子绘图 (4×4小白点居中)
    wire in_dot = (sub_x >= 5'd8 && sub_x < 5'd12) &&
                  (sub_y >= 5'd8 && sub_y < 5'd12);

    // ======== IDLE 画面 "ENTER" 文字图案 (5x7字体, 2x缩放) ========
    wire [4:0] tcol = (h_cnt >= 250 && h_cnt < 300) ? ((h_cnt - 250) >> 1) : 5'd0;
    wire [2:0] trow = (v_cnt >= 280 && v_cnt < 294) ? ((v_cnt - 280) >> 1) : 3'd0;
    wire text_in_area = (h_cnt >= 250 && h_cnt < 300) && (v_cnt >= 280 && v_cnt < 294);

    // 7行 × 25列 点阵 (E-N-T-E-R, 每字母5列, 无间隙)
    reg [24:0] text_pat;
    always @(*) begin
        case (trow)
            3'd0: text_pat = 25'b11111_10001_11111_11111_11110;  // E N T E R row0
            3'd1: text_pat = 25'b10000_11001_00100_10000_10001;
            3'd2: text_pat = 25'b10000_10101_00100_10000_10001;
            3'd3: text_pat = 25'b11111_10011_00100_11111_11110;
            3'd4: text_pat = 25'b10000_10001_00100_10000_10100;
            3'd5: text_pat = 25'b10000_10001_00100_10000_10010;
            3'd6: text_pat = 25'b11111_10001_00100_11111_10001;
            default: text_pat = 25'd0;
        endcase
    end
    wire text_bit = text_in_area && (tcol < 25) && text_pat[24 - tcol];

    // ======== WIN 画面 "WIN!" 文字图案 (5x7字体, 2x缩放) ========
    wire [4:0] wtcol = (h_cnt >= 290 && h_cnt < 330) ? ((h_cnt - 290) >> 1) : 5'd0;
    wire [2:0] wtrow = (v_cnt >= 230 && v_cnt < 244) ? ((v_cnt - 230) >> 1) : 3'd0;
    wire win_text_in = (h_cnt >= 290 && h_cnt < 330) && (v_cnt >= 230 && v_cnt < 244);

    // 7行 × 20列 点阵 (W-I-N-!, 每字母5列)
    reg [19:0] win_pat;
    always @(*) begin
        case (wtrow)
            3'd0: win_pat = 20'b10001_01110_10001_00100;
            3'd1: win_pat = 20'b10001_00100_11001_00100;
            3'd2: win_pat = 20'b10001_00100_10101_00100;
            3'd3: win_pat = 20'b10101_00100_10011_00100;
            3'd4: win_pat = 20'b11011_00100_10001_00100;
            3'd5: win_pat = 20'b10001_00100_10001_00000;
            3'd6: win_pat = 20'b10001_01110_10001_00100;
            default: win_pat = 20'd0;
        endcase
    end
    wire win_bit = win_text_in && (wtcol < 20) && win_pat[19 - wtcol];

    always @(posedge clk_vga) begin
        if (!active) begin
            VGA_R <= 4'd0;
            VGA_G <= 4'd0;
            VGA_B <= 4'd0;
        end else if (game_state_s == 2'b00) begin
            // ==================== IDLE: 黑底 + 绿框 + 黄色Pac-Man图标 ====================
            VGA_R <= 4'd0;
            VGA_G <= 4'd0;
            VGA_B <= 4'd0;

            // 绿框
            if ((h_cnt >= 200 && h_cnt < 440) &&
                (v_cnt >= 170 && v_cnt < 310)) begin
                if ((h_cnt >= 200 && h_cnt < 208) ||
                    (h_cnt >= 432 && h_cnt < 440) ||
                    (v_cnt >= 170 && v_cnt < 178) ||
                    (v_cnt >= 302 && v_cnt < 310)) begin
                    VGA_R <= 4'd0;
                    VGA_G <= 4'd15;
                    VGA_B <= 4'd0;
                end
            end

            // 黄色吃豆人图标 (框内中心: h=290~350, v=210~270)
            if ((h_cnt >= 290 && h_cnt < 350) &&
                (v_cnt >= 210 && v_cnt < 270)) begin
                // 圆形 Pac-Man (半径~28像素, 带开口)
                if (((h_cnt - 320) * (h_cnt - 320) + (v_cnt - 240) * (v_cnt - 240)) < 784) begin
                    if (!((h_cnt > 320) && (v_cnt < 240) &&
                          ((v_cnt - 240) > -(h_cnt - 320)))) begin
                        VGA_R <= 4'd15;
                        VGA_G <= 4'd15;
                        VGA_B <= 4'd0;
                    end
                end
            end

            // "ENTER" 白色文字
            if (text_bit) begin
                VGA_R <= 4'd15;
                VGA_G <= 4'd15;
                VGA_B <= 4'd15;
            end

        end else begin
            // ============ PLAY / GAMEOVER / WIN: 游戏画面 ============
            // 默认背景: 黑色
            VGA_R <= 4'd0;
            VGA_G <= 4'd0;
            VGA_B <= 4'd0;

            // ---- 墙壁 (蓝色) ----
            if (map_type == 2'b01) begin
                VGA_R <= 4'd0;
                VGA_G <= 4'd0;
                VGA_B <= 4'd10;
            end

            // ---- 豆子 (白色小点) ----
            if ((map_type == 2'b00 || map_type == 2'b11) && pellet && in_dot) begin
                VGA_R <= 4'd15;
                VGA_G <= 4'd15;
                VGA_B <= 4'd15;
            end

            // ---- 幽灵房地板 (深灰) ----
            if (map_type == 2'b10) begin
                VGA_R <= 4'd3;
                VGA_G <= 4'd3;
                VGA_B <= 4'd3;
            end

            // ---- 吃豆人 (黄色) ----
            if (is_pac && in_box) begin
                VGA_R <= 4'd15;
                VGA_G <= 4'd15;
                VGA_B <= 4'd0;
            end

            // ---- 幽灵 (红色, GAMEOVER时变白) ----
            if (is_ghost && in_box) begin
                if (game_state_s == 2'b10) begin
                    VGA_R <= 4'd15;
                    VGA_G <= 4'd15;
                    VGA_B <= 4'd15;
                end else begin
                    VGA_R <= 4'd15;
                    VGA_G <= 4'd3;
                    VGA_B <= 4'd3;
                end
            end

            // ---- WIN 叠加金色框 + "WIN!" 文字 ----
            if (game_state_s == 2'b11) begin
                // 金色边框
                if ((h_cnt >= 170 && h_cnt < 470) &&
                    (v_cnt >= 150 && v_cnt < 330)) begin
                    if ((h_cnt >= 170 && h_cnt < 178) ||
                        (h_cnt >= 462 && h_cnt < 470) ||
                        (v_cnt >= 150 && v_cnt < 158) ||
                        (v_cnt >= 322 && v_cnt < 330)) begin
                        VGA_R <= 4'd15;
                        VGA_G <= 4'd15;
                        VGA_B <= 4'd0;
                    end
                end
                // "WIN!" 白色文字 (框内居中)
                if (win_bit) begin
                    VGA_R <= 4'd15;
                    VGA_G <= 4'd15;
                    VGA_B <= 4'd15;
                end
            end
        end
    end

endmodule