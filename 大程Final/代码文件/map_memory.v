//============================================================================
// map_memory.v — 地图 ROM + 豆子 RAM (修订版v3)
// MAP ROM:  32×24 = 768 cells × 2-bit (00=空地, 01=墙壁, 10=幽灵房, 11=出生点)
// PELLET RAM: 768 cells × 1-bit (1=有豆子, 0=已吃)
// ROM 读取: 组合逻辑 (无时钟延迟, 供 VGA 和游戏逻辑同时读取)
// RAM 读取: 组合逻辑
// RAM 写入: 同步 (posedge clk)
// pellet_init: 重新初始化所有豆子 (在游戏重新开始时触发)
//============================================================================

module map_memory (
    input  clk,                    // 系统时钟 (100MHz)
    input  rst,                    // 全局复位

    // ---- Port A: VGA 读端口 (组合逻辑) ----
    input  [9:0] addr_a,          // {row[4:0], col[4:0]}
    output [1:0] map_type_a,      // ROM 地图类型
    output       pellet_a,        // 当前位置豆子状态

    // ---- Port B: 游戏逻辑端口 (组合逻辑读 + 同步写) ----
    input  [9:0] addr_b,          // {row[4:0], col[4:0]}
    output [1:0] map_type_b,      // ROM 地图类型
    output       pellet_b,        // 豆子状态
    input        pellet_we,       // 豆子 RAM 写使能
    input        pellet_din,      // 写入数据

    // ---- 豆子重新初始化 ----
    input        pellet_init,     // 高有效 (脉冲, 触发全部豆子恢复)

    // ---- 豆子总数输出 ----
    output reg [9:0] pellet_total // 初始化后的豆子总数
);

    // ---- 存储数组 ----
    reg [1:0] map_rom [0:767];
    reg [0:0] pellet_ram [0:767];

    // ---- ROM: 组合逻辑读取 (双端口读数) ----
    assign map_type_a = map_rom[addr_a];
    assign map_type_b = map_rom[addr_b];

    // ---- RAM: 组合逻辑读取 (双端口读数) ----
    assign pellet_a = pellet_ram[addr_a];
    assign pellet_b = pellet_ram[addr_b];

    // ---- RAM: 同步写入 + 豆子初始化状态机 (合并在一个 always 块中) ----
    reg [9:0] init_addr;
    reg       init_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            init_addr    <= 10'd0;
            init_active  <= 1'b0;
            pellet_total <= 10'd0;
        end else begin
            // ---- 优先级1: 游戏逻辑吃豆 (pellet_we=1) ----
            if (pellet_we) begin
                pellet_ram[addr_b] <= pellet_din;
            end

            // ---- 优先级2: 豆子初始化触发 ----
            if (pellet_init) begin
                init_addr    <= 10'd0;
                init_active  <= 1'b1;
                pellet_total <= 10'd0;
            end else if (init_active) begin
                // 在当前地址恢复豆子 (只有空地/出生点才有豆子)
                // 注: 不覆盖吃豆逻辑刚写入的地址 (同一周期 pellet_we 优先)
                if (!pellet_we || (init_addr != addr_b)) begin
                    if (map_rom[init_addr] == 2'b00 || map_rom[init_addr] == 2'b11) begin
                        pellet_ram[init_addr] <= 1'b1;
                        pellet_total <= pellet_total + 10'd1;  // 计数
                    end else begin
                        pellet_ram[init_addr] <= 1'b0;
                    end
                end

                if (init_addr == 10'd767)
                    init_active <= 1'b0;        // 完成
                else
                    init_addr <= init_addr + 10'd1;
            end
        end
    end

    // ---- 迷宫初始化 (仅在仿真/上电时执行一次) ----
    integer i;
    initial begin
        // 全部初始化为墙壁
        for (i = 0; i < 768; i = i + 1) begin
            map_rom[i]    = 2'b01;
            pellet_ram[i] = 1'b1;
        end

        // ======== 定义通道 ========
        // 水平主干道
        for (i = 1; i < 31; i = i + 1) map_rom[1*32 + i]  = 2'b00;   // Row 1
        for (i = 1; i < 31; i = i + 1) map_rom[22*32 + i] = 2'b00;   // Row 22
        for (i = 1; i < 31; i = i + 1) map_rom[4*32 + i]  = 2'b00;   // Row 4
        for (i = 1; i < 31; i = i + 1) map_rom[9*32 + i]  = 2'b00;   // Row 9
        for (i = 1; i < 31; i = i + 1) map_rom[18*32 + i] = 2'b00;   // Row 18

        // 幽灵房上方通道 (Row 10-11 中间连接, 使房门通向外侧)
        for (i = 1;  i < 13; i = i + 1) map_rom[10*32 + i] = 2'b00;
        for (i = 13; i < 19; i = i + 1) map_rom[10*32 + i] = 2'b00;
        for (i = 19; i < 31; i = i + 1) map_rom[10*32 + i] = 2'b00;
        for (i = 1;  i < 13; i = i + 1) map_rom[11*32 + i] = 2'b00;
        for (i = 13; i < 19; i = i + 1) map_rom[11*32 + i] = 2'b00;
        for (i = 19; i < 31; i = i + 1) map_rom[11*32 + i] = 2'b00;
        for (i = 1;  i < 13; i = i + 1) map_rom[12*32 + i] = 2'b00;
        for (i = 19; i < 31; i = i + 1) map_rom[12*32 + i] = 2'b00;
        for (i = 1;  i < 13; i = i + 1) map_rom[14*32 + i] = 2'b00;
        for (i = 19; i < 31; i = i + 1) map_rom[14*32 + i] = 2'b00;
        for (i = 1;  i < 13; i = i + 1) map_rom[15*32 + i] = 2'b00;
        for (i = 19; i < 31; i = i + 1) map_rom[15*32 + i] = 2'b00;

        // 垂直边缘
        for (i = 1; i < 23; i = i + 1) map_rom[i*32 + 1]  = 2'b00;
        for (i = 1; i < 23; i = i + 1) map_rom[i*32 + 30] = 2'b00;

        // 内部竖道
        for (i = 2;  i < 9;  i = i + 1) map_rom[i*32 + 6]  = 2'b00;
        for (i = 2;  i < 9;  i = i + 1) map_rom[i*32 + 25] = 2'b00;
        for (i = 15; i < 22; i = i + 1) map_rom[i*32 + 6]  = 2'b00;
        for (i = 15; i < 22; i = i + 1) map_rom[i*32 + 25] = 2'b00;
        for (i = 2;  i < 11; i = i + 1) map_rom[i*32 + 12] = 2'b00;
        for (i = 2;  i < 11; i = i + 1) map_rom[i*32 + 19] = 2'b00;

        // ---- 吃豆人出生点所在行 (Row 16) 水平通道 ----
        for (i = 1; i < 31; i = i + 1) map_rom[16*32 + i] = 2'b00;

        // ---- 幽灵房 (Rows 13-14, Cols 13-18) ----
        for (i = 13; i < 19; i = i + 1) begin
            map_rom[13*32 + i] = 2'b10;
            map_rom[14*32 + i] = 2'b10;
        end
        // 幽灵房墙壁
        for (i = 12; i < 20; i = i + 1) map_rom[12*32 + i] = 2'b01;
        for (i = 12; i < 20; i = i + 1) map_rom[15*32 + i] = 2'b01;
        map_rom[13*32 + 12] = 2'b01;  map_rom[14*32 + 12] = 2'b01;
        map_rom[13*32 + 19] = 2'b01;  map_rom[14*32 + 19] = 2'b01;
        // 幽灵房门
        map_rom[12*32 + 15] = 2'b00;
        map_rom[12*32 + 16] = 2'b00;

        // ---- 吃豆人出生点 ----
        map_rom[16*32 + 16] = 2'b11;

        // ---- 清除非空地位置的豆子 ----
        for (i = 0; i < 768; i = i + 1) begin
            if (map_rom[i] != 2'b00 && map_rom[i] != 2'b11)
                pellet_ram[i] = 1'b0;
        end
    end

endmodule
