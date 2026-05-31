// ============================================================================
//  input_buffer.v  -  4자리 입력 버퍼 / 4-digit shift-register buffer
// ----------------------------------------------------------------------------
//  숫자 키가 들어올 때마다 4-bit 단위로 좌측 시프트하여 최근 4자리를 보관한다.
//  (16-bit = 4-bit x 4자리)   buffer <= {buffer[11:0], key_code};
//    - cnt      : 현재까지 입력된 자릿수 (0~4, 4에서 포화)
//    - load_en  : 상위 FSM이 입력을 허용하는 상태(IDLE/INPUT/CHANGE)에서만 적재
//    - clr      : FSM 강제 초기화 펄스 (상태 전이/취소/완료 시)
//    - CLEAR 키(0xB)는 상태와 무관하게 버퍼를 비운다.
// ============================================================================
module input_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_stb,
    input  wire [3:0]  key_code,
    input  wire        load_en,
    input  wire        clr,
    output reg  [15:0] buffer,
    output reg  [2:0]  cnt
);
    wire is_digit     = key_stb && (key_code <= 4'd9);
    wire is_clear_key = key_stb && (key_code == 4'hB);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= 16'd0;
            cnt    <= 3'd0;
        end else if (clr || is_clear_key) begin
            buffer <= 16'd0;
            cnt    <= 3'd0;
        end else if (is_digit && load_en && cnt < 3'd4) begin
            buffer <= {buffer[11:0], key_code};
            cnt    <= cnt + 3'd1;
        end
    end
endmodule
