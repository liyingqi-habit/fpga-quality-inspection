`timescale 1ns/1ps
// Dedicated fixture: no force of CPU internals. IRQ pins and AXIL responses only.
module competition_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset=1,irq=0,release_rsp=0;
 wire cr,busy,cancelled,cv,ready,cw,rv,re,retire,store_retire;
 wire [31:0] ca,cd,rd,cmd_pc,retire_pc;wire[3:0] mask;
 wire av,ar,wv,wr,bv,br,qv,qr,pv,pr;wire[31:0] aa,wd,qa,pd;wire[3:0] ws;wire[2:0] ap,qp;wire[1:0] bc,pc;
 wire iv;wire[31:0] ip;reg ir=0;reg[31:0] insn=32'h13;
 reg[31:0] rom[0:4095];
 reg ifault=0;reg[31:0] response_pc=0,trigger_pc;
 integer sync_kind=-1,unused;
 integer source,phase,code,delay_value,boot,cycle=0,fd,rf,issue_at=-1;
 integer injected=0,seen_rsp=0,seen_handler=0,done=0,finish_age=0;
 wire[31:0] old_memory,commit_addr,commit_data;wire commit;
 wire allow_rsp=release_rsp || issue_at<0 || seen_rsp;
 VexAxilCpu cpu(.clk(clk),.reset(cr),.iBus_cmd_valid(iv),.iBus_cmd_ready(1'b1),.iBus_cmd_payload_pc(ip),
  .iBus_rsp_valid(ir),.iBus_rsp_payload_error(ifault),.iBus_rsp_payload_inst(insn),
  .dBus_cmd_valid(cv),.dBus_cmd_ready(ready),.dBus_cmd_payload_wr(cw),.dBus_cmd_payload_address(ca),
  .dBus_cmd_payload_data(cd),.dBus_cmd_payload_mask(mask),.dBus_cmd_payload_size(),
  .dBus_rsp_ready(rv),.dBus_rsp_error(re),.dBus_rsp_data(rd),
  .timerInterrupt(irq && source==7),.softwareInterrupt(irq && source==3),.externalInterrupt(irq && source==11),
  .obs_cmd_pc(cmd_pc),.obs_store_retire(store_retire),.obs_retire_pc(retire_pc),.obs_retire_valid(retire));
 cpu_axil_bridge bridge(clk,reset,1'b0,1'b1,allow_rsp,cv,cw,ca,cd,mask,ready,rv,re,rd,
  cr,busy,cancelled,av,ar,aa,ap,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,qp,pv,pr,pd,pc);
 cancel_target target(clk,reset,1'b1,1'b1,1'b1,1'b0,delay_value[7:0],code[1:0],
  av,ar,aa,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,pv,pr,pd,pc,old_memory,commit,commit_addr,commit_data);
 always @(posedge clk)begin
  cycle=cycle+1;
  if(reset)begin ir<=0;insn<=32'h13;ifault<=0;response_pc<=0;end
  else begin
   ir<=iv;if(iv)begin insn<=rom[ip[13:2]];response_pc<=ip;ifault<=ip[31:14]!=18'h20000;end
   $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
    boot,cycle,irq,cv,ready,cw,ca,cmd_pc,rv,re,retire,retire_pc,old_memory,commit,commit_addr,commit_data,iv,ip,ir,response_pc,ifault);
   if(sync_kind<0 && cv&&ready&&ca==32'h10000000)issue_at=cycle;
   if(sync_kind>=0 && iv && ip==trigger_pc && issue_at<0)issue_at=cycle;
   if(rv && issue_at>=0)seen_rsp=1;
   if(retire && retire_pc==32'h80000080)seen_handler=1;
   if(commit && commit_addr>=32'h80004000 && commit_addr<32'h80004400)begin
    if((^commit_data)===1'bx)$fatal(1,"Unknown competition record");
    $fdisplay(rf,"%0d,%0d,%0d",boot,commit_addr,commit_data);
   end
   if(commit && commit_addr==32'h10000024)done=1;
  end
 end
 always @(negedge clk)if(!reset)begin
  // Keep fault response held long enough for the early IRQ to become pending.
  if(issue_at>=0 && cycle-issue_at>=12)release_rsp=1;
  if(!injected && (((sync_kind<0) && ((phase==0 && issue_at>=0 && cycle-issue_at>=2) ||
     (phase==1 && rv && !seen_rsp))) ||
     (sync_kind>=0 && phase<2 && issue_at>=0 && cycle-issue_at>=phase) ||
     (phase==2 && seen_handler)))begin irq=1;injected=1;end
  if(commit && commit_addr==32'h10000030)irq=0;
  if(done)finish_age=finish_age+1;
 end
 initial begin
  unused=$value$plusargs("KIND=%d",sync_kind);
  unused=$value$plusargs("FAULTPC=%h",trigger_pc);
  if(!$value$plusargs("SOURCE=%d",source)||!$value$plusargs("PHASE=%d",phase)||
     !$value$plusargs("CODE=%d",code)||!$value$plusargs("DELAY=%d",delay_value))$fatal(1,"Missing arguments");
  $readmemh("firmware.hex",rom);
  fd=$fopen("trace.csv","w");rf=$fopen("records.csv","w");
  $fdisplay(fd,"boot,cycle,irq,cv,ready,write,addr,cmd_pc,rv,error,retire,retire_pc,memory,commit,commit_addr,commit_data,iv,ip,ir,response_pc,ifault");
  $fdisplay(rf,"boot,addr,data");
  for(boot=1;boot<=2;boot=boot+1)begin
   reset=1;repeat(10)@(negedge clk);
   irq=0;release_rsp=0;issue_at=-1;injected=0;seen_rsp=0;seen_handler=0;done=0;finish_age=0;
   reset=0;wait(finish_age>=10);@(negedge clk);
   if(!injected)$fatal(1,"IRQ timing window missed");
   $display("COMPETITION_TRACE_COMPLETE boot=%0d source=%0d phase=%0d",boot,source,phase);
  end
  $fclose(fd);$fclose(rf);$finish;
 end
 initial begin repeat(20000)@(posedge clk);$fatal(1,"Competition timeout");end
endmodule
