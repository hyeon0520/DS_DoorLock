// ============================================================================
//  doorlock_top.v  -  디지털 도어락 Top Module
//  Board : HBE-Combo-II-SE (Altera Cyclone II EP2C8Q208 / Xilinx Spartan-3)
// ----------------------------------------------------------------------------
//  4자리 비밀번호 입력으로 잠금/해제. 3회 오입력 시 경보(LED 점멸 + Piezo),
//  UNLOCK 상태에서 일정 시간 후 자동 잠금, 관리자 키로 비밀번호 변경 지원.
//
//  데이터 흐름
//    btn[16] --(debounce/encode)--> key_stb/key_code
//             --> input_buffer(buffer,cnt) --> password_logic(match,fail_cnt)
//             --> fsm_controller(state) --> {lcd,fnd,led,piezo} 출력
//
//  파라미터
//    CLK_HZ       : 입력 클럭 주파수 (기본 1MHz, 보드 기본 클럭)
//    DEFAULT_PW   : 초기 비밀번호 (16-bit = 4자리 x 4-bit BCD, 기본 0x1234)
//    LOCK_SECONDS : UNLOCK 자동 잠금까지의 시간(초)
// ============================================================================
module doorlock_top #(
    parameter integer CLK_HZ       = 1_000_000,
    parameter [15:0]  DEFAULT_PW   = 16'h1234,
    parameter integer LOCK_SECONDS = 10
)(
    input  wire        clk,        // 보드 클럭 (1MHz)
    input  wire        rst_n,      // 리셋 (Low active)
    input  wire [15:0] btn,        // 푸시버튼 16개
    input  wire [7:0]  dip,        // DIP 스위치 8bit (예약/모드용)

    output wire        lcd_rs,
    output wire        lcd_rw,
    output wire        lcd_e,
    output wire [7:0]  lcd_data,

    output wire [7:0]  fnd_seg,    // {dp,g,f,e,d,c,b,a}
    output wire [3:0]  fnd_com,    // 4자리 공통단 (active-low)

    output wire [15:0] led,
    output wire        piezo
);
    // 사용하지 않는 입력 (lint 방지용)
    wire _unused = &{dip, 1'b0};

    // ---- 상태 코드 (가독성) ----
    localparam S_IDLE = 3'd0, S_INPUT = 3'd1, S_UNLOCK = 3'd3, S_CHANGE = 3'd5;

    // ---- 내부 신호 ----
    wire        tick_1khz, tick_1hz, blink;
    wire        key_stb;
    wire [3:0]  key_code;
    wire [15:0] buffer;
    wire [2:0]  input_cnt;
    wire        match;
    wire [1:0]  fail_cnt;
    wire        lock_timeout;
    wire [2:0]  state;
    wire        pw_check, pw_commit, fail_clr, buf_clr, unlock_sig, alarm_sig;

    // 입력 적재 허용 상태: IDLE / INPUT / CHANGE
    wire load_en = (state == S_IDLE) || (state == S_INPUT) || (state == S_CHANGE);

    // ---- 클럭/틱 ----
    clock_divider #(.CLK_HZ(CLK_HZ)) u_div (
        .clk(clk), .rst_n(rst_n),
        .tick_1khz(tick_1khz), .tick_1hz(tick_1hz), .blink(blink)
    );

    // ---- 입력 처리 (디바운싱 + 키 인코딩) ----
    key_encoder #(.STABLE_CYCLES(CLK_HZ/50)) u_key (   // 20ms
        .clk(clk), .rst_n(rst_n), .btn(btn),
        .key_stb(key_stb), .key_code(key_code)
    );

    // ---- 4자리 입력 버퍼 ----
    input_buffer u_buf (
        .clk(clk), .rst_n(rst_n),
        .key_stb(key_stb), .key_code(key_code),
        .load_en(load_en), .clr(buf_clr),
        .buffer(buffer), .cnt(input_cnt)
    );

    // ---- 비밀번호 로직 ----
    password_logic #(.DEFAULT_PW(DEFAULT_PW)) u_pw (
        .clk(clk), .rst_n(rst_n), .buffer(buffer),
        .pw_check(pw_check), .pw_commit(pw_commit), .fail_clr(fail_clr),
        .match(match), .fail_cnt(fail_cnt)
    );

    // ---- 자동 잠금 타이머 ----
    auto_lock_timer #(.LOCK_SECONDS(LOCK_SECONDS)) u_tmr (
        .clk(clk), .rst_n(rst_n),
        .enable(state == S_UNLOCK), .tick_1hz(tick_1hz),
        .timeout(lock_timeout)
    );

    // ---- 메인 FSM ----
    fsm_controller #(.CHECK_HOLD(CLK_HZ/3)) u_fsm (   // ~0.3s 표시
        .clk(clk), .rst_n(rst_n),
        .key_stb(key_stb), .key_code(key_code), .input_cnt(input_cnt),
        .match(match), .fail_cnt(fail_cnt), .lock_timeout(lock_timeout),
        .state(state),
        .pw_check(pw_check), .pw_commit(pw_commit), .fail_clr(fail_clr),
        .buf_clr(buf_clr), .unlock_sig(unlock_sig), .alarm_sig(alarm_sig)
    );

    // ---- 출력: LCD (담당: 권우현) ----
    lcd_controller #(.CLK_HZ(CLK_HZ)) u_lcd (
        .clk(clk), .rst_n(rst_n),
        .state(state), .input_cnt(input_cnt),
        .lcd_rs(lcd_rs), .lcd_rw(lcd_rw), .lcd_e(lcd_e), .lcd_data(lcd_data)
    );

    // ---- 출력: FND 마스킹 ----
    fnd_controller u_fnd (
        .clk(clk), .rst_n(rst_n), .tick_1khz(tick_1khz),
        .state(state), .input_cnt(input_cnt),
        .seg(fnd_seg), .com(fnd_com)
    );

    // ---- 출력: LED ----
    led_controller u_led (
        .clk(clk), .rst_n(rst_n),
        .state(state), .input_cnt(input_cnt), .blink(blink),
        .led(led)
    );

    // ---- 출력: Piezo ----
    piezo_controller #(.CLK_HZ(CLK_HZ)) u_pz (
        .clk(clk), .rst_n(rst_n),
        .alarm(alarm_sig), .key_stb(key_stb),
        .piezo(piezo)
    );

    // unlock_sig 는 실제 모터/솔레노이드 제어용 별도 핀으로 뽑을 수 있음.
    // 본 보드 데모에서는 LED/LCD 로 해제 상태를 표현한다.
    wire _unused2 = unlock_sig;
endmodule
