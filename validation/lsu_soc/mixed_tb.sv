`timescale 1ns/1ps
module mixed_tb;
  parameter integer DELAY=0;
  reg clk=0,rstn=0;always #5 clk=~clk;
  wire tx;wire[7:0]led;
  mini_soc #(.CLK_HZ(1152000),.DEBOUNCE_CYCLES(8),.RESPONSE_DELAY(DELAY)) dut(
    .clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led(led));
  reg[31:0] expected[0:255];
  integer reads=0,writes=0,responses=0,boot,k;
  reg outstanding=0;
  always @(posedge clk) begin
    if(dut.reset) begin reads=0;writes=0;responses=0;outstanding=0;end
    else begin
      if(led==8'hee) $fatal(1,"Mixed program trap/readback failure");
      if(dut.d_rsp_ready) begin
        if(!outstanding || dut.d_rsp_error) $fatal(1,"Mixed response mismatch");
        responses=responses+1;outstanding=0;
      end
      if(dut.d_fire) begin
        if(outstanding) $fatal(1,"Mixed request overlap");
        outstanding=1;
        if(dut.d_write) writes=writes+1;else reads=reads+1;
      end
    end
  end
  initial begin
    $readmemh("mixed_expected.hex",expected);
    for(boot=1;boot<=2;boot=boot+1) begin
      repeat(20) @(negedge clk);rstn=1;
      wait(led==8'h5a);repeat(DELAY+25) @(negedge clk);
      for(k=0;k<256;k=k+1)
        if(dut.ram[512+k]!==expected[k])
          $fatal(1,"Mixed reference mismatch word=%0d actual=%h expected=%h",k,dut.ram[512+k],expected[k]);
      if(outstanding || reads!=192 || writes!=321 || responses!=513 || dut.fault_count!=0)
        $fatal(1,"Mixed coverage mismatch reads=%0d writes=%0d responses=%0d",reads,writes,responses);
      $display("PASS: mixed delay=%0d boot=%0d rows=32 words=256 reads=192 writes=321",DELAY,boot);
      rstn=0;
    end
    $finish;
  end
  initial begin repeat(150000) @(posedge clk);$fatal(1,"Mixed timeout");end
endmodule
