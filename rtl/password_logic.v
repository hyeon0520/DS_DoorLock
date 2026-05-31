// ============================================================================
//  password_logic.v  -  비밀번호 비교 / 변경 / 실패 카운터
// ----------------------------------------------------------------------------
//  - stored   : 현재 등록된 4자리 비밀번호 (16-bit). 리셋 시 DEFAULT_PW.
//  - match    : 입력 버퍼와 저장값의 16-bit 병렬 비교 결과 (조합).
//  - fail_cnt : 연속 실패 횟수 (0~3). 3이 되면 ALARM 조건.
//
//  제어 펄스 (상위 FSM이 1-사이클 펄스로 구동)
//    - pw_check  : 이번 시도를 채점. 일치면 fail_cnt=0, 불일치면 fail_cnt+1(최대3).
//    - pw_commit : buffer 값을 새 비밀번호로 저장(비밀번호 변경).
//    - fail_clr  : 실패 카운터 0으로 초기화 (Reset/Clear).
// ============================================================================
module password_logic #(
    parameter [15:0] DEFAULT_PW = 16'h1234
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] buffer,
    input  wire        pw_check,
    input  wire        pw_commit,
    input  wire        fail_clr,
    output wire        match,
    output reg  [1:0]  fail_cnt
);
    reg [15:0] stored;

    assign match = (buffer == stored);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stored   <= DEFAULT_PW;
            fail_cnt <= 2'd0;
        end else begin
            if (pw_commit) stored <= buffer;

            if (fail_clr) begin
                fail_cnt <= 2'd0;
            end else if (pw_check) begin
                if (match)              fail_cnt <= 2'd0;
                else if (fail_cnt < 2'd3) fail_cnt <= fail_cnt + 2'd1;
            end
        end
    end
endmodule
