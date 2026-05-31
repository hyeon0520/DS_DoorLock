// ============================================================================
//  piezo_controller.v  -  Piezo 부저 제어 / Buzzer tone generator
// ----------------------------------------------------------------------------
//  - 톤 생성   : CLK_HZ 를 분주하여 TONE_HZ 가청 방형파 생성
//  - 경보음    : alarm=1 인 동안 연속 톤 출력
//  - 키 비프음 : key_stb 발생 시 BEEP_MS 동안 짧은 피드백 톤(one-shot)
// ============================================================================
module piezo_controller #(
    parameter integer CLK_HZ  = 1_000_000,
    parameter integer TONE_HZ = 1_000,
    parameter integer BEEP_MS = 50
)(
    input  wire clk,
    input  wire rst_n,
    input  wire alarm,
    input  wire key_stb,
    output reg  piezo
);
    localparam integer HALF     = (CLK_HZ/(2*TONE_HZ) > 0) ? CLK_HZ/(2*TONE_HZ) : 1;
    localparam integer BEEP_CYC = (CLK_HZ/1000)*BEEP_MS;

    reg [31:0] tdiv;
    reg        tone;
    reg [31:0] beepcnt;
    reg        beeping;

    // tone (square wave) generator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tdiv <= 32'd0; tone <= 1'b0; end
        else if (tdiv >= HALF-1) begin tdiv <= 32'd0; tone <= ~tone; end
        else tdiv <= tdiv + 32'd1;
    end

    // key-beep one-shot
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin beepcnt <= 32'd0; beeping <= 1'b0; end
        else if (key_stb) begin beeping <= 1'b1; beepcnt <= BEEP_CYC; end
        else if (beeping) begin
            if (beepcnt > 32'd0) beepcnt <= beepcnt - 32'd1;
            else beeping <= 1'b0;
        end
    end

    always @(*) piezo = (alarm || beeping) ? tone : 1'b0;
endmodule
