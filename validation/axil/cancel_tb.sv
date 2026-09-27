`timescale 1ns/1ps
module cancel_tb;
 reg clk=0;always #5 clk=~clk;
 reg bus_reset=1,request=0,allow_rsp=0,allow_aw=0,allow_w=0,allow_ar=0;
 wire cr,busy,cancelled,cv,ready,cw,rv,re,retire,store_retire;
 wire[31:0] ca,cd,rd,cmd_pc,retire_pc;wire[3:0] mask;
 wire av,ar,wv,wr,bv,br,qv,qr,pv,pr;wire[31:0] aa,wd,qa,pd;wire[3:0] ws;wire[2:0] ap,qp;wire[1:0] bc,pc;
 wire iv;wire[31:0] ip;reg ir=0;reg[31:0] insn=32'h13;
 reg[31:0] rom0[0:4095],rom1[0:4095];
 integer write_mode,phase,code,delay_value,cycle=0,fd,epoch=0;
 integer accepted=0,aw_count=0,w_count=0,ar_count=0,response_count=0,stalls=0;
 integer reset_at=-1,reset_done=0,done=0,finish_age=0,issue_at=-1,i;
 wire[31:0] old_memory,commit_addr,commit_data;wire commit;
 VexAxilCpu cpu(.clk(clk),.reset(cr),.iBus_cmd_valid(iv),.iBus_cmd_ready(1'b1),.iBus_cmd_payload_pc(ip),
  .iBus_rsp_valid(ir),.iBus_rsp_payload_error(1'b0),.iBus_rsp_payload_inst(insn),
  .dBus_cmd_valid(cv),.dBus_cmd_ready(ready),.dBus_cmd_payload_wr(cw),.dBus_cmd_payload_address(ca),
  .dBus_cmd_payload_data(cd),.dBus_cmd_payload_mask(mask),.dBus_cmd_payload_size(),
  .dBus_rsp_ready(rv),.dBus_rsp_error(re),.dBus_rsp_data(rd),
  .timerInterrupt(1'b0),.softwareInterrupt(1'b0),.externalInterrupt(1'b0),
  .obs_cmd_pc(cmd_pc),.obs_store_retire(store_retire),.obs_retire_pc(retire_pc),.obs_retire_valid(retire));
 cpu_axil_bridge bridge(clk,bus_reset,request,1'b1,allow_rsp,cv,cw,ca,cd,mask,ready,rv,re,rd,
  cr,busy,cancelled,av,ar,aa,ap,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,qp,pv,pr,pd,pc);
 cancel_target target(clk,bus_reset,allow_aw,allow_w,allow_ar,phase==7,delay_value[7:0],code[1:0],
  av,ar,aa,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,pv,pr,pd,pc,old_memory,commit,commit_addr,commit_data);
 always @(posedge clk)begin
  cycle=cycle+1;
  if(cr)begin ir<=0;insn<=32'h13;end
  else begin ir<=iv;if(iv)insn<=epoch==0?rom0[ip[13:2]]:rom1[ip[13:2]];end
  if(!bus_reset)begin
   $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
    cycle,epoch,request,cr,busy,cancelled,cv,ready,cw,ca,cd,mask,cmd_pc,
    av,ar,aa,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,pv,pr,pd,pc,rv,re,rd,
    retire&&!cr,retire_pc,old_memory,store_retire&&!cr);
   if(cv&&ready)begin accepted=accepted+1;if(accepted==1)issue_at=cycle;end
   if(av&&ar)aw_count=aw_count+1;
   if(wv&&wr)w_count=w_count+1;
   if(qv&&qr)ar_count=ar_count+1;
   if((bv&&!br)||(pv&&!pr))stalls=stalls+1;
   if((bv&&br)||(pv&&pr))response_count=response_count+1;
   if(commit && commit_addr==32'h10000024)done=1;
  end
 end
 // Only external timing/reset/ROM fixture changes; never force CPU registers or retire/trap.
 always @(negedge clk)if(!bus_reset)begin
  if(reset_at>=0 && cycle>reset_at)request=0;
  if(phase==0 || reset_done || (accepted>0 && cycle-issue_at>=3))begin
   allow_aw=1;allow_w=1;allow_ar=1;
   if(!reset_done && phase==2)allow_w=0;
   if(!reset_done && phase==3)allow_aw=0;
  end
  if(stalls>=3)allow_rsp=1;
  if(!reset_done && phase!=0 && (
   (phase==1 && accepted==1 && aw_count==0 && w_count==0 && ar_count==0) ||
   (phase==2 && aw_count==1 && w_count==0) ||
   (phase==3 && w_count==1 && aw_count==0) ||
   ((phase==4||phase==7) && ((write_mode&&aw_count==1&&w_count==1)||(!write_mode&&ar_count==1)) && !bv&&!pv) ||
   (phase==5 && (bv||pv) && allow_rsp) ||
   (phase==6 && (bv||pv) && !allow_rsp)))begin
    request=1;reset_at=cycle;reset_done=1;epoch=1;
  end
  if(done && !busy && !rv)finish_age=finish_age+1;
  if(finish_age==15 || (phase==7 && reset_done && cycle-reset_at==100))begin
   $fclose(fd);$display("TRACE_COMPLETE write=%0d phase=%0d code=%0d delay=%0d",write_mode,phase,code,delay_value);$finish;
  end
 end
 initial begin
  if(!$value$plusargs("WRITE=%d",write_mode)||!$value$plusargs("PHASE=%d",phase)||
     !$value$plusargs("CODE=%d",code)||!$value$plusargs("DELAY=%d",delay_value))$fatal(1,"Missing case arguments");
  $readmemh("boot0.hex",rom0);$readmemh("boot1.hex",rom1);
  fd=$fopen("trace.csv","w");if(!fd)$fatal(1,"Trace open");
  $fdisplay(fd,"cycle,epoch,reset,cpu_reset,busy,cancelled,cv,ready,write,addr,data,mask,cmd_pc,av,ar,aa,wv,wr,wd,ws,bv,br,bc,qv,qr,qa,pv,pr,pd,pc,rv,re,rd,retire,retire_pc,memory,store_retire");
  repeat(5)@(negedge clk);bus_reset=0;
 end
 initial begin repeat(3000)@(posedge clk);$fatal(1,"Cancel CPU timeout");end
endmodule
