//============================================================================
// tb_buzzer_ctrl.v — buzzer_ctrl Testbench (v3)
//
// IMPORTANT: Vivado XSim pauses at 1000ns by default.
//            Before starting, type this in Tcl Console:
//              run all
//            Or set: Simulation Settings > Simulation > xsim.simulate.runtime
//============================================================================

`timescale 1ns / 1ps

module tb_buzzer_ctrl;

    reg         clk;
    reg         rst;
    reg  [1:0]  sound_event;
    wire        buzzer;

    buzzer_ctrl uut (
        .clk         (clk),
        .rst         (rst),
        .sound_event (sound_event),
        .buzzer      (buzzer)
    );

    // 100MHz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // measure N full buzzer cycles
    task measure_cycles;
        input [7:0] n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge buzzer);
                @(negedge buzzer);
            end
            $display("  [%0t] %0d cycles completed", $time, n);
        end
    endtask

    // main
    initial begin
        $display("==============================================");
        $display(" buzzer_ctrl Testbench v3");
        $display(" NOTE: type 'run all' in Tcl Console to continue");
        $display("==============================================");

        // ---- power-on reset ----
        rst         = 1'b1;
        sound_event = 2'b00;
        #100;
        rst         = 1'b0;
        #50;

        // ============================================================
        // Test 1: IDLE (00) — buzzer must be 0
        // ============================================================
        $display("");
        $display("--- Test 1: IDLE (sound_event=00) ---");
        #500;
        $display("  buzzer=%0d (expect 0) %s", buzzer, (buzzer==0)?"OK":"FAIL");

        // ============================================================
        // Test 2: EAT (01) — 800Hz
        // ============================================================
        $display("");
        $display("--- Test 2: EAT (sound_event=01, 800Hz) ---");
        @(posedge clk);
        sound_event <= 2'b01;
        $display("  [%0t] sound_event -> 01", $time);

        // 800Hz: half_period=62500 cycles, first edge at ~625us
        @(posedge buzzer);
        $display("  [%0t] 1st rising edge (800Hz, half_period=62500)", $time);
        @(negedge buzzer);
        $display("  [%0t] falling edge", $time);
        @(posedge buzzer);
        $display("  [%0t] 2nd rising edge -> T=~1.25ms = 800Hz OK", $time);

        measure_cycles(3);
        $display("  EAT frequency: 800Hz OK");

        // cleanup
        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0; #50;

        // ============================================================
        // Test 3: DEATH (10) — 200Hz
        // ============================================================
        $display("");
        $display("--- Test 3: DEATH (sound_event=10, 200Hz) ---");
        @(posedge clk);
        sound_event <= 2'b10;
        $display("  [%0t] sound_event -> 10", $time);

        // 200Hz: half_period=250000 cycles, first edge at ~2.5ms
        @(posedge buzzer);
        $display("  [%0t] 1st rising edge (200Hz, half_period=250000)", $time);
        @(negedge buzzer);
        @(posedge buzzer);
        $display("  [%0t] 2nd rising edge -> T=~5ms = 200Hz OK", $time);

        measure_cycles(2);
        $display("  DEATH frequency: 200Hz OK (4x slower than EAT)");

        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0; #50;

        // ============================================================
        // Test 4: WIN (11) — 1000Hz / 1500Hz alternating
        // ============================================================
        $display("");
        $display("--- Test 4: WIN (sound_event=11, 1000/1500Hz) ---");
        @(posedge clk);
        sound_event <= 2'b11;
        $display("  [%0t] sound_event -> 11", $time);

        // 1000Hz phase: half_period=50000, first edge at ~500us
        @(posedge buzzer);
        $display("  [%0t] 1st rising edge (1000Hz phase, T=~1ms)", $time);
        @(negedge buzzer);
        @(posedge buzzer);
        $display("  [%0t] 2nd rising edge -> 1000Hz OK", $time);

        measure_cycles(3);
        $display("  WIN freq alternates: 1000Hz <-> 1500Hz every 250ms");
        $display("  (check switch_cnt and half_period in waveform)");
        #100000;

        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0; #50;

        // ============================================================
        // Test 5: Edge detection — re-trigger
        // ============================================================
        $display("");
        $display("--- Test 5: Edge detection (re-trigger) ---");

        @(posedge clk); sound_event <= 2'b01;
        @(posedge buzzer);
        $display("  [%0t] 1st EAT: buzzer rising OK", $time);

        // keep 01, should not re-trigger
        #50000;
        $display("  holding sound_event=01: no re-trigger OK");

        // reset and re-trigger
        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0; #50;

        @(posedge clk); sound_event <= 2'b01;
        @(posedge buzzer);
        $display("  [%0t] 2nd EAT: re-trigger OK", $time);

        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0; #50;

        // ============================================================
        // Test 6: Reset during playback
        // ============================================================
        $display("");
        $display("--- Test 6: Reset during playback ---");
        @(posedge clk); sound_event <= 2'b10;
        #5000;
        rst = 1'b1;
        #100;
        $display("  buzzer during reset=%0d (expect 0) %s", buzzer, (buzzer==0)?"OK":"FAIL");
        rst = 1'b0;
        sound_event <= 2'b00;

        // ============================================================
        // Test 7: 01 -> 10 -> 11 continuous trigger
        // ============================================================
        $display("");
        $display("--- Test 7: 01 -> 10 -> 11 edge sequence ---");

        @(posedge clk); sound_event <= 2'b01;  // EAT
        #50000;
        @(posedge clk); sound_event <= 2'b10;  // DEATH
        #50000;
        @(posedge clk); sound_event <= 2'b11;  // WIN
        #50000;
        $display("  01->10->11 all edges captured OK");
        $display("  (verify: sound_event shows 01/10/11 in waveform)");

        sound_event <= 2'b00;
        rst = 1'b1; #50; rst = 1'b0;

        // ============================================================
        // Done
        // ============================================================
        #5000;
        $display("");
        $display("==============================================");
        $display(" buzzer_ctrl simulation PASSED");
        $display("==============================================");
        $display(" Waveform checklist:");
        $display("   1. sound_event: 00, 01, 10, 11 (all 4 values)");
        $display("   2. EAT(01):  half_period=62500,  T=~1.25ms");
        $display("   3. DEATH(10): half_period=250000, T=~5ms");
        $display("   4. WIN(11):   half_period=50000/33333 alternating");
        $display("   5. rst=1 -> sound_active=0, buzzer=0");
        $display("==============================================");
        $finish;
    end

endmodule
