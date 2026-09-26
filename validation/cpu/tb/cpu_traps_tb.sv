`timescale 1ns/1ps
module cpu_traps_tb;
  reg clk=0, rstn=0;
  always #5 clk=~clk;
  wire tx;
  wire [7:0] led;
  mini_soc #(.CLK_HZ(1152000),.DEBOUNCE_CYCLES(8)) dut(
    .clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led(led));
  integer accepted=0;
  always @(posedge clk) begin
    if(dut.reset) accepted=0;
    else begin
      if(led[7]) $fatal(1,"Trap failure signature=%h",led);
      if(dut.uart_start) begin
        if(accepted>=2 || dut.d_data[7:0] !== (accepted==0 ? 8'h41 : 8'h42))
          $fatal(1,"Stale/duplicate UART write after reset");
        accepted=accepted+1;
      end
    end
  end
  task reset_cpu;
    begin
      @(negedge clk); rstn=0;
      repeat(20) @(negedge clk);
      if(tx!==1 || dut.tx_busy!==0 || led!==0 || dut.d_valid!==0)
        $fatal(1,"Reset did not quiesce CPU/MMIO/UART");
      rstn=1;
    end
  endtask
  task evidence;
    begin
      if(dut.ram[0]!==2 || dut.ram[3]!==5 || dut.ram[6]!==4 || dut.ram[9]!==6)
        $fatal(1,"Trap cause evidence wrong");
      if(dut.ram[2]!==0 || dut.ram[5]!==32'h20000000 ||
         dut.ram[8]!==32'h80004101 || dut.ram[11]!==32'h80004102)
        $fatal(1,"Trap address evidence wrong");
      if(dut.ram[64]!==32'h11223344 || dut.ram[65]!==32'h11223344 || dut.fault_count!==0)
        $fatal(1,"Misaligned store had side effect");
    end
  endtask
  initial begin
    reset_cpu;
    wait(dut.d_valid && !dut.d_ready && dut.d_write && dut.d_addr==32'h10000000);
    @(negedge clk);
    evidence;
    if(accepted!=1) $fatal(1,"Did not interrupt second UART write");
    $display("PASS: four traps recovered with mcause/mepc/mtval checks; reset during UART backpressure");
    reset_cpu;
    // White-box phase targeting only; result checks remain architectural.
    wait(led==8'h32 && dut.cpu.memory_DivPlugin_div_counter_willIncrement &&
         dut.cpu.memory_DivPlugin_div_counter_value==6'd10);
    evidence;
    $display("PASS: reached active divider iteration 10 after first reboot");
    reset_cpu;
    wait(led==8'h55 && !dut.tx_busy);
    repeat(20) @(negedge clk);
    evidence;
    if(accepted!=2) $fatal(1,"Post-reset UART accept count incorrect");
    $display("PASS: trap regression and reset during UART wait/division; clean reboot completed");
    $finish;
  end
  initial begin repeat(100000) @(posedge clk); $fatal(1,"Trap/reset timeout"); end
endmodule
