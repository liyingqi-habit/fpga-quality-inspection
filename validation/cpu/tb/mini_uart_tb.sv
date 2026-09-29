`timescale 1ns/1ps
// Test the real 27 MHz / 115200 divisor, including receive error handling.
module mini_uart_tb;
  reg clk=0;
  always #18.5185 clk=~clk;
  reg reset=1, rx=1, tx_start=0, rx_pop=0, clear_errors=0;
  reg [7:0] tx_data=0;
  wire tx, tx_busy, rx_valid, overrun, framing_error;
  wire [7:0] rx_data;
  localparam DIV=234;
  mini_uart dut(.*);
  task send(input [7:0] data, input stop_ok);
    integer i;
    begin
      @(negedge clk); rx=0; repeat(DIV) @(negedge clk);
      for(i=0;i<8;i=i+1) begin rx=data[i]; repeat(DIV) @(negedge clk); end
      rx=stop_ok; repeat(DIV) @(negedge clk);
      rx=1; repeat(DIV) @(negedge clk);
    end
  endtask
  task pop;
    begin @(negedge clk); rx_pop=1; @(negedge clk); rx_pop=0; end
  endtask
  task clear;
    begin @(negedge clk); clear_errors=1; @(negedge clk); clear_errors=0; end
  endtask
  reg [9:0] frame;
  integer j;
  initial begin
    repeat(8) @(negedge clk); reset=0;
    // Short glitch must not become a received character.
    rx=0; repeat(10) @(negedge clk); rx=1;
    repeat(DIV*11) @(negedge clk);
    if(rx_valid || framing_error) $fatal(1,"false start accepted");
    send(8'hA5,1);
    if(!rx_valid || rx_data!==8'hA5) $fatal(1,"RX byte mismatch");
    send(8'h3C,1);
    if(!overrun || rx_data!==8'hA5) $fatal(1,"overflow did not preserve old byte");
    pop(); clear();
    if(rx_valid || overrun) $fatal(1,"clear/pop failed");
    send(8'h55,0);
    if(!framing_error || rx_valid) $fatal(1,"bad stop accepted");
    clear();
    send(8'hC3,1);
    if(!rx_valid || rx_data!==8'hC3 || framing_error) $fatal(1,"RX recovery failed");
    pop();
    frame={1'b1,8'h96,1'b0};
    @(negedge clk); tx_data=8'h96; tx_start=1;
    @(negedge clk); tx_start=0;
    repeat(DIV/2) @(negedge clk);
    for(j=0;j<10;j=j+1) begin
      if(tx!==frame[j]) $fatal(1,"TX frame mismatch at bit %0d",j);
      repeat(DIV) @(negedge clk);
    end
    if(tx_busy || !tx) $fatal(1,"TX did not return idle");
    reset=1; repeat(3) @(negedge clk);
    if(rx_valid || overrun || framing_error || tx_busy || !tx) $fatal(1,"reset failed");
    $display("PASS: UART 27MHz divisor234, false start, overflow, framing, recovery, TX, reset");
    $finish;
  end
  initial begin repeat(100000) @(posedge clk); $fatal(1,"UART timeout"); end
endmodule
