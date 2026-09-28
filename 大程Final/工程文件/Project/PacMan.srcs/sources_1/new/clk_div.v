//============================================================================
// clk_div.v — 时钟管理模块 (MMCM 生成 25.1MHz VGA 时钟)
//   VCO = 100MHz * 32.125 / 4 = 803.125MHz
//   CLKOUT0 = 803.125 / 32 = 25.098MHz → 640x480@59.76Hz
//============================================================================

module clk_div (
    input  clk_100mhz,
    input  rst,
    output vga_clk,            // 25.1MHz, MMCM 输出
    output reg game_clk,       // ~10Hz 单周期脉冲
    output reg scan_clk        // ~1kHz 连续时钟
);

    // ===== MMCM: 100MHz → 25.098MHz =====
    wire clk_fb, clk_unbuf, locked;
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (32.125),        // VCO = 100 * 32.125 / 4 = 803.125 MHz
        .DIVCLK_DIVIDE      (4),
        .CLKOUT0_DIVIDE_F   (32.0),          // 803.125 / 32 = 25.098 MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKIN1_PERIOD      (10.000),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKIN1   (clk_100mhz),
        .CLKFBIN  (clk_fb),
        .CLKFBOUT (clk_fb),
        .CLKOUT0  (clk_unbuf),
        .PWRDWN   (1'b0),
        .RST      (rst),
        .LOCKED   (locked)
    );
    BUFG bufg_vga (.I(clk_unbuf), .O(vga_clk));

    // ===== 游戏 Tick: ~10Hz 单周期脉冲 =====
    parameter GAME_DIV = 24'd10_000_000;
    reg [23:0] game_cnt;
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin game_cnt<=0; game_clk<=0; end
        else if (game_cnt==GAME_DIV-1) begin game_cnt<=0; game_clk<=1; end
        else begin game_cnt<=game_cnt+1; game_clk<=0; end
    end

    // ===== 扫描时钟: ~1kHz 连续50%占空比 =====
    parameter SCAN_DIV = 17'd100_000;
    reg [16:0] scan_cnt;
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin scan_cnt<=0; scan_clk<=0; end
        else if (scan_cnt==SCAN_DIV-1) begin scan_cnt<=0; scan_clk<=~scan_clk; end
        else scan_cnt<=scan_cnt+1;
    end
endmodule
