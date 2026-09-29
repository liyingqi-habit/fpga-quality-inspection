`timescale 1ns/1ps
module access_tb;
  parameter integer DELAY=0;
  reg clk=0,rstn=0; always #5 clk=~clk;
  wire tx;wire[7:0]led;
  mini_soc #(.CLK_HZ(1152000),.DEBOUNCE_CYCLES(8),.RESPONSE_DELAY(DELAY)) dut(
    .clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led(led));
  integer cycle=0,accepted=0,responses=0,read_count=0,write_count=0,trap_count=0;
  integer pending=0,age=0,badreads=0,fd,run;
  reg [31:0] pc, addr; reg wr,error_seen=0,store_wait=0;
  reg [3:0] byte_lanes=0; reg [1:0] half_lanes=0;
  reg [71:0] held; reg holding=0;
  wire [71:0] command={dut.d_write,dut.d_addr,dut.d_data,dut.d_size,dut.d_mask,1'b0};
  always @(posedge clk) begin
    cycle=cycle+1;
    if(dut.reset) begin
      pending=0;store_wait=0;holding=0;
      accepted=0;responses=0;read_count=0;write_count=0;trap_count=0;badreads=0;
      byte_lanes=0;half_lanes=0;
    end else begin
      if(led[7]) $fatal(1,"Access failure signature=%h",led);
      if(holding && (!dut.d_valid || command!==held)) $fatal(1,"DBus unstable under backpressure");
      holding=dut.d_valid&&!dut.d_ready; if(holding) held=command;
      if(dut.d_rsp_ready) begin
        if(!pending || cycle-age<DELAY+1) $fatal(1,"Orphan/early response");
        pending=0;responses=responses+1;error_seen=dut.d_rsp_error;
      end
      if(dut.obs_store_retire) begin
        if(!store_wait || pending || error_seen || dut.obs_retire_pc!==pc) $fatal(1,"Store retired without matching success");
        store_wait=0;
      end
      if(dut.d_fire) begin
        if(pending || store_wait) $fatal(1,"Command reused outstanding slot");
        pending=1;age=cycle;accepted=accepted+1;
        pc=dut.obs_cmd_pc;addr=dut.d_addr;wr=dut.d_write;error_seen=0;
        store_wait=wr;
        if(wr) write_count=write_count+1;else read_count=read_count+1;
        if(addr==32'h800043f0 || addr==32'h10000000) $fatal(1,"Wrong-path side effect reached bus");
        if(!wr && addr==32'h20000000) badreads=badreads+1;
        if(addr==32'h80004201 && dut.d_size==1) $fatal(1,"Misaligned halfword reached bus");
        if(wr && addr>=32'h80004200 && addr<=32'h80004203) begin
          if(dut.d_size==0) begin
            if(dut.d_mask!==(4'b1<<addr[1:0])) $fatal(1,"Bad SB mask");
            byte_lanes[addr[1:0]]=1;
          end
          if(dut.d_size==1) begin
            if(dut.d_mask!==(addr[1]?4'b1100:4'b0011)) $fatal(1,"Bad SH mask");
            half_lanes[addr[1]]=1;
          end
        end
      end
      // On a write error the instruction is removed, not retired.
      if(!pending && store_wait && error_seen) store_wait=0;
      if(dut.obs_retire_valid && dut.obs_retire_pc==32'h80000080) trap_count=trap_count+1;
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycle,run,
        dut.d_fire,dut.d_write,dut.d_addr,dut.d_mask,dut.d_rsp_ready,dut.d_rsp_error,dut.obs_store_retire,led);
    end
  end
  initial begin
    fd=$fopen("access_trace.csv","w");
    $fdisplay(fd,"cycle,boot,cmd,write,address,mask,response,error,store_retire,led");
    for(run=1;run<=2;run=run+1) begin
      repeat(20) @(negedge clk);rstn=1;
      wait(led==8'h55); repeat(DELAY+25) @(negedge clk);
      if(pending || store_wait || accepted!=responses || read_count!=19 || write_count!=13 ||
         byte_lanes!=15 || half_lanes!=3 || trap_count!=6 || badreads!=1)
        $fatal(1,"Missing coverage cmd=%0d rsp=%0d traps=%0d badreads=%0d",accepted,responses,trap_count,badreads);
      if(dut.ram[128]!==32'hfedc8001 || dut.ram[136]!==1 || dut.ram[4095]!==32'h13579bdf || dut.fault_count!==3)
        $fatal(1,"Final memory/fault evidence mismatch");
      $display("PASS: accesses delay=%0d boot=%0d reads=%0d writes=%0d traps=6 SB_lanes=4 SH_lanes=2 flush=3",DELAY,run,read_count,write_count);
      rstn=0;
    end
    $fclose(fd);$finish;
  end
  initial begin repeat(100000) @(posedge clk);$fatal(1,"Access timeout");end
endmodule
