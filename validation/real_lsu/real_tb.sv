`timescale 1ns/1ps
module real_tb;
  reg clk=0; always #5 clk=~clk;
  reg bus_reset=1,reset_request=0,admit=1,allow_b=0,allow_aw=1,allow_w=1;
  wire cpu_reset,busy,cancelled,cmd_valid,cmd_ready,cmd_write,rsp_valid,rsp_error;
  wire [31:0] cmd_addr,cmd_data,cmd_pc,retire_pc; wire [3:0] cmd_mask;
  wire retire,retire_valid;
  wire av,ar,wv,wr,bv,br; wire [31:0] addr,data; wire [3:0] strb; wire [1:0] resp;
  reg [7:0] delay_cycles; reg [1:0] response_code; reg never_respond=0;
  wire iv; wire [31:0] ip; reg ir=0; reg [31:0] instruction=32'h13;
  reg [31:0] rom[0:4095];
  integer id,cycle=0,fd,aw_count=0,w_count=0,b_stalls=0,epoch=0;
  integer reset_cycle=-1,reset_once=0,drained=0,settled=0,trap_seen=0;
  integer retire_count=0,young_count=0,i; reg trap_event=0;
  wire young=cmd_valid && cmd_ready && cmd_write && cmd_addr==32'h10000004+id*4;
  wire issue=cmd_valid && cmd_ready && cmd_write && cmd_addr==32'h10000000+id*4;
  VexWriteResponse cpu(.clk(clk),.reset(cpu_reset),
    .iBus_cmd_valid(iv),.iBus_cmd_ready(1'b1),.iBus_cmd_payload_pc(ip),
    .iBus_rsp_valid(ir),.iBus_rsp_payload_error(1'b0),.iBus_rsp_payload_inst(instruction),
    .dBus_cmd_valid(cmd_valid),.dBus_cmd_ready(cmd_ready),.dBus_cmd_payload_wr(cmd_write),
    .dBus_cmd_payload_address(cmd_addr),.dBus_cmd_payload_data(cmd_data),
    .dBus_cmd_payload_mask(cmd_mask),.dBus_cmd_payload_size(),
    .dBus_rsp_ready(rsp_valid),.dBus_rsp_error(rsp_error),.dBus_rsp_data(32'b0),
    .timerInterrupt(1'b0),.externalInterrupt(1'b0),.softwareInterrupt(1'b0),
    .obs_cmd_pc(cmd_pc),.obs_store_retire(retire),.obs_retire_pc(retire_pc),
    .obs_retire_valid(retire_valid));
  write_bridge bridge(clk,bus_reset,reset_request,admit,allow_b,
    cmd_valid,cmd_write,cmd_addr,cmd_data,cmd_mask,cmd_ready,rsp_valid,rsp_error,
    cpu_reset,busy,cancelled,av,ar,addr,wv,wr,data,strb,bv,br,resp);
  write_target target(clk,bus_reset,allow_aw,allow_w,av,addr,ar,wv,data,strb,wr,
    bv,br,resp,delay_cycles,response_code,never_respond);
  always @(posedge clk) begin
    if(cpu_reset) begin ir<=0; instruction<=32'h13; end
    else begin ir<=iv; if(iv) instruction<=rom[ip[13:2]]; end
    cycle=cycle+1;
    if(!bus_reset) begin
      // Event comes from actual handler retirement and architectural CSRs.
      trap_event=retire_valid && retire_pc==32'h80000080 && !cpu_reset;
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        cycle,id,epoch,reset_request,cpu_reset,issue,(issue||young)?cmd_pc:32'b0,av,ar,addr,wv,wr,data,strb,bv,br,resp,
        retire && !cpu_reset,(retire&&!cpu_reset)?retire_pc:32'b0,trap_event,
        trap_event?cpu.CsrPlugin_mepc:32'b0,trap_event?cpu.CsrPlugin_mtval:32'b0,
        trap_event?cpu.CsrPlugin_mcause_exceptionCode:4'b0,young,busy,cancelled,
        cmd_valid && !cpu_reset,(cmd_valid&&!cpu_reset)?cmd_addr:32'b0);
      if(av&&ar) aw_count=aw_count+1;
      if(wv&&wr) w_count=w_count+1;
      if(bv&&!br) b_stalls=b_stalls+1;
      if(retire && !cpu_reset && retire_pc==32'h80000010) retire_count=retire_count+1;
      if(young) young_count=young_count+1;
      if(trap_event) trap_seen=trap_seen+1;
      if(reset_once && bv&&br) drained=1;
    end
  end
  // Timing-only stimulus: never drives retirement, traps, PC, CSR or bus requests.
  always @(negedge clk) if(!bus_reset) begin
    if(id==0 || id==3 || id==6 || id==9 || id==10) allow_w=aw_count>0;
    if(id==1 || id==4 || id==7) allow_aw=w_count>0;
    if(id==2 || id==8 || id==11) begin
      if(av&&wv) settled=settled+1;
      if(settled>=4) begin allow_aw=1; allow_w=1; end
    end
    if(b_stalls>=3) allow_b=1;
    if(reset_request && cycle>reset_cycle) begin reset_request=0; admit=1; end
    if(!reset_once && (
       (id==5 && cmd_valid) ||
       (id==6 && aw_count==1 && w_count==0) ||
       (id==7 && w_count==1 && aw_count==0) ||
       ((id==8 || id==11) && aw_count==1 && w_count==1 && !bv) ||
       (id==9 && bv && allow_b))) begin
      reset_request=1; reset_once=1; reset_cycle=cycle; epoch=1;
    end
    if(drained) response_code=0;
  end
  initial begin
    if(!$value$plusargs("CASE=%d",id)) $fatal(1,"CASE required");
    for(i=0;i<4096;i=i+1) rom[i]=32'h13;
    $readmemh("program.hex",rom);
    fd=$fopen("trace.csv","w");
    if(!fd) $fatal(1,"Trace open failed");
    $fdisplay(fd,"cycle,case,epoch,reset,cpu_reset,issue,pc,av,ar,addr,wv,wr,data,strb,bv,br,resp,retire,retire_pc,trap,trap_pc,trap_addr,cause,young,busy,cancelled,cmd_valid,cmd_addr");
    case(id)
      1:delay_cycles=7; 2:delay_cycles=31; 3:delay_cycles=9;
      4:delay_cycles=3; 6,7:delay_cycles=8; 8:delay_cycles=15;
      9:delay_cycles=2; default:delay_cycles=0;
    endcase
    response_code=id==3 || id==9 ? 2 : id==4 ? 3 : 0;
    never_respond=id==11;
    if(id==5) admit=0;
    if(id==0 || id==3 || id==6 || id==9 || id==10) allow_w=0;
    if(id==1 || id==4 || id==7) allow_aw=0;
    if(id==2 || id==8 || id==11) begin allow_aw=0;allow_w=0;end
    repeat(5) @(negedge clk); bus_reset=0;
    if(id==11) begin
      wait(reset_once); repeat(50) @(negedge clk);
      if(!busy || !cpu_reset || !cancelled) $fatal(1,"Lost quarantine");
    end else begin
      wait(retire_valid && (retire_pc==32'h80000018 || retire_pc==32'h8000008c));
      repeat(20) @(negedge clk);
      if(id==3 || id==4) begin
        if(trap_seen!=1 || retire_count!=0 || young_count!=0) $fatal(1,"Error architecture");
        if(target.memory[id]!==32'h11223344) $fatal(1,"Error model memory");
        if(target.memory[id+1]!==32'h11223344) $fatal(1,"Younger memory corrupted on error");
      end else begin
        if(trap_seen!=0 || retire_count!=1 || young_count!=1) $fatal(1,"Success/reboot architecture");
        if(target.memory[id] !== 32'haabbcc00+id) $fatal(1,"Memory result");
        if(target.memory[id+1] !== 32'haabbcc00+id) $fatal(1,"Younger memory result");
      end
    end
    $fclose(fd); $display("REAL_CASE_PASS %0d retires=%0d traps=%0d young=%0d",id,retire_count,trap_seen,young_count);
    $finish;
  end
  initial begin repeat(5000) @(posedge clk); $fatal(1,"Real CPU timeout"); end
endmodule
