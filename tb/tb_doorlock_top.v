// ============================================================================
//  tb_doorlock_top.v  -  Top 통합 테스트벤치
// ----------------------------------------------------------------------------
//  시뮬레이션 가속을 위해 CLK_HZ 를 10kHz, LOCK_SECONDS 를 2초로 축소.
//  시나리오
//    A) 정상 해제 : 1-2-3-4 + ENTER -> UNLOCK -> (자동잠금) -> IDLE
//    B) 3회 실패   : 9-9-9-9 + ENTER 를 3회 -> ALARM -> CLEAR -> IDLE
//    C) 비번 변경  : 1-2-3-4+ENTER -> UNLOCK -> CHANGE -> 5-6-7-8+ENTER -> IDLE
//
//  실행 (Icarus Verilog):
//    iverilog -o sim.out tb/tb_doorlock_top.v rtl/*.v && vvp sim.out
// ============================================================================
`timescale 1ns/1ps
module tb_doorlock_top;
    localparam integer CLK_HZ = 10_000;
    localparam integer STABLE = CLK_HZ/50;   // debounce cycles (=200)

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [15:0] btn = 16'd0;
    reg  [7:0]  dip = 8'd0;
    wire        lcd_rs, lcd_rw, lcd_e;
    wire [7:0]  lcd_data;
    wire [7:0]  fnd_seg;
    wire [3:0]  fnd_com;
    wire [15:0] led;
    wire        piezo;

    doorlock_top #(
        .CLK_HZ(CLK_HZ), .DEFAULT_PW(16'h1234), .LOCK_SECONDS(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .btn(btn), .dip(dip),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_e(lcd_e), .lcd_data(lcd_data),
        .fnd_seg(fnd_seg), .fnd_com(fnd_com), .led(led), .piezo(piezo)
    );

    // clock
    always #50 clk = ~clk;   // 100ns period

    // state name for logging
    function [47:0] sname;
        input [2:0] s;
        case (s)
            3'd0: sname = "IDLE  ";
            3'd1: sname = "INPUT ";
            3'd2: sname = "CHECK ";
            3'd3: sname = "UNLOCK";
            3'd4: sname = "ALARM ";
            3'd5: sname = "CHANGE";
            default: sname = "??????";
        endcase
    endfunction

    reg [2:0] prev = 3'd7;
    always @(posedge clk) begin
        if (dut.state !== prev) begin
            $display("[%0t] STATE -> %s  (cnt=%0d fail=%0d)",
                     $time, sname(dut.state), dut.input_cnt, dut.fail_cnt);
            prev <= dut.state;
        end
    end

    // press one button: hold long enough to debounce, then release
    task press;
        input [3:0] idx;
        begin
            btn[idx] = 1'b1;
            repeat (STABLE + 20) @(posedge clk);
            btn[idx] = 1'b0;
            repeat (STABLE + 20) @(posedge clk);
        end
    endtask

    // key code aliases
    localparam [3:0] K_ENTER = 4'hA, K_CLEAR = 4'hB, K_CHANGE = 4'hC;

    integer i;
    initial begin
        $dumpfile("tb_doorlock_top.vcd");
        $dumpvars(0, tb_doorlock_top);

        // reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---- A) 정상 해제 : 1 2 3 4 ENTER ----
        $display("\n=== Scenario A: correct password 1234 ===");
        press(4'd1); press(4'd2); press(4'd3); press(4'd4);
        press(K_ENTER);
        // CHECK hold + transition
        repeat (CLK_HZ/2) @(posedge clk);   // wait through CHECK
        if (dut.state == 3'd3) $display("  -> PASS: reached UNLOCK");
        else                   $display("  -> FAIL: state=%0d", dut.state);

        // wait for auto-lock (2s = 2*CLK_HZ cycles)
        repeat (3*CLK_HZ) @(posedge clk);
        if (dut.state == 3'd0) $display("  -> PASS: auto-locked to IDLE");
        else                   $display("  -> note: state=%0d", dut.state);

        // ---- B) 3회 실패 -> ALARM ----
        $display("\n=== Scenario B: 3 wrong attempts -> ALARM ===");
        for (i = 0; i < 3; i = i + 1) begin
            press(4'd9); press(4'd9); press(4'd9); press(4'd9);
            press(K_ENTER);
            repeat (CLK_HZ/2) @(posedge clk);
        end
        if (dut.state == 3'd4) $display("  -> PASS: reached ALARM");
        else                   $display("  -> FAIL: state=%0d", dut.state);

        // clear alarm
        press(K_CLEAR);
        repeat (50) @(posedge clk);
        if (dut.state == 3'd0) $display("  -> PASS: cleared to IDLE");

        // ---- C) 비밀번호 변경 ----
        $display("\n=== Scenario C: change password to 5678 ===");
        press(4'd1); press(4'd2); press(4'd3); press(4'd4); press(K_ENTER);
        repeat (CLK_HZ/2) @(posedge clk);            // -> UNLOCK
        press(K_CHANGE);                             // -> CHANGE
        repeat (50) @(posedge clk);
        press(4'd5); press(4'd6); press(4'd7); press(4'd8); press(K_ENTER);
        repeat (100) @(posedge clk);                 // commit -> IDLE
        $display("  -> stored PW now = %h (expect 5678)", dut.u_pw.stored);

        // verify new password unlocks
        press(4'd5); press(4'd6); press(4'd7); press(4'd8); press(K_ENTER);
        repeat (CLK_HZ/2) @(posedge clk);
        if (dut.state == 3'd3) $display("  -> PASS: new password unlocks");
        else                   $display("  -> FAIL: state=%0d", dut.state);

        $display("\n=== Simulation done ===");
        $finish;
    end

    // global watchdog
    initial begin
        #200_000_000;   // 200 ms sim time hard stop
        $display("TIMEOUT");
        $finish;
    end
endmodule
