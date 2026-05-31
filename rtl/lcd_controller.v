// ============================================================================
//  lcd_controller.v  -  16x2 Character LCD 드라이버 (HD44780, 8-bit)
//  담당: 권우현 (LCD 16x2 출력 모듈)
// ----------------------------------------------------------------------------
//  기능
//    1) 초기화 시퀀스 : 전원 ON 대기 -> Function Set(8-bit/2-line/5x8)
//                       -> Display OFF -> Clear -> Entry Mode -> Display ON
//    2) 드라이버      : RS/RW/E 타이밍 생성, Enable 펄스 폭 보장, DDRAM 주소 지정,
//                       ASCII 데이터 전송 (Command/Data write 분리)
//    3) 상태별 메시지 : fsm_state(+input_cnt)에 따라 32바이트(2행x16) 자동 갱신
//
//  화면 매핑 (FSM 상태 -> LCD 2행)
//    IDLE   : "** DIGITAL LOCK " / "Enter Password  "
//    INPUT  : "Password:       " / 입력 자릿수만큼 '*' 표시
//    CHECK  : "Checking...     " / "Please wait     "
//    UNLOCK : "ACCESS GRANTED  " / "Welcome!        "
//    ALARM  : "!! WARNING !!   " / "3 Failed Tries  "
//    CHANGE : "New Password?   " / "Enter New PW    "
//
//  내부 구조 : (a) 메시지 렌더러(조합) (b) 바이트 전송 엔진 (c) 시퀀서
//  타이밍은 CLK_HZ 로부터 계산되어 1MHz~수십MHz 어떤 입력에도 자동 대응한다.
// ============================================================================
module lcd_controller #(
    parameter integer CLK_HZ = 1_000_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [2:0]  state,       // FSM 현재 상태
    input  wire [2:0]  input_cnt,   // 입력 자릿수 (0~4) -> '*' 개수
    output reg         lcd_rs,      // 0=command, 1=data
    output wire        lcd_rw,      // 항상 0 (write only)
    output reg         lcd_e,       // enable strobe
    output reg  [7:0]  lcd_data     // DB0~DB7
);
    assign lcd_rw = 1'b0;

    // ---- 타이밍 (cycles) : 최소 1 보장 ----
    localparam integer C_PWRON = (CLK_HZ/50)      + 1;  // ~20ms 전원안정
    localparam integer C_INIT  = (CLK_HZ/200)     + 1;  // ~5ms  초기 function set 간격
    localparam integer C_CLEAR = (CLK_HZ/500)     + 1;  // ~2ms  Clear/Home 실행시간
    localparam integer C_EXEC  = (CLK_HZ/20000)   + 1;  // ~50us 일반 명령/데이터 실행
    localparam integer C_EN    = (CLK_HZ/2000000) + 1;  // Enable High 폭 (>=230ns) 최소1

    // ---- FSM 상태 코드 ----
    localparam S_IDLE   = 3'd0, S_INPUT = 3'd1, S_CHECK = 3'd2,
               S_UNLOCK = 3'd3, S_ALARM = 3'd4, S_CHANGE = 3'd5;

    // =====================================================================
    //  (a) 메시지 렌더러 : state/input_cnt -> 16글자(128bit) 2줄
    //      문자열 리터럴은 정확히 16글자 = 128bit. 좌측 글자가 MSB.
    // =====================================================================
    reg [127:0] l1, l2;
    reg [127:0] stars;
    integer k;
    always @(*) begin
        for (k = 0; k < 16; k = k + 1)
            stars[127-8*k -: 8] = ({1'b0,k[2:0]} < input_cnt) ? 8'h2A   // '*'
                                                              : 8'h20;  // space
        case (state)
            S_IDLE   : begin l1 = "** DIGITAL LOCK "; l2 = "Enter Password  "; end
            S_INPUT  : begin l1 = "Password:       "; l2 = stars;              end
            S_CHECK  : begin l1 = "Checking...     "; l2 = "Please wait     "; end
            S_UNLOCK : begin l1 = "ACCESS GRANTED  "; l2 = "Welcome!        "; end
            S_ALARM  : begin l1 = "!! WARNING !!   "; l2 = "3 Failed Tries  "; end
            S_CHANGE : begin l1 = "New Password?   "; l2 = "Enter New PW    "; end
            default  : begin l1 = "                "; l2 = "                "; end
        endcase
    end

    // 초기화 명령 ROM (index 0..7) 과 실행시간
    function [7:0] init_cmd;
        input [2:0] i;
        case (i)
            3'd0, 3'd1, 3'd2 : init_cmd = 8'h30; // wake-up function set
            3'd3             : init_cmd = 8'h38; // 8-bit, 2-line, 5x8
            3'd4             : init_cmd = 8'h08; // display off
            3'd5             : init_cmd = 8'h01; // clear display
            3'd6             : init_cmd = 8'h06; // entry mode: increment, no shift
            3'd7             : init_cmd = 8'h0C; // display on, cursor off, blink off
            default          : init_cmd = 8'h00;
        endcase
    endfunction

    function [31:0] init_exec;
        input [2:0] i;
        case (i)
            3'd0, 3'd1 : init_exec = C_INIT;   // 첫 wake-up 간격 길게
            3'd5       : init_exec = C_CLEAR;  // clear 는 ~1.5ms+
            default    : init_exec = C_EXEC;
        endcase
    endfunction

    // RUN 단계의 step(0..33) -> (rs,data)
    //   0      : set DDRAM addr line1 (0x80)
    //   1..16  : line1 데이터 16글자
    //   17     : set DDRAM addr line2 (0xC0)
    //   18..33 : line2 데이터 16글자
    function [7:0] run_data;
        input [5:0] s;
        if      (s == 6'd0)  run_data = 8'h80;
        else if (s <= 6'd16) run_data = l1[127 - 8*(s-1) -: 8];
        else if (s == 6'd17) run_data = 8'hC0;
        else                 run_data = l2[127 - 8*(s-18) -: 8];
    endfunction

    function run_rs;
        input [5:0] s;
        run_rs = !((s == 6'd0) || (s == 6'd17)); // 0,17 은 command, 나머지 data
    endfunction

    // =====================================================================
    //  (b) 바이트 전송 엔진 : req/busy 핸드셰이크로 1바이트 write 수행
    //      SET(setup) -> EHI(E high) -> ELO(E low) -> WAIT(exec) -> done
    // =====================================================================
    reg        bw_req;
    reg        bw_rs;
    reg [7:0]  bw_data;
    reg [31:0] bw_exec;
    reg        eng_busy;
    reg [2:0]  es;
    reg [31:0] ecnt, eexec;
    localparam E_IDLE = 3'd0, E_SET = 3'd1, E_EHI = 3'd2, E_ELO = 3'd3, E_WAIT = 3'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            es <= E_IDLE; eng_busy <= 1'b0;
            lcd_e <= 1'b0; lcd_rs <= 1'b0; lcd_data <= 8'h00;
            ecnt <= 32'd0; eexec <= 32'd0;
        end else begin
            case (es)
                E_IDLE: begin
                    lcd_e <= 1'b0;
                    if (bw_req) begin
                        eng_busy <= 1'b1;
                        lcd_rs   <= bw_rs;
                        lcd_data <= bw_data;
                        eexec    <= bw_exec;
                        ecnt     <= 32'd0;
                        es       <= E_SET;
                    end
                end
                E_SET:  begin lcd_e <= 1'b0; ecnt <= 32'd0; es <= E_EHI; end // setup time
                E_EHI:  begin
                    lcd_e <= 1'b1;
                    if (ecnt >= C_EN-1) begin ecnt <= 32'd0; es <= E_ELO; end
                    else ecnt <= ecnt + 32'd1;
                end
                E_ELO:  begin lcd_e <= 1'b0; ecnt <= 32'd0; es <= E_WAIT; end
                E_WAIT: begin
                    if (ecnt >= eexec-1) begin es <= E_IDLE; eng_busy <= 1'b0; end
                    else ecnt <= ecnt + 32'd1;
                end
                default: es <= E_IDLE;
            endcase
        end
    end

    // =====================================================================
    //  (c) 시퀀서 : 전원대기 -> 초기화 -> RUN(메시지 갱신, 변화 시 재출력)
    //      iss 핸드셰이크 : 0=요청, 1=수락대기(busy=1), 2=완료대기(busy=0), 3=변화대기
    // =====================================================================
    localparam P_PWRON = 2'd0, P_INIT = 2'd1, P_RUN = 2'd2;
    reg [1:0]  phase;
    reg [1:0]  iss;
    reg [5:0]  step;
    reg [31:0] dly;
    reg [2:0]  prev_state;
    reg [2:0]  prev_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= P_PWRON; iss <= 2'd0; step <= 6'd0; dly <= 32'd0;
            bw_req <= 1'b0; bw_rs <= 1'b0; bw_data <= 8'h00; bw_exec <= 32'd0;
            prev_state <= 3'd7; prev_cnt <= 3'd7;
        end else begin
            case (phase)
                // ---- 전원 안정 대기 ----
                P_PWRON: begin
                    if (dly >= C_PWRON-1) begin dly <= 32'd0; phase <= P_INIT; step <= 6'd0; iss <= 2'd0; end
                    else dly <= dly + 32'd1;
                end

                // ---- 초기화 명령 8개 ----
                P_INIT: begin
                    case (iss)
                        2'd0: begin
                            bw_rs   <= 1'b0;
                            bw_data <= init_cmd(step[2:0]);
                            bw_exec <= init_exec(step[2:0]);
                            bw_req  <= 1'b1;
                            iss     <= 2'd1;
                        end
                        2'd1: if (eng_busy) begin bw_req <= 1'b0; iss <= 2'd2; end
                        2'd2: if (!eng_busy) begin
                                  if (step >= 6'd7) begin
                                      phase <= P_RUN; step <= 6'd0; iss <= 2'd0;
                                      prev_state <= 3'd7; prev_cnt <= 3'd7;
                                  end else begin
                                      step <= step + 6'd1; iss <= 2'd0;
                                  end
                              end
                        default: iss <= 2'd0;
                    endcase
                end

                // ---- 화면 출력 / 변화 감지 ----
                P_RUN: begin
                    case (iss)
                        2'd0: begin
                            bw_rs   <= run_rs(step);
                            bw_data <= run_data(step);
                            bw_exec <= C_EXEC;
                            bw_req  <= 1'b1;
                            iss     <= 2'd1;
                        end
                        2'd1: if (eng_busy) begin bw_req <= 1'b0; iss <= 2'd2; end
                        2'd2: if (!eng_busy) begin
                                  if (step >= 6'd33) begin
                                      step       <= 6'd0;
                                      prev_state <= state;
                                      prev_cnt   <= input_cnt;
                                      iss        <= 2'd3;        // 한 화면 완료 -> 변화대기
                                  end else begin
                                      step <= step + 6'd1; iss <= 2'd0;
                                  end
                              end
                        2'd3: begin                                // 상태/자릿수 변하면 재출력
                            if (state != prev_state || input_cnt != prev_cnt) begin
                                step <= 6'd0; iss <= 2'd0;
                            end
                        end
                    endcase
                end

                default: phase <= P_PWRON;
            endcase
        end
    end
endmodule
