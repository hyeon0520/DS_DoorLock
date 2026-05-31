# DS_DoorLock — FPGA 디지털 금고 / 도어락 시스템

> 디지털시스템설계 팀 프로젝트 · HBE-Combo-II-SE 보드 · **Verilog HDL**
> 4자리 비밀번호 입력으로 잠금/해제, 3회 오입력 시 경보(LED 점멸 + Piezo),
> UNLOCK 후 자동 잠금, 관리자 비밀번호 변경 지원.

---

## 1. 개요

FPGA를 활용해 비밀번호 인증 방식의 디지털 도어락을 설계/구현한다.
사용자가 입력한 4자리 비밀번호를 검증하여 문 개폐 여부를 제어하고,
LCD/FND/LED/Piezo로 상태를 시각·청각적으로 표현한다.

| 항목 | 내용 |
|------|------|
| 보드 | HBE-Combo-II-SE (Altera Cyclone II `EP2C8Q208` / Xilinx Spartan-3 `XC3S200`) |
| 기본 클럭 | 1 MHz (보드 제공: 1MHz / 1kHz / 1Hz) |
| 설계 언어 | Verilog HDL (Verilog-2001) |
| 입력 | 푸시버튼 16개 (0~9, Enter, Clear, Change), DIP 8bit(예약) |
| 출력 | Character LCD 16×2, FND 4-digit, LED 16개, Piezo Buzzer |
| 기본 비밀번호 | `1234` (파라미터 `DEFAULT_PW`로 변경 가능) |

---

## 2. 주요 기능

- **4자리 비밀번호 입력** — 버튼 디바운싱 → 키 인코딩 → 4-bit×4 시프트 버퍼
- **잠금/해제** — `match` 일치 시 UNLOCK, LCD `ACCESS GRANTED`
- **3회 오입력 경보** — `fail_cnt==3` → ALARM (LED 전체 점멸 + 부저)
- **자동 잠금** — UNLOCK 후 `LOCK_SECONDS`(기본 10초) 경과 시 IDLE 복귀
- **비밀번호 변경** — UNLOCK에서 Change 키 → 새 4자리 입력 → 저장
- **비밀번호 마스킹** — FND/LCD에 숫자 대신 `*` 표시로 노출 방지

---

## 3. 시스템 구조

```
        ┌───────────────────────────── FPGA (doorlock_top) ─────────────────────────────┐
btn[16] │  key_encoder ─► input_buffer ─► password_logic ─┐                              │
DIP[8]  │  (debounce)     (4-digit buf)   (compare/fail)   │                              │
        │       │              │                │           ▼                            │
        │       └──────────────┴────────────────┴──► fsm_controller (6-state)            │
        │                                                  │ state                       │
        │   clock_divider ──► tick_1khz/1hz/blink          ▼                              │
        │   auto_lock_timer ──► lock_timeout ──►  ┌─────────┴──────────┐                  │
        │                                         ▼     ▼     ▼     ▼                     │
        │                              lcd_controller fnd led piezo                        │
        └──────────────────────────────────│──────│────│────│──────────────────────────┘
                                            ▼      ▼    ▼    ▼
                                       LCD 16×2  FND4  LED16  Buzzer
```

### FSM 상태도

```
 IDLE ──(숫자키)──► INPUT ──(ENTER & 4자리)──► CHECK ──(일치)──► UNLOCK ──(Change)──► CHANGE
   ▲                  │                          │                 │                    │
   │                (Clear)                  (불일치)           (timeout/Clear)      (ENTER&4자리)
   │                  ▼                          │                 │                    │
   └──────────────── IDLE ◄──(불일치<3회)────────┤                 └────► IDLE ◄─────────┘
                                                 │(불일치 3회)
                                                 ▼
                                              ALARM ──(Clear/Reset)──► IDLE
```

### 상태별 LCD 16×2 화면

| State  | Line 1            | Line 2             |
|--------|-------------------|--------------------|
| IDLE   | `** DIGITAL LOCK ` | `Enter Password  ` |
| INPUT  | `Password:       ` | `*` × 입력자릿수    |
| CHECK  | `Checking...     ` | `Please wait     ` |
| UNLOCK | `ACCESS GRANTED  ` | `Welcome!        ` |
| ALARM  | `!! WARNING !!   ` | `3 Failed Tries  ` |
| CHANGE | `New Password?   ` | `Enter New PW    ` |

---

## 4. 파일 구성

```
DS_DoorLock/
├── README.md
├── docs/
│   └── SPEC.md                # 상세 명세서 (포트/타이밍/전이표/핀맵/테스트계획)
├── rtl/                       # 합성 대상 RTL
│   ├── doorlock_top.v         # Top: 전체 모듈 연결
│   ├── clock_divider.v        # 1kHz/1Hz/blink 틱 생성
│   ├── debouncer.v            # 단일 버튼 디바운서
│   ├── key_encoder.v          # 16버튼 디바운스+엣지+우선순위 인코딩
│   ├── input_buffer.v         # 4자리 시프트 버퍼 + 자릿수 카운터
│   ├── password_logic.v       # 비교/실패카운터/비번 변경
│   ├── auto_lock_timer.v      # UNLOCK 자동 잠금 타이머
│   ├── fsm_controller.v       # 메인 6-상태 FSM
│   ├── lcd_controller.v       # ★ HD44780 LCD 16×2 드라이버 (담당: 권우현)
│   ├── fnd_controller.v       # 4-digit FND 멀티플렉싱 + 마스킹
│   ├── led_controller.v       # LED 16개 상태/경보 패턴
│   └── piezo_controller.v     # 부저 톤/경보음/키 비프
└── tb/                        # 테스트벤치
    ├── tb_doorlock_top.v      # 통합 시나리오(정상/실패/변경)
    └── tb_lcd_controller.v    # LCD 초기화·드라이버 단위 검증
```

---

## 5. 모듈 인터페이스 (Top Port)

| 신호 | 방향 | 비트 | 설명 |
|------|------|------|------|
| `clk`      | in  | 1  | 보드 클럭(1MHz 기본) |
| `rst_n`    | in  | 1  | 리셋 (Low active) |
| `btn`      | in  | 16 | 푸시버튼 0~9/Enter/Clear/Change |
| `dip`      | in  | 8  | DIP 스위치(예약) |
| `lcd_rs/rw/e` | out | 1,1,1 | LCD 제어 |
| `lcd_data` | out | 8  | LCD 데이터 버스 DB0~DB7 |
| `fnd_seg`  | out | 8  | `{dp,g,f,e,d,c,b,a}` (active-H) |
| `fnd_com`  | out | 4  | 자리 선택 (active-L, Common Cathode) |
| `led`      | out | 16 | LED 16개 |
| `piezo`    | out | 1  | 부저 |

**버튼 매핑:** `btn[0..9]`=숫자0~9, `btn[10]`=Enter, `btn[11]`=Clear, `btn[12]`=Change.

---

## 6. 시뮬레이션

### Icarus Verilog (무료)
```bash
# 통합 테스트
iverilog -g2012 -o sim.out tb/tb_doorlock_top.v rtl/*.v
vvp sim.out                 # 콘솔에 상태 전이 로그 출력
# 파형: gtkwave tb_doorlock_top.vcd

# LCD 단위 테스트
iverilog -o lcd.out tb/tb_lcd_controller.v rtl/lcd_controller.v
vvp lcd.out
```

### ModelSim / Questa
```tcl
vlib work
vlog rtl/*.v tb/tb_doorlock_top.v
vsim -c tb_doorlock_top -do "run -all; quit"
```

> 테스트벤치는 시뮬레이션 가속을 위해 `CLK_HZ=10_000`, `LOCK_SECONDS=2`로
> 축소 인스턴스화한다. 실제 합성/보드 적용 시 기본값(1MHz/10초)을 사용한다.

### 합성 (Quartus II)
1. 새 프로젝트 생성, Device `EP2C8Q208C8`
2. `rtl/*.v` 추가, Top-Level = `doorlock_top`
3. `docs/SPEC.md`의 핀 매핑 표대로 Pin Planner 설정 후 Compile → `.sof` 다운로드

---

## 7. 역할 분담

| 팀원 | 담당 | 본 저장소 모듈 |
|------|------|----------------|
| 이서영 | Top / FSM 통합, 인터페이스 정의 | `doorlock_top.v`, `fsm_controller.v` |
| 손동한 | 입력 처리(디바운싱/인코딩/버퍼) | `debouncer.v`, `key_encoder.v`, `input_buffer.v` |
| 정용성 | 비밀번호 비교/변경/시도 카운터/자동잠금 | `password_logic.v`, `auto_lock_timer.v` |
| **권우현** | **LCD 초기화/드라이버/상태 메시지** | **`lcd_controller.v`** |
| 장현석 | FND 7-seg 디코더/멀티플렉싱/마스킹 | `fnd_controller.v` |
| 최미소 | 경보(Piezo 톤/LED 점멸 패턴) | `piezo_controller.v`, `led_controller.v` |

상세 사양은 [docs/SPEC.md](docs/SPEC.md) 참고.
