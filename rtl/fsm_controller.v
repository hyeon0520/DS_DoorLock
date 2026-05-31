// ============================================================================
//  fsm_controller.v  -  메인 상태 머신 / Main FSM
// ----------------------------------------------------------------------------
//  6개 상태로 디지털 도어락 전체 흐름을 제어한다.
//    IDLE   (0) : 초기 대기. 숫자 키 입력 시 INPUT 진입.
//    INPUT  (1) : 비밀번호 4자리 입력. ENTER & 4자리 -> CHECK, CLEAR -> IDLE.
//    CHECK  (2) : 채점(pw_check 펄스). CHECK_HOLD 동안 "Checking..." 표시 후 분기.
//                   일치        -> UNLOCK
//                   불일치&3회   -> ALARM
//                   불일치       -> IDLE (버퍼 초기화)
//    UNLOCK (3) : 잠금 해제(unlock_sig=1). 자동 잠금 타임아웃/CLEAR -> IDLE.
//                   CHANGE 키 -> CHANGE (비밀번호 변경 모드).
//    ALARM  (4) : 경보(alarm_sig=1). CLEAR/Reset -> IDLE (실패 카운터 초기화).
//    CHANGE (5) : 새 비밀번호 4자리 입력 후 ENTER -> 저장(pw_commit) -> IDLE.
//
//  비밀번호 비교 결과(match)는 INPUT->CHECK 전이 순간에 match_r 로 래치한다.
//  실패 카운터(fail_cnt)는 password_logic 이 pw_check 펄스에서 갱신하므로,
//  CHECK_HOLD 만료 시점에는 이미 "이번 시도 반영 후" 값이다 => fail_cnt==3 이면 ALARM.
// ============================================================================
module fsm_controller #(
    parameter integer CHECK_HOLD = 300_000   // CHECK 표시 유지 사이클 (~0.3s @1MHz)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        key_stb,
    input  wire [3:0]  key_code,
    input  wire [2:0]  input_cnt,
    input  wire        match,
    input  wire [1:0]  fail_cnt,
    input  wire        lock_timeout,
    output reg  [2:0]  state,
    output reg         pw_check,
    output reg         pw_commit,
    output reg         fail_clr,
    output reg         buf_clr,
    output reg         unlock_sig,
    output reg         alarm_sig
);
    localparam S_IDLE   = 3'd0,
               S_INPUT  = 3'd1,
               S_CHECK  = 3'd2,
               S_UNLOCK = 3'd3,
               S_ALARM  = 3'd4,
               S_CHANGE = 3'd5;

    localparam K_ENTER  = 4'hA,
               K_CLEAR  = 4'hB,
               K_CHANGE = 4'hC;

    wire is_digit  = key_stb && (key_code <= 4'd9);
    wire is_enter  = key_stb && (key_code == K_ENTER);
    wire is_clear  = key_stb && (key_code == K_CLEAR);
    wire is_change = key_stb && (key_code == K_CHANGE);

    reg  [2:0]  nstate;
    reg  [31:0] hold;
    reg         match_r;

    // ---- sequential: state, CHECK hold counter, match latch ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            hold    <= 32'd0;
            match_r <= 1'b0;
        end else begin
            state <= nstate;
            // latch comparison the moment we enter CHECK (buffer holds the attempt)
            if (state != S_CHECK && nstate == S_CHECK) begin
                match_r <= match;
                hold    <= 32'd0;
            end else if (state == S_CHECK) begin
                hold <= hold + 32'd1;
            end else begin
                hold <= 32'd0;
            end
        end
    end

    // ---- combinational: next-state & control outputs ----
    always @(*) begin
        nstate     = state;
        pw_check   = 1'b0;
        pw_commit  = 1'b0;
        fail_clr   = 1'b0;
        buf_clr    = 1'b0;
        unlock_sig = 1'b0;
        alarm_sig  = 1'b0;

        case (state)
            S_IDLE: begin
                if (is_digit) nstate = S_INPUT;     // 첫 숫자 입력으로 진입
            end

            S_INPUT: begin
                if (is_clear) begin
                    nstate  = S_IDLE;
                    buf_clr = 1'b1;
                end else if (is_enter && input_cnt == 3'd4) begin
                    nstate = S_CHECK;
                end
            end

            S_CHECK: begin
                if (hold == 32'd0) pw_check = 1'b1;  // 진입 첫 사이클에만 1회 채점
                if (hold >= CHECK_HOLD-1) begin
                    if (match_r)             nstate = S_UNLOCK;
                    else if (fail_cnt >= 2'd3) nstate = S_ALARM;
                    else begin
                        nstate  = S_IDLE;
                        buf_clr = 1'b1;
                    end
                end
            end

            S_UNLOCK: begin
                unlock_sig = 1'b1;
                if (is_change) begin
                    nstate  = S_CHANGE;
                    buf_clr = 1'b1;
                end else if (lock_timeout || is_clear) begin
                    nstate  = S_IDLE;
                    buf_clr = 1'b1;
                end
            end

            S_ALARM: begin
                alarm_sig = 1'b1;
                if (is_clear) begin
                    nstate   = S_IDLE;
                    buf_clr  = 1'b1;
                    fail_clr = 1'b1;
                end
            end

            S_CHANGE: begin
                if (is_clear) begin
                    nstate  = S_IDLE;
                    buf_clr = 1'b1;
                end else if (is_enter && input_cnt == 3'd4) begin
                    pw_commit = 1'b1;
                    fail_clr  = 1'b1;
                    nstate    = S_IDLE;
                    buf_clr   = 1'b1;
                end
            end

            default: nstate = S_IDLE;
        endcase
    end
endmodule
