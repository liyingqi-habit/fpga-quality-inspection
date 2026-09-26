`timescale 1ns/1ps
module mini_soc_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg rstn=0, key=1, rx=1;
  wire tx; wire [7:0] led;
  localparam DIV=10;
  mini_soc #(.CLK_HZ(1152000),.DEBOUNCE_CYCLES(8)) dut(
    .clk(clk),.rstn(rstn),.key(key),.uart_rx(rx),.uart_tx(tx),.led(led));
  task getbyte(output reg [7:0] b);
    integer i;
    begin
      @(negedge tx);
      repeat(DIV+DIV/2) @(negedge clk);
      for(i=0;i<8;i=i+1) begin b[i]=tx; repeat(DIV) @(negedge clk); end
      if(tx!==1'b1) $fatal(1,"TX stop bit invalid");
    end
  endtask
  task expect_text(input string expected);
    reg [7:0] b; integer i;
    begin
      for(i=0;i<expected.len();i=i+1) begin
        getbyte(b);
        if(b!==expected[i]) $fatal(1,"UART mismatch idx %0d expected %h got %h",i,expected[i],b);
        $write("%c",b);
      end
    end
  endtask
  task sendbyte(input [7:0] b);
    integer i;
    begin
      @(negedge clk); rx=0; repeat(DIV) @(negedge clk);
      for(i=0;i<8;i=i+1) begin rx=b[i]; repeat(DIV) @(negedge clk); end
      rx=1; // Return before firmware can echo; caller immediately waits for TX.
    end
  endtask
  initial begin
    if($test$plusargs("wave")) begin $dumpfile("mini_soc.vcd"); $dumpvars(0,mini_soc_tb); end
    repeat(20) @(negedge clk); rstn=1;
    expect_text("VEX MINI RV32IM\015\012SELFTEST PASS\015\012KEY=1\015\012");
    key=0;
    expect_text("KEY=0\015\012");
    key=1;
    expect_text("KEY=1\015\012");
    sendbyte(8'h5a); expect_text("Z");
    wait(led==8'h02); wait(led==8'h04);
    if(dut.fault_count!=0 || dut.uart.overrun || dut.uart.framing_error) $fatal(1,"Peripheral fault");
    rstn=0; repeat(20) @(negedge clk); rstn=1;
    expect_text("VEX MINI RV32IM\015\012SELFTEST PASS\015\012KEY=1\015\012");
    $display("\nPASS: CPU boot, data/BSS, SB/SH/LB/LH, M ops, timer, GPIO, UART RX/TX, key, reboot");
    $finish;
  end
  initial begin repeat(2000000) @(posedge clk); $fatal(1,"Simulation timeout"); end
endmodule
