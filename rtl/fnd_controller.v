// ============================================================================
//  fnd_controller.v  -  4자리 FND(7-Segment) 드라이버 + 마스킹
// ----------------------------------------------------------------------------
//  4개의 Common-Cathode FND 를 ~1kHz 로 시분할 스캔(멀티플렉싱)하여
//  잔상 효과로 동시에 켜진 것처럼 표시한다.
//  비밀번호 노출 방지를 위해 입력된 자릿수만큼 숫자 대신 '*'(전 세그먼트 점등)
//  마스킹을 표시한다. (INPUT / CHANGE / CHECK 상태에서만 표시)
//
//  seg : {dp,g,f,e,d,c,b,a}  active-HIGH (1=점등)
//  com : 4자리 선택, active-LOW (0=선택된 자리)  -- Common Cathode 가정
// ============================================================================
module fnd_controller (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_1khz,
    input  wire [2:0]  state,
    input  wire [2:0]  input_cnt,   // 0~4
    output reg  [7:0]  seg,
    output reg  [3:0]  com
);
    localparam S_INPUT = 3'd1, S_CHECK = 3'd2, S_CHANGE = 3'd5;
    localparam [7:0] MASK  = 8'b0111_1111;  // a~g 전점등 (dp off) => '*' 형태
    localparam [7:0] BLANK = 8'b0000_0000;

    reg [1:0] scan;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        scan <= 2'd0;
        else if (tick_1khz) scan <= scan + 2'd1;
    end

    wire show = (state == S_INPUT) || (state == S_CHANGE) || (state == S_CHECK);
    wire lit  = ({1'b0, scan} < input_cnt);  // 현재 스캔 자리 < 입력 자릿수

    always @(*) begin
        com         = 4'b1111;       // 모두 비선택
        com[scan]   = 1'b0;          // 현재 자리만 선택 (active-low)
        seg         = (show && lit) ? MASK : BLANK;
    end
endmodule
