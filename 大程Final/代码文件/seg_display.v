//============================================================================
// seg_display.v — 七段数码管显示驱动 (Arduino 子板)
// 将二进制分数转换为 BCD, 驱动 4 位共阳数码管动态扫描
//   - 共阳: AN[x]=0 选中该位, SEGMENT 低电平点亮
//   - 4 位显示: 支持 0~9999 分数范围
//============================================================================

module seg_display (
    input  clk,                // 系统时钟 (100MHz)
    input  clk_scan,           // 扫描时钟 (~1kHz)
    input  rst,
    input  [7:0] score,        // 游戏分数 (0-255, 最大可到9999用2字节)
    input  [15:0] score_full,  // 扩展分数输入 (用于显示更多位数)
    output reg [7:0] SEGMENT,  // 段选信号 (a,b,c,d,e,f,g,dp)
    output reg [3:0] AN        // 位选信号 (共阳, 低有效)
);

    // ---- 二进制 → BCD 转换 (双Dabble算法, 16-bit → 5位BCD) ----
    // 对于 0~9999 范围 (14-bit), 输出 4 位 BCD
    reg [15:0] bcd_result;     // [15:12]=千位, [11:8]=百位, [7:4]=十位, [3:0]=个位
    reg [3:0] bcd_digit;       // 当前扫描位的BCD值

    // 双Dabble: 将16-bit二进制转为5位BCD (4位用于0-9999)
    function [19:0] bin2bcd;
        input [15:0] bin;
        integer i;
        reg [19:0] temp;       // 5位BCD = 20 bits
        reg [35:0] combined;
        begin
            temp = 20'd0;
            combined = {temp, bin};
            for (i = 0; i < 16; i = i + 1) begin
                // 对每个BCD位, 如果 >= 5 则加 3
                if (combined[19:16] >= 5)
                    combined[19:16] = combined[19:16] + 3;
                if (combined[23:20] >= 5)
                    combined[23:20] = combined[23:20] + 3;
                if (combined[27:24] >= 5)
                    combined[27:24] = combined[27:24] + 3;
                if (combined[31:28] >= 5)
                    combined[31:28] = combined[31:28] + 3;
                if (combined[35:32] >= 5)
                    combined[35:32] = combined[35:32] + 3;
                // 左移一位
                combined = combined << 1;
            end
            bin2bcd = combined[35:16];
        end
    endfunction

    // 持续计算 BCD (组合逻辑)
    wire [19:0] bcd;
    assign bcd = bin2bcd({4'd0, score_full});  // 使用扩展分数

    // ---- 动态扫描状态机 ----
    reg [1:0] scan_state;      // 当前扫描位: 0=个位, 1=十位, 2=百位, 3=千位

    always @(posedge clk_scan or posedge rst) begin
        if (rst) begin
            scan_state <= 2'd0;
        end else begin
            scan_state <= scan_state + 2'd1;  // 自动循环 0→1→2→3→0
        end
    end

    // ---- 选择当前BCD数字 ----
    always @(*) begin
        case (scan_state)
            2'd0: bcd_digit = bcd[3:0];    // 个位
            2'd1: bcd_digit = bcd[7:4];    // 十位
            2'd2: bcd_digit = bcd[11:8];   // 百位
            2'd3: bcd_digit = bcd[15:12];  // 千位
        endcase
    end

    // ---- AN 位选 (共阳, 低有效) ----
    always @(*) begin
        case (scan_state)
            2'd0: AN = 4'b1110;   // 个位选中
            2'd1: AN = 4'b1101;   // 十位选中
            2'd2: AN = 4'b1011;   // 百位选中
            2'd3: AN = 4'b0111;   // 千位选中
        endcase
    end

    // ---- SEGMENT 段选 (共阳, 低有效: 0=亮, 1=灭) ----
    // 段编码: dp-g-f-e-d-c-b-a (MSB→LSB)
    always @(*) begin
        case (bcd_digit)
            4'd0: SEGMENT = 8'b11000000;  // "0"
            4'd1: SEGMENT = 8'b11111001;  // "1"
            4'd2: SEGMENT = 8'b10100100;  // "2"
            4'd3: SEGMENT = 8'b10110000;  // "3"
            4'd4: SEGMENT = 8'b10011001;  // "4"
            4'd5: SEGMENT = 8'b10010010;  // "5"
            4'd6: SEGMENT = 8'b10000010;  // "6"
            4'd7: SEGMENT = 8'b11111000;  // "7"
            4'd8: SEGMENT = 8'b10000000;  // "8"
            4'd9: SEGMENT = 8'b10010000;  // "9"
            default: SEGMENT = 8'b11111111; // 全灭
        endcase
    end

endmodule
