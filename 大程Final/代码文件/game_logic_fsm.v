//============================================================================
// game_logic_fsm.v — 核心游戏状态机 (修订版v5, 纯硬件可靠)
// 幽灵: LFSR随机 + 墙壁避碰, 不依赖任何ROM/initial/$readmemb
//============================================================================

module game_logic_fsm (
    input  clk, game_tick, rst,
    input  up, down, left, right,         // 黄(WASD)
    input  p2_up, p2_down, p2_left, p2_right, // 红(箭头)
    input  start_game, reset_game,
    output reg [9:0] map_addr,
    input  [1:0] map_type,
    input  pellet_state,
    output reg [9:0]  pellet_waddr,
    output reg        pellet_we,
    output reg        pellet_din,
    input  [9:0] pellet_total,
    output reg [4:0] pac_x, pac_y, ghost_x, ghost_y,
    output reg [1:0] game_state,
    output reg [7:0] score,
    output reg [1:0] sound_event,
    output reg [7:0] debug_led
);

    parameter IDLE=2'd0, PLAY=2'd1, GAMEOVER=2'd2, WIN=2'd3;
    parameter P_IDLE=3'd0, P_CALC=3'd1, P_CHECK=3'd2, P_PELLET=3'd3, P_GHOST=3'd4;
    parameter DN=3'd0, DU=3'd1, DD=3'd2, DL=3'd3, DR=3'd4;

    reg [2:0] play_sub;
    reg [4:0] pnx, pny, gnx, gny;
    reg [2:0] pac_dir, ghost_dir;
    reg       want_u, want_d, want_l, want_r;
    reg [7:0] lfsr;
    reg       pac_moved;
    reg       pellet_latch;        // P_CHECK锁存豆子状态
    reg [9:0] pellets_remain;
    reg       count_loaded;
    reg [15:0] tick_cnt;
    // 组合逻辑: 下一步坐标
    wire [4:0] pac_nx = (pac_dir==DL)?((pac_x==0)?pac_x:pac_x-1):(pac_dir==DR)?((pac_x==30)?pac_x:pac_x+1):pac_x;
    wire [4:0] pac_ny = (pac_dir==DU)?((pac_y==0)?pac_y:pac_y-1):(pac_dir==DD)?((pac_y==22)?pac_y:pac_y+1):pac_y;
    wire [4:0] gho_nx = (ghost_dir==DL)?((ghost_x==0)?ghost_x:ghost_x-1):(ghost_dir==DR)?((ghost_x==31)?ghost_x:ghost_x+1):ghost_x;
    wire [4:0] gho_ny = (ghost_dir==DU)?((ghost_y==0)?ghost_y:ghost_y-1):(ghost_dir==DD)?((ghost_y==23)?ghost_y:ghost_y+1):ghost_y;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            game_state<=IDLE; play_sub<=P_IDLE;
            pac_x<=16; pac_y<=16; ghost_x<=15; ghost_y<=14;
            pnx<=16; pny<=16; gnx<=15; gny<=14;
            pac_dir<=DN; ghost_dir<=DU;
            want_u<=0; want_d<=0; want_l<=0; want_r<=0;
            lfsr<=8'h5A; pac_moved<=0; pellet_latch<=0; tick_cnt<=0;
            score<=0; pellets_remain<=0;
            sound_event<=0; pellet_we<=0;
            pellet_waddr<=0; pellet_din<=0;
            map_addr<=0; count_loaded<=0;
            debug_led<=8'h01;
        end else begin
            pellet_we<=0; sound_event<=0;
            lfsr<={lfsr[6:0],lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};

            if(game_state==PLAY)begin
                want_u<=up; want_d<=down; want_l<=left; want_r<=right;
                // 红: 箭头键设方向, 松键即停
                if(p2_up)           ghost_dir<=DU;
                else if(p2_down)    ghost_dir<=DD;
                else if(p2_left)    ghost_dir<=DL;
                else if(p2_right)   ghost_dir<=DR;
                else                ghost_dir<=DN;
            end

            case(game_state)
                IDLE: begin
                    debug_led<=8'h01; score<=0;
                    want_u<=0; want_d<=0; want_l<=0; want_r<=0;
                    if(start_game)begin
                        game_state<=PLAY; play_sub<=P_IDLE;
                        pac_x<=16; pac_y<=16; ghost_x<=15; ghost_y<=14;
                        pac_dir<=DN; ghost_dir<=DU;
                        score<=0; pellets_remain<=0;
                        count_loaded<=0; pac_moved<=0; pellet_latch<=0; tick_cnt<=0;
                    end
                end

                PLAY: begin
                    debug_led<=8'h02;
                    if(reset_game) game_state<=IDLE;
                    case(play_sub)
                        P_IDLE: begin
                            if(game_tick)begin
                                tick_cnt<=tick_cnt+16'd1;
                                if(!count_loaded)begin
                                    pellets_remain<=pellet_total; count_loaded<=1;
                                end
                                if(want_u)      pac_dir<=DU;
                                else if(want_d) pac_dir<=DD;
                                else if(want_l) pac_dir<=DL;
                                else if(want_r) pac_dir<=DR;
                                else            pac_dir<=DN;
                                play_sub<=P_CALC;
                            end
                        end

                        P_CALC: begin
                            pnx<=pac_nx; pny<=pac_ny;
                            map_addr<={pac_ny,pac_nx};
                            play_sub<=P_CHECK;
                        end

                        P_CHECK: begin
                            if(map_type!=2'b01 && pnx>=1 && pnx<=30 && pny>=1 && pny<=22)begin
                                pac_x<=pnx; pac_y<=pny; pac_moved<=1;
                                pellet_latch<=pellet_state;
                            end else begin
                                pac_moved<=0; pellet_latch<=0; map_addr<={pac_y,pac_x};
                            end
                            play_sub<=P_PELLET;
                        end

                        P_PELLET: begin
                            // 吃豆: pellet_latch在P_CHECK锁存(1周期稳定)
                            if(pac_moved && pellet_latch)begin
                                pellet_we<=1; pellet_waddr<={pny,pnx}; pellet_din<=0;
                                score<=score+8'd1;
                                pellets_remain<=pellets_remain-10'd1;
                                sound_event<=2'b01;
                            end
                            pac_moved<=0;

                            // 红: 玩家2操控, 直接锁存方向移动
                            gnx<=gho_nx; gny<=gho_ny;
                            map_addr<={gho_ny,gho_nx};
                            play_sub<=P_GHOST;
                        end

                        P_GHOST: begin
                            // 红: 双重墙壁检测(ROM + 坐标) + 碰撞
                            if(map_type!=2'b01 && gnx>=1 && gnx<=30 && gny>=1 && gny<=22
                               && !(gnx==0 || gnx==31 || gny==0 || gny==23))begin
                                ghost_x<=gnx; ghost_y<=gny;
                            end
                            if(pac_x==ghost_x && pac_y==ghost_y)begin
                                game_state<=GAMEOVER; sound_event<=2'b10;
                            end else if(pellets_remain==0)begin
                                game_state<=WIN; sound_event<=2'b11;
                            end
                            play_sub<=P_IDLE;
                        end
                        default: play_sub<=P_IDLE;
                    endcase
                end

                GAMEOVER: begin
                    debug_led<=8'h04; sound_event<=2'b10;
                    if(start_game)begin
                        game_state<=PLAY; play_sub<=P_IDLE;
                        pac_x<=16; pac_y<=16; ghost_x<=15; ghost_y<=14;
                        pac_dir<=DN; ghost_dir<=DU;
                        score<=0; pellets_remain<=0;
                        count_loaded<=0; pac_moved<=0; pellet_latch<=0; tick_cnt<=0;
                    end
                    if(reset_game) game_state<=IDLE;
                end

                WIN: begin
                    debug_led<=8'h08; sound_event<=2'b11;
                    if(start_game)begin
                        game_state<=PLAY; play_sub<=P_IDLE;
                        pac_x<=16; pac_y<=16; ghost_x<=15; ghost_y<=14;
                        pac_dir<=DN; ghost_dir<=DU;
                        score<=0; pellets_remain<=0;
                        count_loaded<=0; pac_moved<=0; pellet_latch<=0; tick_cnt<=0;
                    end
                    if(reset_game) game_state<=IDLE;
                end
                default: game_state<=IDLE;
            endcase
        end
    end
endmodule
