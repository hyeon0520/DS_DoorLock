// ============================================================================
//  led_controller.v  -  LED 16개 상태 표시 / LED array driver
// ----------------------------------------------------------------------------
//  도어락 상태를 16개 LED 로 직관적으로 표현한다.
//    IDLE   : 전체 점등(잠금 대기 표시)
//    INPUT  : 입력 자릿수만큼 막대 채우기 (progress bar)
//    CHECK  : 하위 8개 점등
//    UNLOCK : 전체 소등(잠금 해제 표시)
//    ALARM  : 전체 동시 점멸(blink)
//    CHANGE : 상/하위 8개 교대 점멸
// ============================================================================
module led_controller (
    input  wire        clk,      // (미사용, 향후 패턴 확장용)
    input  wire        rst_n,    // (미사용)
    input  wire [2:0]  state,
    input  wire [2:0]  input_cnt,
    input  wire        blink,
    output reg  [15:0] led
);
    localparam S_IDLE   = 3'd0, S_INPUT = 3'd1, S_CHECK = 3'd2,
               S_UNLOCK = 3'd3, S_ALARM = 3'd4, S_CHANGE = 3'd5;

    always @(*) begin
        case (state)
            S_IDLE   : led = 16'hFFFF;
            S_INPUT  : led = (16'h0001 << input_cnt) - 16'h0001; // 0,1,3,7,F
            S_CHECK  : led = 16'h00FF;
            S_UNLOCK : led = 16'h0000;
            S_ALARM  : led = blink ? 16'hFFFF : 16'h0000;
            S_CHANGE : led = blink ? 16'h00FF : 16'hFF00;
            default  : led = 16'h0000;
        endcase
    end
endmodule
