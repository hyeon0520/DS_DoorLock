// ============================================================================
//  debouncer.v  -  단일 버튼 디바운서 / Single-button debouncer
// ----------------------------------------------------------------------------
//  기계식 스위치의 채터링(접점 떨림)을 제거하여 안정된 레벨을 출력.
//    - 입력을 2단 동기화(메타스테이블 방지)
//    - 입력이 현재 출력과 다르면 STABLE_CYCLES 동안 유지되어야 출력 갱신
//  20ms @ 1MHz => STABLE_CYCLES = 20_000  (= CLK_HZ/50)
// ============================================================================
module debouncer #(
    parameter integer STABLE_CYCLES = 20_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire din,    // raw button input
    output reg  dout    // debounced, stable level
);
    reg sync0, sync1;
    reg [31:0] cnt;

    // 2-flop synchronizer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync0 <= 1'b0; sync1 <= 1'b0; end
        else        begin sync0 <= din;  sync1 <= sync0; end
    end

    // stability counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= 32'd0;
            dout <= 1'b0;
        end else if (sync1 != dout) begin
            if (cnt >= STABLE_CYCLES-1) begin
                dout <= sync1;
                cnt  <= 32'd0;
            end else begin
                cnt  <= cnt + 32'd1;
            end
        end else begin
            cnt <= 32'd0;
        end
    end
endmodule
