//============================================================================
// top_pacman.v — 顶层模块: 吃豆人游戏 (修订版v2)
//
// 子模块: clk_div, map_memory, vga_display, game_logic_fsm,
//         ps2_keyboard, seg_display, buzzer_ctrl
//
// Sword Kintex 7 I/O:
//   系统时钟: clk_100mhz → AC18
//   复位:     RSTN       → W13
//   VGA:      VGA_R/G/B, HSYNC, VSYNC
//   PS/2:     PS2_clk (N18), PS2_data (M19)
//   七段码:   SEGMENT[7:0], AN[3:0]  (Arduino子板, 共阳)
//   蜂鸣器:   Buzzer (AF24)
//   LED:      LED[7:0] (Arduino子板)
//   开关:     SW[15:0]
//   按钮:     BTN_x[4:0] = 5'b00000, BTN_y[3:0] 输入 (独立键模式)
//
//   SW[0]: 开始游戏, SW[1]: 复位, SW[15]: 暂停
//============================================================================

module top_pacman (
    input  clk_100mhz,
    input  RSTN,                // 低有效 → 内部反相

    // VGA
    output [3:0] VGA_R, VGA_G, VGA_B,
    output HSYNC, VSYNC,

    // PS/2
    input  PS2_clk, PS2_data,

    // 七段码
    output [7:0] SEGMENT,
    output [3:0] AN,

    // LED
    output [7:0] LED,

    // 蜂鸣器
    output Buzzer,

    // 开关 + 按钮
    input  [15:0] SW,
    output [4:0] BTN_x,
    input  [3:0] BTN_y
);

    // ======== 复位信号 ========
    wire rst = ~RSTN;

    // ======== 按钮去抖动 (简单同步器) ========
    // SW[0] → 开始, SW[1] → 复位, SW[15] → 暂未使用
    reg [1:0] sw0_sync, sw1_sync;
    always @(posedge clk_100mhz) begin
        sw0_sync <= {sw0_sync[0], SW[0]};
        sw1_sync <= {sw1_sync[0], SW[1]};
    end
    wire sw0_rise = sw0_sync[1] && !sw0_sync[0];  // SW[0] 上升沿
    wire sw1_rise = sw1_sync[1] && !sw1_sync[0];  // SW[1] 上升沿

    // ======== 时钟分频 ========
    wire clk_vga;           // 25MHz
    wire game_tick;         // ~10Hz 脉冲
    wire clk_scan;          // ~1kHz 扫描

    clk_div u_clk (
        .clk_100mhz (clk_100mhz),
        .rst        (rst),
        .vga_clk    (clk_vga),
        .game_clk   (game_tick),
        .scan_clk   (clk_scan)
    );

    // ======== 游戏逻辑 ========
    wire [4:0] pac_x, pac_y, ghost_x, ghost_y;
    wire [1:0] game_state;
    wire [7:0] score;
    wire [1:0] sound_event;
    wire [7:0] score_led;

    // 方向输入 (来自 PS/2 或 SW/按钮)
    wire up, down, left, right;
    wire p2_up, p2_down, p2_left, p2_right;
    wire kbd_start, kbd_reset;

    // 地图总线
    wire [9:0] game_map_addr;     // 游戏逻辑读地址
    wire [1:0] game_map_type;     // 地图类型
    wire       game_pellet;       // 豆子状态
    wire [9:0] game_pellet_waddr; // 写地址 (清除豆子)
    wire       game_pellet_we;
    wire       game_pellet_din;

    // 注: game_logic可同时输出 map_addr (读) 和 pellet_waddr (写)
    // 通过 MUX 选择传给 map_memory Port B

    // ---- 开始/复位信号合并 (PS/2 键盘 OR 开关) ----
    wire start_sig = kbd_start | sw0_rise;
    wire reset_sig = kbd_reset | sw1_rise;

    game_logic_fsm u_game (
        .clk          (clk_100mhz),
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
        .start_game   (start_sig),
        .reset_game   (reset_sig),
        .map_addr     (game_map_addr),
        .map_type     (game_map_type),
        .pellet_state (game_pellet),
        .pellet_waddr (game_pellet_waddr),
        .pellet_we    (game_pellet_we),
        .pellet_din   (game_pellet_din),
        .pellet_total (map_pellet_total),
        .pac_x        (pac_x),
        .pac_y        (pac_y),
        .ghost_x      (ghost_x),
        .ghost_y      (ghost_y),
        .game_state   (game_state),
        .score        (score),
        .sound_event  (sound_event),
        .debug_led    (score_led)
    );

    // ======== 地图存储 (ROM + Pellet RAM) ========
    wire [9:0] vga_map_addr;
    wire [1:0] vga_map_type;
    wire       vga_pellet;

    // Port B 地址 MUX: 当游戏逻辑在写豆子时, 传递写地址
    wire [9:0] map_addr_b = game_pellet_we ? game_pellet_waddr : game_map_addr;

    wire [9:0] map_pellet_total;

    map_memory u_map (
        .clk         (clk_100mhz),
        .rst         (rst),
        .addr_a      (vga_map_addr),
        .map_type_a  (vga_map_type),
        .pellet_a    (vga_pellet),
        .addr_b      (map_addr_b),
        .map_type_b  (game_map_type),
        .pellet_b    (game_pellet),
        .pellet_we   (game_pellet_we),
        .pellet_din  (game_pellet_din),
        .pellet_init (pellet_init),
        .pellet_total(map_pellet_total)
    );

    // ======== 豆子初始化控制器 ========
    reg [1:0] prev_state;
    reg       pellet_init;
    always @(posedge clk_100mhz or posedge rst) begin
        if (rst) begin
            prev_state  <= 2'b00;
            pellet_init <= 1'b0;
        end else begin
            prev_state <= game_state;
            // 任意状态 → PLAY 时触发 (包括 GAMEOVER/WIN 重新开始)
            pellet_init <= (prev_state != 2'b01 && game_state == 2'b01);
        end
    end

    // ======== PS/2 键盘 ========
    ps2_keyboard u_ps2 (
        .clk        (clk_100mhz),
        .rst        (rst),
        .ps2_clk    (PS2_clk),
        .ps2_data   (PS2_data),
        .up         (up),
        .down       (down),
        .left       (left),
        .right      (right),
        .p2_up      (p2_up),
        .p2_down    (p2_down),
        .p2_left    (p2_left),
        .p2_right   (p2_right),
        .start_game (kbd_start),
        .reset_game (kbd_reset)
    );

    // ======== VGA 显示 ========
    vga_display u_vga (
        .clk_vga    (clk_vga),
        .rst        (rst),
        .map_addr   (vga_map_addr),
        .map_type   (vga_map_type),
        .pellet     (vga_pellet),
        .pac_x      (pac_x),
        .pac_y      (pac_y),
        .ghost_x    (ghost_x),
        .ghost_y    (ghost_y),
        .game_state (game_state),
        .VGA_R      (VGA_R),
        .VGA_G      (VGA_G),
        .VGA_B      (VGA_B),
        .HSYNC      (HSYNC),
        .VSYNC      (VSYNC)
    );

    // ======== 七段码 ========
    wire [15:0] score_ext = {8'd0, score};

    seg_display u_seg (
        .clk        (clk_100mhz),
        .clk_scan   (clk_scan),
        .rst        (rst),
        .score      (score),
        .score_full (score_ext),
        .SEGMENT    (SEGMENT),
        .AN         (AN)
    );

    // ======== 蜂鸣器 ========
    buzzer_ctrl u_buzz (
        .clk         (clk_100mhz),
        .rst         (rst),
        .sound_event (sound_event),
        .buzzer      (Buzzer)
    );

    // ======== 按钮 (独立键模式) ========
    assign BTN_x = 5'b00000;

    // ======== LED 状态指示 ========
    assign LED = (game_state == 2'b00) ? 8'b00000001 :     // IDLE:    LED[0]
                 (game_state == 2'b01) ? 8'b00000010 :     // PLAY:    LED[1]
                 (game_state == 2'b10) ? 8'b00000100 :     // GAMEOVER: LED[2]
                 (game_state == 2'b11) ? 8'b00001000 :     // WIN:     LED[3]
                 8'b00000000;

endmodule
