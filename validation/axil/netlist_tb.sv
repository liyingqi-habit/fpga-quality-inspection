`timescale 1ns/1ps
`include "config.vh"
module netlist_tb;
 reg clk=0,rstn=0,key=1,grs_n=0;always #18.5185 clk=~clk;
 wire tx,led0;
`ifdef GATE
 GTP_GRS GRS_INST(.GRS_N(grs_n));
 // For the pinned netlist: the rising BVALID register transition is target commit.
 wire fire=dut.soc.bvalid_vname.D && !dut.soc.bvalid_vname.Q && !dut.soc.bvalid_vname.R;
`else
 wire fire=!dut.soc.bus_reset && dut.soc.commit_write;
`endif
 mini_soc_first_board dut(.clk(clk),.rstn(rstn),.key(key),.uart_rx(1'b1),.uart_tx(tx),.led0(led0));
 wire [31:0] addr=dut.soc.address,data=dut.soc.data;
 reg [31:0] expected[0:`RESULTS-1];integer count=0,boot,fd,coll1=0,coll2=0;
 reg [7:0] observed_led=0;
`ifdef TRACE_BOOT
 integer cycle=0;
 always @(posedge clk)begin
   cycle=cycle+1;
   if(cycle<140)$display("TRACE c=%0d rst=%b fire=%b b=%b addr=%h cpuaddr=%h data=%h",cycle,rstn,fire,dut.soc.bvalid,addr,dut.soc.ca,data);
 end
`endif
`ifdef GATE
 reg hit1,hit2;
 always @(posedge dut.soc.cpu.RegFilePlugin_regFile.CLKA)begin
   hit1=rstn && dut.soc.cpu.RegFilePlugin_regFile.WEA && dut.soc.cpu.RegFilePlugin_regFile.ADDRA==dut.soc.cpu.RegFilePlugin_regFile.ADDRB;
   hit2=rstn && dut.soc.cpu.RegFilePlugin_regFile_1.WEA && dut.soc.cpu.RegFilePlugin_regFile_1.ADDRA==dut.soc.cpu.RegFilePlugin_regFile_1.ADDRB;
   if(hit1)coll1=coll1+1;if(hit2)coll2=coll2+1;
`ifdef POISON_RAW
   #0.001;
   release dut.soc.cpu.decode_RegFilePlugin_rs1Data;
   release dut.soc.cpu.decode_RegFilePlugin_rs2Data;
   #0.999;
   if(hit1)force dut.soc.cpu.decode_RegFilePlugin_rs1Data=32'hxxxxxxxx;
   if(hit2)force dut.soc.cpu.decode_RegFilePlugin_rs2Data=32'hxxxxxxxx;
`endif
 end
`endif
 always @(posedge clk)if(rstn && fire)begin
   if((^addr)===1'bx || (^data)===1'bx)$fatal(1,"Unknown committed write");
   // Ignore time-dependent timer compare writes when comparing architectural results.
   if(addr>=32'h80004800 && addr<32'h80005000)begin
     if(count>=`RESULTS || addr!==32'h80004800+count*4 || data!==expected[count])
       $fatal(1,"ISA result mismatch word=%0d addr=%h data=%h expected=%h",count,addr,data,expected[count]);
     $fdisplay(fd,"%0d,%0d,%08h",boot,count,data);count=count+1;
   end
   if(addr==32'h10000010)begin
     observed_led=data[7:0];
     if(data==32'hee)$fatal(1,"Firmware trap/interrupt assertion failed");
   end
 end
 always @(negedge clk)begin
   if(observed_led==8'he1)key=0;
   if(observed_led==8'he2)key=1;
 end
 initial begin
   $readmemh("expected.hex",expected);
`ifdef EXPECTATION_MUTATION
   expected[4]=expected[4]^1;
`endif
   fd=$fopen("results.csv","w");repeat(30)@(negedge clk);grs_n=1;
   for(boot=1;boot<=2;boot=boot+1)begin
     rstn=0;repeat(20)@(negedge clk);count=0;coll1=0;coll2=0;observed_led=0;key=1;rstn=1;
     wait(observed_led==8'h6b);repeat(20)@(negedge clk);
     if(count!=`RESULTS)$fatal(1,"Missing results");
`ifdef GATE
     if(coll1==0 || coll2==0)$fatal(1,"Missing register collision coverage");
`endif
     $display("PASS: integrated boot=%0d results=%0d collisions=%0d/%0d",boot,count,coll1,coll2);$fflush();
   end
   $fclose(fd);$finish;
 end
 initial begin repeat(100000)@(posedge clk);$fatal(1,"Integrated timeout");end
endmodule
