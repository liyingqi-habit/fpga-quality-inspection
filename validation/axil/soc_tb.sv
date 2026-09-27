`timescale 1ns/1ps
`include "config.vh"
module soc_tb;
 reg clk=0,rstn=0,key=1;always #18.5185 clk=~clk;
 wire tx;wire[7:0] led;
 axil_soc dut(clk,rstn,key,1'b1,tx,led);
 reg[31:0] expected[0:`RESULTS-1];integer count=0,boot,cycles=0;
 always @(posedge clk)begin
   cycles=cycles+1;
   if(!dut.bus_reset && dut.commit_write && dut.address>=32'h80004800 && dut.address<32'h80005000)begin
     if(count>=`RESULTS||dut.address!==32'h80004800+count*4||dut.data!==expected[count])
       $fatal(1,"ISA result mismatch word=%0d addr=%h data=%h expected=%h",count,dut.address,dut.data,expected[count]);
     count=count+1;
   end
   if(led==8'hee)$fatal(1,"Firmware fail pc=%h cause=%h mepc=%h tval=%h",dut.cpu.writeBack_PC,dut.cpu.CsrPlugin_mcause_exceptionCode,dut.cpu.CsrPlugin_mepc,dut.cpu.CsrPlugin_mtval);
 end
 always @(negedge clk)begin
   if(led==8'he1)key=0;
   if(led==8'he2)key=1;
 end
 initial begin
   $readmemh("expected.hex",expected);
`ifdef EXPECTATION_MUTATION
   expected[4]=expected[4]^1;
`endif
   for(boot=1;boot<=2;boot=boot+1)begin
     rstn=0;repeat(20)@(negedge clk);count=0;key=1;rstn=1;
     wait(led==8'h6b);repeat(20)@(negedge clk);
     if(count!=`RESULTS)$fatal(1,"Missing results");
     $display("PASS: AXIL SoC boot=%0d results=%0d",boot,count);
   end
   $finish;
 end
 initial begin repeat(100000)@(posedge clk);$fatal(1,"SoC timeout pc=%h",dut.cpu.writeBack_PC);end
endmodule
