`timescale 1ns/1ps
module reset_tb;
  parameter integer KIND=0, PHASE=0, DELAY=7;
  reg clk=0,rstn=0;always #5 clk=~clk;
  wire tx;wire[7:0]led;
  mini_soc #(.CLK_HZ(1152000),.DEBOUNCE_CYCLES(8),.RESPONSE_DELAY(DELAY)) dut(
    .clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led(led));
  integer accepted=0,responses=0,cancelled=0,epoch=0,selected=0,cycles=0;
  reg outstanding=0, store_wait=0, failed_rsp=0;
  reg[31:0] store_pc=0;
  wire match_cmd=dut.d_fire &&
    ((KIND==0 && dut.d_write && dut.d_addr==32'h80004400) ||
     (KIND==1 && !dut.d_write && dut.d_addr==32'h80004400) ||
     (KIND==2 && !dut.d_write && dut.d_addr==32'h20000000) ||
     (KIND==3 && dut.d_write && dut.d_addr==32'h20000000));
  always @(posedge clk) begin
    cycles=cycles+1;
    if(dut.reset) begin
      if(outstanding) cancelled=cancelled+1;
      outstanding=0;store_wait=0;failed_rsp=0;
    end else begin
      if(led==8'hee) $fatal(1,"Reset firmware failure");
      if(dut.d_rsp_ready) begin
        if(!outstanding) $fatal(1,"Stale response after reset");
        outstanding=0;responses=responses+1;failed_rsp=dut.d_rsp_error;
      end
      if(dut.obs_store_retire) begin
        if(!store_wait || outstanding || failed_rsp || dut.obs_retire_pc!==store_pc)
          $fatal(1,"Invalid store retirement across reset");
        store_wait=0;
      end
      if(store_wait && failed_rsp && !outstanding) store_wait=0;
      if(dut.d_fire) begin
        if(outstanding || store_wait) $fatal(1,"Outstanding slot reused");
        outstanding=1;accepted=accepted+1;failed_rsp=0;
        if(dut.d_write) begin store_wait=1;store_pc=dut.obs_cmd_pc;end
      end
    end
  end
  initial begin
    repeat(20) @(negedge clk);rstn=1;
    // Observe the real handshake, then change reset only on falling edges.
    @(posedge clk);while(!match_cmd) @(posedge clk);
    @(negedge clk);
    if(!dut.pending || dut.d_rsp_ready) $fatal(1,"Missed pending window");
    if(PHASE==1) begin
      while(dut.response_count!=1) @(negedge clk);
    end
    if(PHASE==2) begin
      while(!dut.d_rsp_ready) @(negedge clk);
    end
    if(!outstanding) $fatal(1,"Selected response already consumed");
    selected=1;rstn=0;
    repeat(12) begin
      @(negedge clk);
      if(dut.pending || dut.d_rsp_ready || dut.d_fire || dut.response_count!=0)
        $fatal(1,"Response state not cleared by global reset");
      if(dut.ram[256]!==32'h1234abcd) $fatal(1,"Accepted RAM write was lost on reset");
    end
`ifdef STALE_RESPONSE_MUTATION
    force dut.d_rsp_ready=1;
`endif
    epoch=1;rstn=1;
    wait(led==8'h66);repeat(DELAY+25) @(negedge clk);
    if(!selected || cancelled!=1 || accepted!=responses+cancelled || outstanding || store_wait)
      $fatal(1,"Reset accounting failed accepted=%0d responses=%0d cancelled=%0d",accepted,responses,cancelled);
    if(dut.ram[256]!==32'h1234abcd || dut.fault_count!=1)
      $fatal(1,"Reboot memory/fault state incorrect");
    $display("PASS: inflight reset kind=%0d phase=%0d delay=%0d accepted=%0d responses=%0d cancelled=1 clean_reboot=1",KIND,PHASE,DELAY,accepted,responses);
    $finish;
  end
  initial begin repeat(30000) @(posedge clk);$fatal(1,"Inflight reset timeout");end
endmodule
