`timescale 1ns/1ps
module bus_flush_tb;
  reg clk=0;always #5 clk=~clk;
  reg reset=1,admit=0,allow_b=0,ar=0,wr=0,bv=0;
  wire cr,busy,cancelled,cv,ready,cwrite,rv,re,av,wv,br;
  wire [31:0] ca,cd,cp,rp,aa,wd;wire [3:0] cm,ws;
  wire retire,retire_valid,iv;wire [31:0] ip;
  reg ir=0;reg [31:0] inst=32'h13,rom[0:4095];
  integer schedule,delay_b,delay_cmd,epoch=0,cycle=0,fd,i;
  integer age=0,cmd_age=0,b_age=0,post=0,accepted=0,completed=0,retired=0;
  reg have_aw=0,have_w=0;reg [31:0] held_addr,held_data;
  reg [3:0] held_mask;
  reg final_seen=0,finished=0;reg [31:0] final_pc;
  reg [31:0] branch_pc;
  VexWriteResponse cpu(.clk(clk),.reset(cr),
    .iBus_cmd_valid(iv),.iBus_cmd_ready(1'b1),.iBus_cmd_payload_pc(ip),
    .iBus_rsp_valid(ir),.iBus_rsp_payload_error(1'b0),.iBus_rsp_payload_inst(inst),
    .dBus_cmd_valid(cv),.dBus_cmd_ready(ready),.dBus_cmd_payload_wr(cwrite),
    .dBus_cmd_payload_address(ca),.dBus_cmd_payload_data(cd),.dBus_cmd_payload_mask(cm),.dBus_cmd_payload_size(),
    .dBus_rsp_ready(rv),.dBus_rsp_error(re),.dBus_rsp_data(32'b0),
    .timerInterrupt(1'b0),.externalInterrupt(1'b0),.softwareInterrupt(1'b0),
    .obs_cmd_pc(cp),.obs_store_retire(retire),.obs_retire_pc(rp),.obs_retire_valid(retire_valid));
  write_bridge bridge(clk,reset,1'b0,admit,allow_b,cv,cwrite,ca,cd,cm,ready,rv,re,
    cr,busy,cancelled,av,ar,aa,wv,wr,wd,ws,bv,br,2'b00);
  // Timing stimulus is changed only on falling edges. No CPU internal signal is driven.
  always @(negedge clk) begin
    if(reset) begin admit=0;allow_b=0;ar=0;wr=0;end
    else begin
      admit=(cmd_age>=delay_cmd);
      ar=busy && (schedule==0 ? age>=2 : schedule==1 ? have_w && age>=8 : age>=5);
      wr=busy && (schedule==1 ? age>=2 : schedule==0 ? have_aw && age>=8 : age>=5);
      allow_b=b_age>=4;
    end
  end
  always @(posedge clk) begin
    cycle=cycle+1;
    if(reset) begin
      ir<=0;inst<=32'h13;age=0;cmd_age=0;b_age=0;post=0;
      have_aw=0;have_w=0;bv<=0;accepted=0;completed=0;retired=0;
      final_seen=0;finished=0;
    end else begin
      ir<=iv;if(iv) inst<=rom[ip[13:2]];
      if(cv && ca!=32'h10000000 && ca!=32'h10000004 && ca!=32'h10000008)
        $fatal(1,"Wrong-path request addr=%h",ca);
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        epoch,cycle,cv,ready,cwrite,ca,cd,cm,cp,av,ar,aa,wv,wr,wd,ws,bv,br,rv,retire,rp,
        busy && cpu.BranchPlugin_jumpInterface_valid && cpu.memory_PC==branch_pc);
      if(cv && !ready) cmd_age=cmd_age+1;
      if(cv && ready) begin
        accepted=accepted+1;cmd_age=0;age=0;
        if(ca==32'h10000008)begin final_seen=1;final_pc=cp;end
      end
      if(busy) age=age+1;
      if(av&&ar) begin if(have_aw)$fatal(1,"Duplicate AW");have_aw=1;held_addr=aa;end
      if(wv&&wr) begin if(have_w)$fatal(1,"Duplicate W");have_w=1;held_data=wd;held_mask=ws;end
      if(bv&&!br) b_age=b_age+1;
      if(have_aw&&have_w&&!bv) begin post=post+1;if(post>delay_b)bv<=1;end
      if(bv&&br) begin
        if(!have_aw||!have_w)$fatal(1,"Early B");
        completed=completed+1;have_aw=0;have_w=0;post=0;b_age=0;bv<=0;
      end
      if(retire) retired=retired+1;
      if(retire && final_seen && rp==final_pc) finished=1;
    end
  end
  initial begin
    if(!$value$plusargs("SCHEDULE=%d",schedule) || !$value$plusargs("DELAY=%d",delay_b) ||
       !$value$plusargs("ADMIT=%d",delay_cmd) || !$value$plusargs("BRANCH_PC=%h",branch_pc)) $fatal(1,"Missing schedule");
    $readmemh("firmware.hex",rom);
    fd=$fopen("trace.csv","w");if(!fd)$fatal(1,"Trace open failed");
    $fdisplay(fd,"epoch,cycle,cv,ready,write,ca,cd,cm,cp,av,ar,aa,wv,wr,wd,ws,bv,br,rv,retire,rp,overlap");
    for(epoch=1;epoch<=2;epoch=epoch+1) begin
      reset=1;repeat(8)@(negedge clk);#1;reset=0;
      wait(finished);
      repeat(30)@(negedge clk);#1;
      if(accepted!=completed || completed!=retired || accepted<2)$fatal(1,"Transaction conservation");
    end
    reset=1;$fclose(fd);$display("PASS: bus flush boots=2");$finish;
  end
  initial begin repeat(10000)@(posedge clk);$fatal(1,"Timeout");end
endmodule
