//============================================================================
// buzzer_ctrl.v — 蜂鸣器音效控制器
// 根据 game_logic_fsm 发出的音效事件触发信号, 输出不同频率方波:
//   - sound_event = 01 (EAT):   800Hz, 短促高音 (~100ms)
//   - sound_event = 10 (DEATH): 200Hz, 低沉长音 (~500ms)
//   - sound_event = 11 (WIN):   1000Hz / 1500Hz 交替, 上升感
//============================================================================

module buzzer_ctrl (
    input  clk,                  // 100MHz 系统时钟
    input  rst,
    input  [1:0] sound_event,   // 00=空闲, 01=吃豆, 10=死亡, 11=胜利
    output reg buzzer            // 蜂鸣器输出方波
);

    // ---- 频率参数 (100MHz / (2 * freq) → 半周期计数值) ----
    // 800Hz:  100,000,000 / (2*800)   = 62500
    // 200Hz:  100,000,000 / (2*200)   = 250000
    // 1000Hz: 100,000,000 / (2*1000)  = 50000
    // 1500Hz: 100,000,000 / (2*1500)  ≈ 33333
    parameter HALF_800HZ  = 17'd62500;
    parameter HALF_200HZ  = 18'd250000;
    parameter HALF_1000HZ = 17'd50000;
    parameter HALF_1500HZ = 16'd33333;

    // ---- 音效持续时间 (100MHz 周期) ----
    parameter EAT_DURATION   = 24'd10_000_000;   // 100ms
    parameter DEATH_DURATION = 24'd50_000_000;   // 500ms
    parameter WIN_DURATION   = 24'd100_000_000;  // 1000ms
    parameter WIN_SWITCH     = 24'd25_000_000;   // 250ms 切换一次频率

    // ---- 频率生成计数器 ----
    reg [17:0] freq_cnt;
    reg [17:0] half_period;     // 当前半周期
    reg [23:0] duration_cnt;    // 音效已持续时间
    reg [23:0] total_duration;  // 总持续时间
    reg [23:0] switch_cnt;      // WIN 模式频率切换计数
    reg        sound_active;

    // ---- 状态机: IDLE → PLAYING → IDLE ----
    reg playing;
    reg [1:0] last_event;       // 边沿检测

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            playing     <= 1'b0;
            last_event  <= 2'b00;
            duration_cnt <= 24'd0;
            switch_cnt   <= 24'd0;
            sound_active <= 1'b0;
        end else begin
            // 检测事件上升沿
            if (sound_event != 2'b00 && sound_event != last_event) begin
                playing     <= 1'b1;
                duration_cnt <= 24'd0;
                switch_cnt   <= 24'd0;
                sound_active <= 1'b1;

                case (sound_event)
                    2'b01: total_duration <= EAT_DURATION;
                    2'b10: total_duration <= DEATH_DURATION;
                    2'b11: total_duration <= WIN_DURATION;
                    default: total_duration <= 24'd0;
                endcase
            end else if (playing) begin
                if (duration_cnt >= total_duration) begin
                    playing      <= 1'b0;
                    sound_active <= 1'b0;
                end else begin
                    duration_cnt <= duration_cnt + 24'd1;
                    if (sound_event == 2'b11)   // WIN模式: 250ms切换频率
                        switch_cnt <= switch_cnt + 24'd1;
                end
            end

            last_event <= sound_event;
        end
    end

    // ---- 选择当前半周期 ----
    always @(*) begin
        if (!sound_active) begin
            half_period = 18'd0;
        end else begin
            case (sound_event)
                2'b01: half_period = HALF_800HZ;
                2'b10: half_period = HALF_200HZ;
                2'b11: begin
                    // WIN: 前250ms用1000Hz, 之后交替
                    if (switch_cnt < WIN_SWITCH)
                        half_period = HALF_1000HZ;
                    else if (switch_cnt < 2*WIN_SWITCH)
                        half_period = HALF_1500HZ;
                    else if (switch_cnt < 3*WIN_SWITCH)
                        half_period = HALF_1000HZ;
                    else
                        half_period = HALF_1500HZ;
                end
                default: half_period = 18'd0;
            endcase
        end
    end

    // ---- 方波生成 ----
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            freq_cnt <= 18'd0;
            buzzer   <= 1'b0;
        end else begin
            if (!sound_active) begin
                freq_cnt <= 18'd0;
                buzzer   <= 1'b0;
            end else if (half_period == 0) begin
                buzzer <= 1'b0;
            end else begin
                if (freq_cnt >= half_period - 1) begin
                    freq_cnt <= 18'd0;
                    buzzer   <= ~buzzer;
                end else begin
                    freq_cnt <= freq_cnt + 18'd1;
                end
            end
        end
    end

endmodule
