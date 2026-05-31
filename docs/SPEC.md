# 디지털 도어락 시스템 — 설계 명세서 (Specification)

- **프로젝트:** FPGA 기반 디지털 금고 / 도어락 시스템
- **보드:** HBE-Combo-II-SE (Altera Cyclone II `EP2C8Q208C8` / Xilinx Spartan-3 `XC3S200`)
- **언어:** Verilog HDL (IEEE 1364-2001)
- **기본 클럭:** 1 MHz (보드 제공: 1MHz / 1kHz / 1Hz)
- **문서 버전:** 1.0

---

## 1. 요구사항 명세

### 1.1 기능 요구사항 (FR)

| ID | 요구사항 | 검증 방법 |
|----|----------|-----------|
| FR-1 | 4자리 비밀번호를 버튼으로 입력받는다 | tb 시나리오 A |
| FR-2 | 입력값이 등록 비밀번호와 일치하면 잠금 해제한다 | tb 시나리오 A |
| FR-3 | 불일치 시 실패 횟수를 1 증가시킨다 | tb 시나리오 B |
| FR-4 | 연속 3회 실패 시 경보(ALARM) 상태로 진입한다 | tb 시나리오 B |
| FR-5 | UNLOCK 후 일정 시간 경과 시 자동으로 잠긴다 | tb 시나리오 A |
| FR-6 | UNLOCK 상태에서 비밀번호를 변경할 수 있다 | tb 시나리오 C |
| FR-7 | 입력 자릿수를 `*`로 마스킹 표시한다 | LCD/FND 파형 |
| FR-8 | 상태별 메시지를 LCD 16×2에 출력한다 | tb_lcd 로그 |
| FR-9 | 경보 시 LED 전체 점멸 + 부저음을 출력한다 | 파형/보드 |

### 1.2 비기능 요구사항 (NFR)

| ID | 요구사항 |
|----|----------|
| NFR-1 | 버튼 디바운싱 ≥ 20 ms 안정 후 인식 |
| NFR-2 | LCD Enable 펄스 폭 ≥ 230 ns, Clear/Home 실행시간 ≥ 1.52 ms 준수 |
| NFR-3 | FND 스캔 주파수 ~1 kHz (잔상으로 동시 점등 효과) |
| NFR-4 | 모든 타이밍은 `CLK_HZ` 파라미터로부터 계산되어 클럭 독립적 |
| NFR-5 | 합성 가능(synthesizable) RTL, 래치/멀티드라이버 없음 |

---

## 2. 시스템 파라미터

| 파라미터 | 위치 | 기본값 | 설명 |
|----------|------|--------|------|
| `CLK_HZ`       | top/하위 | `1_000_000` | 입력 클럭 주파수 |
| `DEFAULT_PW`   | top/password_logic | `16'h1234` | 초기 비밀번호(4 nibble) |
| `LOCK_SECONDS` | top/auto_lock_timer | `10` | 자동 잠금 시간(초) |
| `CHECK_HOLD`   | fsm_controller | `CLK_HZ/3` | CHECK 화면 유지 사이클 |
| `STABLE_CYCLES`| debouncer | `CLK_HZ/50` | 디바운스 안정 시간(20ms) |
| `TONE_HZ`      | piezo_controller | `1000` | 부저 톤 주파수 |
| `BEEP_MS`      | piezo_controller | `50` | 키 비프음 길이 |

---

## 3. 상태 / 키 코드 정의

### 3.1 FSM 상태 인코딩

| 코드 | 상태 | 의미 |
|------|------|------|
| `3'd0` | IDLE   | 초기 대기 |
| `3'd1` | INPUT  | 비밀번호 입력 중 |
| `3'd2` | CHECK  | 비밀번호 채점/표시 |
| `3'd3` | UNLOCK | 잠금 해제 |
| `3'd4` | ALARM  | 경보 |
| `3'd5` | CHANGE | 비밀번호 변경 |

### 3.2 키 코드 (`key_code[3:0]`)

| 코드 | 키 | 버튼 |
|------|----|----|
| `0x0~0x9` | 숫자 0~9 | `btn[0..9]` |
| `0xA` | ENTER | `btn[10]` |
| `0xB` | CLEAR | `btn[11]` |
| `0xC` | CHANGE | `btn[12]` |
| `0xF` | NONE | — |

---

## 4. FSM 상태 전이표

| 현재 | 조건 | 다음 | 출력/액션 |
|------|------|------|-----------|
| IDLE   | 숫자키 | INPUT  | 첫 자리 적재 |
| INPUT  | CLEAR | IDLE | `buf_clr` |
| INPUT  | ENTER & `cnt==4` | CHECK | `match` 래치 |
| CHECK  | 진입 1cycle | (CHECK) | `pw_check` 펄스 |
| CHECK  | `hold==CHECK_HOLD` & `match` | UNLOCK | — |
| CHECK  | `hold==CHECK_HOLD` & `fail_cnt==3` | ALARM | — |
| CHECK  | `hold==CHECK_HOLD` & 불일치(<3) | IDLE | `buf_clr` |
| UNLOCK | CHANGE | CHANGE | `buf_clr` |
| UNLOCK | `lock_timeout` 또는 CLEAR | IDLE | `buf_clr` |
| ALARM  | CLEAR/Reset | IDLE | `buf_clr`, `fail_clr` |
| CHANGE | CLEAR | IDLE | `buf_clr` (취소) |
| CHANGE | ENTER & `cnt==4` | IDLE | `pw_commit`, `fail_clr`, `buf_clr` |

> **실패 카운터 타이밍:** `pw_check`는 CHECK 진입 1사이클에 1회 펄스되어
> `password_logic`가 같은 시점에 `fail_cnt`를 갱신한다. 따라서 `CHECK_HOLD`
> 만료 시점의 `fail_cnt`는 "이번 시도가 반영된" 값이며, `==3`이면 ALARM이다.

---

## 5. 모듈별 포트 명세

### 5.1 doorlock_top
> 5장 README의 Top Port 표 참조. 파라미터: `CLK_HZ`, `DEFAULT_PW`, `LOCK_SECONDS`.

### 5.2 clock_divider
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| clk, rst_n | in | 1 | |
| tick_1khz | out | 1 | 1kHz 단일-사이클 펄스 |
| tick_1hz | out | 1 | 1Hz 단일-사이클 펄스 |
| blink | out | 1 | ~3Hz 토글 레벨(경보 점멸) |

### 5.3 debouncer / key_encoder
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| din / btn | in | 1 / 16 | 원시 버튼 입력 |
| dout | out | 1 | (debouncer) 안정 레벨 |
| key_stb | out | 1 | (encoder) 1-cycle 키 스트로브 |
| key_code | out | 4 | (encoder) 키 코드 |

### 5.4 input_buffer
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| key_stb, key_code | in | 1,4 | 키 입력 |
| load_en | in | 1 | 적재 허용(IDLE/INPUT/CHANGE) |
| clr | in | 1 | 강제 초기화 펄스 |
| buffer | out | 16 | 최근 4자리 (4-bit×4) |
| cnt | out | 3 | 입력 자릿수(0~4) |

### 5.5 password_logic
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| buffer | in | 16 | 입력값 |
| pw_check | in | 1 | 채점 펄스 |
| pw_commit | in | 1 | 새 비번 저장 펄스 |
| fail_clr | in | 1 | 실패 카운터 초기화 |
| match | out | 1 | 일치(조합) |
| fail_cnt | out | 2 | 실패 횟수(0~3) |

### 5.6 auto_lock_timer
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| enable | in | 1 | UNLOCK 상태에서 1 |
| tick_1hz | in | 1 | 1Hz 펄스 |
| timeout | out | 1 | LOCK_SECONDS 경과 펄스 |

### 5.7 fsm_controller
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| key_stb, key_code | in | 1,4 | 키 입력 |
| input_cnt | in | 3 | 자릿수 |
| match | in | 1 | 비교 결과 |
| fail_cnt | in | 2 | 실패 횟수 |
| lock_timeout | in | 1 | 자동 잠금 신호 |
| state | out | 3 | 현재 상태 |
| pw_check/pw_commit/fail_clr/buf_clr | out | 1 | 제어 펄스 |
| unlock_sig/alarm_sig | out | 1 | 해제/경보 신호 |

### 5.8 lcd_controller ★ (담당: 권우현)
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| state | in | 3 | 메시지 선택 |
| input_cnt | in | 3 | `*` 개수 |
| lcd_rs | out | 1 | 0=cmd, 1=data |
| lcd_rw | out | 1 | 항상 0 (write) |
| lcd_e | out | 1 | enable strobe |
| lcd_data | out | 8 | DB0~DB7 |

### 5.9 fnd_controller / led_controller / piezo_controller
| 포트 | 방향 | 비트 | 설명 |
|------|------|------|------|
| seg | out | 8 | `{dp,g,f,e,d,c,b,a}` active-H |
| com | out | 4 | 자리 선택 active-L |
| led | out | 16 | LED 상태 |
| alarm, key_stb | in | 1 | 경보/키 입력 |
| piezo | out | 1 | 부저 |

---

## 6. LCD (HD44780) 초기화 & 드라이버 명세

### 6.1 초기화 시퀀스

| # | 명령 | 코드 | 실행시간 | 설명 |
|---|------|------|----------|------|
| 0 | 전원 안정 | — | ≥ 15 ms (구현 20ms) | Power-on wait |
| 1 | Function Set | `0x30` | ~5 ms | wake-up #1 |
| 2 | Function Set | `0x30` | ~5 ms | wake-up #2 |
| 3 | Function Set | `0x30` | ~50 µs | wake-up #3 |
| 4 | Function Set | `0x38` | ~50 µs | 8-bit, 2-line, 5×8 |
| 5 | Display OFF | `0x08` | ~50 µs | |
| 6 | Clear Display | `0x01` | ~2 ms | DDRAM clear |
| 7 | Entry Mode | `0x06` | ~50 µs | 증가, no shift |
| 8 | Display ON | `0x0C` | ~50 µs | 커서 off, blink off |

### 6.2 데이터 쓰기 타이밍 (byte engine)

```
RS ──< valid >─────────────────
DB ──< valid >─────────────────
E  ___╱▔▔▔╲___________  (E High ≥ C_EN 사이클, ≥230ns)
        └ tEN ┘ └─ 실행시간 대기(eexec) ─┘
```

타이밍 상수(@1MHz): `C_PWRON≈20000`, `C_INIT≈5000`, `C_CLEAR≈2000`,
`C_EXEC≈51`, `C_EN≈1`. 모두 `CLK_HZ`에서 자동 계산.

### 6.3 화면 갱신 정책
- RUN 단계에서 `step 0..33`: `0`→DDRAM `0x80`(1행), `1..16`→1행 16글자,
  `17`→DDRAM `0xC0`(2행), `18..33`→2행 16글자.
- 한 화면을 다 쓰면 `state`/`input_cnt` 변화를 감시(`iss=3`)하다가
  변하면 처음(step 0)부터 재출력 → **상태가 바뀔 때만 갱신**(깜빡임 없음).

### 6.4 상태별 메시지 (각 행 정확히 16글자)

| State | Line 1 | Line 2 |
|-------|--------|--------|
| IDLE | `** DIGITAL LOCK ` | `Enter Password  ` |
| INPUT | `Password:       ` | `*`×cnt + 공백 |
| CHECK | `Checking...     ` | `Please wait     ` |
| UNLOCK | `ACCESS GRANTED  ` | `Welcome!        ` |
| ALARM | `!! WARNING !!   ` | `3 Failed Tries  ` |
| CHANGE | `New Password?   ` | `Enter New PW    ` |

---

## 7. 핀 매핑 (Pin Assignment) — 보드 매뉴얼 기준 확정 필요

> ⚠️ 아래는 **양식 예시**다. HBE-Combo-II-SE User Guide의 실제 핀 할당표로
> 1주차에 확정한 뒤 채워 Quartus Pin Planner / `.qsf`에 반영한다.

| 신호 | FPGA 핀 | 비고 |
|------|---------|------|
| clk (1MHz) | `PIN_____` | 보드 클럭 소스 |
| rst_n | `PIN_____` | Reset 버튼(Low active) |
| btn[0..15] | `PIN_____` × 16 | Push button SW1~SWF |
| dip[0..7] | `PIN_____` × 8 | Bus SW |
| lcd_rs / lcd_rw / lcd_e | `PIN_____` | LCD 제어 |
| lcd_data[0..7] | `PIN_____` × 8 | CLCD_D0~D7 |
| fnd_seg[0..7] | `PIN_____` × 8 | a~g, dp |
| fnd_com[0..3] | `PIN_____` × 4 | 4-digit 공통단 |
| led[0..15] | `PIN_____` × 16 | LED1~LED16 |
| piezo | `PIN_____` | Buzzer |

---

## 8. 테스트 계획

| TC | 모듈 | 시나리오 | 기대 결과 |
|----|------|----------|-----------|
| TC-1 | top | `1234`+ENTER | IDLE→INPUT→CHECK→UNLOCK |
| TC-2 | top | UNLOCK 후 대기 | LOCK_SECONDS 후 IDLE |
| TC-3 | top | 오답 3회 | ALARM 진입, fail_cnt=3 |
| TC-4 | top | ALARM에서 CLEAR | IDLE, fail_cnt=0 |
| TC-5 | top | 변경 `5678` 후 재입력 | 새 비번으로 UNLOCK |
| TC-6 | lcd | 초기화 | `0x30/0x38/0x08/0x01/0x06/0x0C` 순서 |
| TC-7 | lcd | state=INPUT, cnt=1→3 | 2행 `*` 개수 변화 |
| TC-8 | lcd | state 변경 | 화면 자동 재출력 |

테스트벤치: `tb/tb_doorlock_top.v`(TC-1~5), `tb/tb_lcd_controller.v`(TC-6~8).
시뮬레이션 가속을 위해 `CLK_HZ=10_000`, `LOCK_SECONDS=2`로 축소 구동.

---

## 9. 향후 확장 (Optional)

- **PS/2 키보드 입력**: 버튼 대신 실제 키보드로 비밀번호 입력 (매뉴얼 PS2_CLK/DATA).
- **변경 시 재확인(2회 입력 일치)**: CHANGE 상태를 `NEW`/`CONFIRM` 서브상태로 분리.
- **현재 비번 확인 후 변경**: 변경 진입 전 기존 비번 1회 검증.
- **모터/솔레노이드 제어**: `unlock_sig`를 별도 GPIO로 출력해 실제 잠금장치 구동.
- **SRAM 활용**: 입출입 이력 저장.
