// ============================================================================
//  clock_divider.v  -  클럭 분주기 / Clock & tick generator
// ----------------------------------------------------------------------------
//  보드 입력 클럭(기본 1MHz)으로부터 시스템 전반에서 사용하는 tick 들을 생성.
//    - tick_1khz : FND 스캔 / 디바운스 샘플링용 1kHz 단일-사이클 펄스
//    - tick_1hz  : 자동 잠금 타이머용 1Hz 단일-사이클 펄스
//    - blink     : 경보(ALARM) LED 점멸용 ~3Hz 토글 레벨
//  CLK_HZ 파라미터만 바꾸면 어떤 입력 주파수에도 대응 (시뮬레이션 시 축소 가능)
// ============================================================================
module clock_divider #(
    parameter integer CLK_HZ = 1_000_000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick_1khz,
    output reg  tick_1hz,
    output reg  blink
);
    localparam integer DIV_1KHZ  = (CLK_HZ/1000 > 0) ? CLK_HZ/1000 : 1;
    localparam integer DIV_1HZ   = (CLK_HZ      > 0) ? CLK_HZ      : 1;
    localparam integer DIV_BLINK = (CLK_HZ/6    > 0) ? CLK_HZ/6    : 1; // ~3Hz 토글

    reg [31:0] c_1khz, c_1hz, c_blink;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_1khz <= 32'd0; tick_1khz <= 1'b0;
        end else if (c_1khz >= DIV_1KHZ-1) begin
            c_1khz <= 32'd0; tick_1khz <= 1'b1;
        end else begin
            c_1khz <= c_1khz + 32'd1; tick_1khz <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_1hz <= 32'd0; tick_1hz <= 1'b0;
        end else if (c_1hz >= DIV_1HZ-1) begin
            c_1hz <= 32'd0; tick_1hz <= 1'b1;
        end else begin
            c_1hz <= c_1hz + 32'd1; tick_1hz <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c_blink <= 32'd0; blink <= 1'b0;
        end else if (c_blink >= DIV_BLINK-1) begin
            c_blink <= 32'd0; blink <= ~blink;
        end else begin
            c_blink <= c_blink + 32'd1;
        end
    end
endmodule
