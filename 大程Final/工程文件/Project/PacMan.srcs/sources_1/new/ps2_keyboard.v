//============================================================================
// ps2_keyboard.v — PS/2 键盘接口解码器
// 基于外设要求.md 提供的参考代码, 解码 Set 2 扫描码:
//   - 方向键 W/A/S/D:    W=1D, A=1C, S=1B, D=23
//   - 扩展方向键:        Up=E0 75, Down=E0 72, Left=E0 6B, Right=E0 74
//   - Enter: 5A (用于开始游戏)
//   - ESC:   76 (用于复位)
//
// 输出 up/down/left/right 为持续电平 (按下为1, 松开为0)
// 输出 start_game / reset_game 为单周期脉冲
//============================================================================

module ps2_keyboard (
    input  clk,                // 100MHz 系统时钟
    input  rst,
    input  ps2_clk,            // PS/2 时钟线
    input  ps2_data,           // PS/2 数据线
    output reg up,             // W (黄)
    output reg down,           // S (黄)
    output reg left,           // A (黄)
    output reg right,          // D (黄)
    output reg p2_up,          // 上箭头 (红)
    output reg p2_down,        // 下箭头 (红)
    output reg p2_left,        // 左箭头 (红)
    output reg p2_right,       // 右箭头 (红)
    output reg start_game,     // Enter 键脉冲
    output reg reset_game      // ESC 键脉冲
);

    // ---- PS/2 时钟下降沿检测 (三级同步 + 边沿检测) ----
    reg ps2_clk_sync0, ps2_clk_sync1, ps2_clk_sync2;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ps2_clk_sync0 <= 1'b0;
            ps2_clk_sync1 <= 1'b0;
            ps2_clk_sync2 <= 1'b0;
        end else begin
            ps2_clk_sync0 <= ps2_clk;
            ps2_clk_sync1 <= ps2_clk_sync0;
            ps2_clk_sync2 <= ps2_clk_sync1;
        end
    end
    wire negedge_ps2_clk = !ps2_clk_sync1 && ps2_clk_sync2;
    reg negedge_ps2_clk_shift;
    always @(posedge clk) begin
        negedge_ps2_clk_shift <= negedge_ps2_clk;
    end

    // ---- 位计数器 (0~10, 共11位) ----
    reg [3:0] bit_count;
    always @(posedge clk or posedge rst) begin
        if (rst)
            bit_count <= 4'd0;
        else if (negedge_ps2_clk_shift) begin
            if (bit_count >= 4'd10)
                bit_count <= 4'd0;     // 一帧结束
            else
                bit_count <= bit_count + 4'd1;
        end
    end

    // ---- 11位帧缓冲区 ----
    reg [10:0] frame_buffer;
    always @(posedge clk or posedge rst) begin
        if (rst)
            frame_buffer <= 11'd0;
        else if (negedge_ps2_clk_shift)
            frame_buffer[bit_count] <= ps2_data;
    end

    // ---- 帧接收完成信号 ----
    reg frame_ready;
    always @(posedge clk or posedge rst) begin
        if (rst)
            frame_ready <= 1'b0;
        else if (negedge_ps2_clk_shift && bit_count == 4'd10)
            frame_ready <= 1'b1;
        else
            frame_ready <= 1'b0;
    end

    // ---- 扫描码解析 ----
    // 状态: 等待普通码 / 等待 E0 后的扩展码 / 等待 F0 后的 Break 码 / 等待 E0 F0 后的扩展 Break 码
    reg        waiting_e0;       // 已收到 E0
    reg        waiting_f0;       // 已收到 F0
    reg        extended_key;     // 当前键为扩展键 (E0 前缀)

    wire [7:0] scan_code = frame_buffer[8:1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            up          <= 1'b0;
            down        <= 1'b0;
            left        <= 1'b0;
            right       <= 1'b0;
            p2_up       <= 1'b0;
            p2_down     <= 1'b0;
            p2_left     <= 1'b0;
            p2_right    <= 1'b0;
            start_game  <= 1'b0;
            reset_game  <= 1'b0;
            waiting_e0  <= 1'b0;
            waiting_f0  <= 1'b0;
            extended_key <= 1'b0;
        end else begin
            // 默认清除脉冲信号
            start_game <= 1'b0;
            reset_game <= 1'b0;

            if (frame_ready) begin
                if (waiting_f0) begin
                    // ---- Break 码: 按键松开 ----
                    waiting_f0 <= 1'b0;
                    extended_key <= 1'b0;

                    // 处理扩展 Break 码 (E0 F0 XX)
                    if (extended_key) begin
                        case (scan_code)
                            8'h75: p2_up    <= 1'b0;   // 上箭头松开
                            8'h72: p2_down  <= 1'b0;   // 下箭头松开
                            8'h6B: p2_left  <= 1'b0;   // 左箭头松开
                            8'h74: p2_right <= 1'b0;   // 右箭头松开
                        endcase
                    end else begin
                        // 普通键松开
                        case (scan_code)
                            8'h1D: up    <= 1'b0;   // W 松开 → 上
                            8'h1C: left  <= 1'b0;   // A 松开 → 左
                            8'h1B: down  <= 1'b0;   // S 松开 → 下
                            8'h23: right <= 1'b0;   // D 松开 → 右
                        endcase
                    end
                end else if (waiting_e0) begin
                    // ---- 扩展键 Make 码 (E0 XX) ----
                    waiting_e0 <= 1'b0;

                    if (scan_code == 8'hF0) begin
                        // E0 F0 → 扩展 Break 码
                        waiting_f0 <= 1'b1;
                        extended_key <= 1'b1;
                    end else begin
                        case (scan_code)
                            8'h75: p2_up    <= 1'b1;   // 上箭头按下
                            8'h72: p2_down  <= 1'b1;   // 下箭头按下
                            8'h6B: p2_left  <= 1'b1;   // 左箭头按下
                            8'h74: p2_right <= 1'b1;   // 右箭头按下
                        endcase
                    end
                end else begin
                    // ---- 普通键扫描码 ----
                    case (scan_code)
                        8'hE0: begin
                            waiting_e0 <= 1'b1;      // 扩展键前缀
                        end
                        8'hF0: begin
                            waiting_f0 <= 1'b1;      // Break 码前缀
                        end
                        // WASD Make 码
                        8'h1D: up    <= 1'b1;        // W
                        8'h1C: left  <= 1'b1;        // A
                        8'h1B: down  <= 1'b1;        // S
                        8'h23: right <= 1'b1;        // D
                        // 特殊功能键
                        8'h5A: start_game <= 1'b1;   // Enter → 脉冲
                        8'h76: reset_game <= 1'b1;   // ESC → 脉冲
                    endcase
                end
            end
        end
    end

endmodule
