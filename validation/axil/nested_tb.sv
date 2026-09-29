`timescale 1ns/1ps
module nested_tb;
 reg clk=0;always #5 clk=~clk;
 reg bus_reset=1,request=0;reg[31:0] pending=0,reset_pending=0;
 wire cr,busy,cancelled,cv,ready,cw,rv,re,retire,store_retire;
 wire[31:0] ca,cd,rd,cmd_pc,retire_pc;wire[3:0] mask;
 wire av,ar,wv,wr,bv,br,qv,qr,pv,pr;wire[31:0] aa,wd,qa,pd;wire[3:0] ws;wire[2:0] ap,qp;wire[1:0] bc,pc;
 wire iv;wire[31:0] ip;reg ir=0;reg[31:0] insn=32'h13;
 reg[31:0] rom0[0:4095],rom1[0:4095];
 wire[31:0] old_memory,commit_addr,commit_data;wire commit;
 integer phase,hold_irq,delay_value,cycle=0,fd,rf,epoch=0,reset_at=-1,done=0,age=0;
 reg[31:0] outer_pc,inner_pc,return_pc;
 integer seen_outer=0,seen_inner=0,seen_return=0,checkpoint_accepted=0;
 VexAxilCpu cpu(.clk(clk),.reset(cr),.iBus_cmd_valid(iv),.iBus_cmd_ready(1'b1),.iBus_cmd_payload_pc(ip),
  .iBus_rsp_valid(ir),.iBus_rsp_payload_error(1'b0),.iBus_rsp_payload_inst(insn),
  .dBus_cmd_valid(cv),.dBus_cmd_ready(ready),.dBus_cmd_payload_wr(cw),.dBus_cmd_payload_address(ca),
  .dBus_cmd_payload_data(cd),.dBus_cmd_payload_mask(mask),.dBus_cmd_payload_size(),
  .dBus_rsp_ready(rv),.dBus_rsp_error(re),.dBus_rsp_data(rd),
  .timerInterrupt(pending[7]),.softwareInterrupt(pending[3]),.externalInterrupt(pending[11]),
  .obs_cmd_pc(cmd_pc),.obs_store_retire(store_retire),.obs_retire_pc(retire_pc),.obs_retire_valid(retire));
 cpu_axil_bridge bridge(clk,bus_reset,request,1'b1,1'b1,cv,cw,ca,cd,mask,ready,rv,re,rd,
  cr,busy,cancelled,av,ar,aa,ap,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,qp,pv,pr,pd,pc);
 // This target is deliberately NOT reset by CPU-local reset. Accepted stores persist.
 cancel_target target(clk,bus_reset,1'b1,1'b1,1'b1,1'b0,delay_value[7:0],2'b0,
  av,ar,aa,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,pv,pr,pd,pc,old_memory,commit,commit_addr,commit_data);
 always @(posedge clk)begin
  cycle=cycle+1;
  if(cr)begin ir<=0;insn<=32'h13;end
  else begin ir<=iv;if(iv)insn<=epoch==0?rom0[ip[13:2]]:rom1[ip[13:2]];end
  if(!bus_reset)begin
   $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
    cycle,epoch,request,cr,busy,cancelled,pending,reset_pending,cv,ready,cw,ca,cmd_pc,rv,re,
    retire&&!cr,retire_pc,commit,commit_addr,commit_data,av&&ar,wv&&wr,bv&&br,pv&&pr);
   if(!cr && retire && retire_pc==outer_pc)seen_outer=1;
   if(!cr && retire && retire_pc==inner_pc)seen_inner=1;
   if(!cr && retire && retire_pc==return_pc)seen_return=1;
   if(cv&&ready&&ca==32'h10000044)checkpoint_accepted=1;
   if(commit && commit_addr>=32'h80004000 && commit_addr<32'h80005000)begin
    if((^commit_data)===1'bx)$fatal(1,"Unknown nested record");
    $fdisplay(rf,"%0d,%0d,%0d,%0d",epoch,cycle,commit_addr,commit_data);
   end
   if(commit && commit_addr==32'h10000024)done=1;
  end
 end
 always @(negedge clk)if(!bus_reset)begin
  if(commit && (commit_addr==32'h10000030 || commit_addr==32'h10000034))pending=pending|commit_data;
  if(commit && commit_addr==32'h10000038)pending=pending&~commit_data;
  if(epoch==0 && ((phase==1 && seen_outer) || (phase==2 && checkpoint_accepted) ||
    (phase==3 && seen_inner) || (phase==4 && seen_return) ||
    (phase==5 && checkpoint_accepted && bv && br && aa==32'h10000044)))begin
   reset_pending=hold_irq ? pending : 0;
   pending=reset_pending;epoch=1;request=1;reset_at=cycle;
  end
  if(reset_at>=0 && cycle-reset_at>=2)request=0;
  if(done&&!busy&&!rv)age=age+1;
  if(age==15)begin $fclose(fd);$fclose(rf);$display("NESTED_TRACE_COMPLETE phase=%0d hold=%0d",phase,hold_irq);$finish;end
 end
 initial begin
  if(!$value$plusargs("PHASE=%d",phase)||!$value$plusargs("HOLD=%d",hold_irq)||
    !$value$plusargs("DELAY=%d",delay_value)||!$value$plusargs("OUTERPC=%h",outer_pc)||
    !$value$plusargs("INNERPC=%h",inner_pc)||!$value$plusargs("RETURNPC=%h",return_pc))$fatal(1,"Missing arguments");
  $readmemh("boot0.hex",rom0);$readmemh("boot1.hex",rom1);
  fd=$fopen("trace.csv","w");rf=$fopen("records.csv","w");
  $fdisplay(fd,"cycle,epoch,reset,cpu_reset,busy,cancelled,pending,reset_pending,cv,ready,write,addr,cmd_pc,rv,error,retire,retire_pc,commit,commit_addr,commit_data,aw_fire,w_fire,b_fire,r_fire");
  $fdisplay(rf,"epoch,cycle,addr,data");
  repeat(10)@(negedge clk);bus_reset=0;
 end
 initial begin repeat(16000)@(posedge clk);$fatal(1,"Nested timeout");end
endmodule
