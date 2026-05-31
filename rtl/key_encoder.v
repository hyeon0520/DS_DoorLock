// ============================================================================
//  key_encoder.v  -  키 인코더 / 16-button key encoder
// ----------------------------------------------------------------------------
//  16개 푸시버튼을 각각 디바운싱 -> 상승 엣지 검출 -> 우선순위 인코딩하여
//  한 사이클짜리 키 스트로브(key_stb)와 4-bit 키 코드(key_code)를 출력한다.
//
//  버튼 인덱스 -> 키 코드 매핑 (보드 BUTTON_SW1~SWF)
//    btn[0]  ~ btn[9]  : 숫자 0 ~ 9   (key_code = 0x0 ~ 0x9)
//    btn[10]           : ENTER        (key_code = 0xA)
//    btn[11]           : CLEAR        (key_code = 0xB)
//    btn[12]           : CHANGE(관리자) (key_code = 0xC)
//    btn[13..15]       : 예약/미사용   (0xD~0xF, 상위 모듈에서 무시)
//  key_code == 0xF 는 "키 없음(NONE)"을 의미.
// ============================================================================
module key_encoder #(
    parameter integer STABLE_CYCLES = 20_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] btn,
    output reg         key_stb,
    output reg  [3:0]  key_code
);
    wire [15:0] db;       // debounced levels
    reg  [15:0] db_q;     // delayed for edge detect
    wire [15:0] rise = db & ~db_q;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_debounce
            debouncer #(.STABLE_CYCLES(STABLE_CYCLES)) u_db (
                .clk   (clk),
                .rst_n (rst_n),
                .din   (btn[i]),
                .dout  (db[i])
            );
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) db_q <= 16'd0;
        else        db_q <= db;
    end

    // priority encode the lowest-index rising edge
    integer j;
    reg [3:0] code;
    reg       found;
    always @(*) begin
        code  = 4'hF;
        found = 1'b0;
        for (j = 0; j < 16; j = j + 1) begin
            if (!found && rise[j]) begin
                code  = j[3:0];
                found = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_stb  <= 1'b0;
            key_code <= 4'hF;
        end else begin
            key_stb  <= found;
            key_code <= code;
        end
    end
endmodule
