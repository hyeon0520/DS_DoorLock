// ============================================================================
//  tb_lcd_controller.v  -  LCD 드라이버 단위 테스트벤치 (권우현 담당 모듈)
// ----------------------------------------------------------------------------
//  - 초기화 시퀀스가 0x30/0x38/0x08/0x01/0x06/0x0C 순으로 나가는지
//  - Enable 펄스(lcd_e)의 상승/하강과 RS 레벨이 올바른지
//  - state 변경 시 화면이 자동 재출력 되는지 (DDRAM addr 0x80/0xC0 + ASCII)
//  를 파형(VCD)과 콘솔 로그로 확인한다.
//
//  실행:
//    iverilog -o lcd.out tb/tb_lcd_controller.v rtl/lcd_controller.v && vvp lcd.out
// ============================================================================
`timescale 1ns/1ps
module tb_lcd_controller;
    localparam integer CLK_HZ = 10_000;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [2:0] state = 3'd0;       // IDLE
    reg  [2:0] input_cnt = 3'd0;
    wire       lcd_rs, lcd_rw, lcd_e;
    wire [7:0] lcd_data;

    lcd_controller #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk), .rst_n(rst_n),
        .state(state), .input_cnt(input_cnt),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_e(lcd_e), .lcd_data(lcd_data)
    );

    always #50 clk = ~clk;

    // log every byte latched on the falling edge of E (write complete)
    reg e_q = 1'b0;
    always @(posedge clk) begin
        e_q <= lcd_e;
        if (e_q && !lcd_e) begin   // E falling edge
            if (lcd_rs)
                $display("[%0t] DATA  0x%02h  '%s'", $time, lcd_data,
                         (lcd_data >= 8'h20 && lcd_data < 8'h7F) ? lcd_data : 8'h2E);
            else
                $display("[%0t] CMD   0x%02h", $time, lcd_data);
        end
    end

    initial begin
        $dumpfile("tb_lcd_controller.vcd");
        $dumpvars(0, tb_lcd_controller);

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // let init + first IDLE screen render
        repeat (CLK_HZ) @(posedge clk);

        // simulate entering INPUT and typing digits
        $display("\n-- state=INPUT, cnt=1 --");
        state = 3'd1; input_cnt = 3'd1;
        repeat (CLK_HZ/2) @(posedge clk);

        $display("\n-- cnt=3 --");
        input_cnt = 3'd3;
        repeat (CLK_HZ/2) @(posedge clk);

        $display("\n-- state=UNLOCK --");
        state = 3'd3; input_cnt = 3'd0;
        repeat (CLK_HZ/2) @(posedge clk);

        $display("\n-- state=ALARM --");
        state = 3'd4;
        repeat (CLK_HZ/2) @(posedge clk);

        $display("\n=== LCD test done ===");
        $finish;
    end

    initial begin
        #100_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
