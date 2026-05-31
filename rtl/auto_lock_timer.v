// ============================================================================
//  auto_lock_timer.v  -  자동 잠금 타이머 / Auto-lock timer
// ----------------------------------------------------------------------------
//  UNLOCK 상태에서 enable=1 이 되면 1Hz tick 을 세어 LOCK_SECONDS 초 경과 시
//  timeout 을 1-사이클 펄스로 발생시켜 FSM 을 IDLE 로 강제 복귀시킨다.
//  enable 이 풀리면(다른 상태) 카운터는 즉시 0 으로 리셋된다.
// ============================================================================
module auto_lock_timer #(
    parameter integer LOCK_SECONDS = 10
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enable,     // UNLOCK 상태에서 1
    input  wire tick_1hz,   // 1Hz 단일-사이클 펄스
    output reg  timeout
);
    reg [31:0] sec;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec     <= 32'd0;
            timeout <= 1'b0;
        end else if (!enable) begin
            sec     <= 32'd0;
            timeout <= 1'b0;
        end else begin
            timeout <= 1'b0;
            if (tick_1hz) begin
                if (sec >= LOCK_SECONDS-1) begin
                    timeout <= 1'b1;
                    sec     <= 32'd0;
                end else begin
                    sec <= sec + 32'd1;
                end
            end
        end
    end
endmodule
