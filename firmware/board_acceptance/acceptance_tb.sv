`timescale 1ns/1ps
`include "symbols.vh"
// Test-only stimulus/fault injection; production CPU/bridge/SoC/UART unchanged.
module acceptance_tb;
  reg clk=0,rstn=0,key=1;
  always #18.5185 clk=~clk;
  wire tx; wire [7:0] led;
  axil_soc dut(clk,rstn,key,1'b1,tx,led);
  integer scenario=0, fd, cycles=0, epoch=0;
  integer rx_state=0, rx_count=0, rx_bit=0;
  reg [7:0] rx_byte=0;
  reg previous_tx=1;
  string line="", log_path;
  integer releases=0, irq_entries=0, release_entries=0, trap_entries=0;
  reg press_prompt=0, finished_line=0, fail_line=0;
  reg [31:0] jumped_ticks;

  // Independent 8N1 receiver: only observes top-level TX and reset.
  // 27 MHz / 115200 rounded = 234 clocks/bit; sample at bit centers.
  always @(negedge clk) begin
    cycles=cycles+1;
    if(!rstn) begin
      rx_state=0;rx_count=0;previous_tx=1;line="";
      releases=0;press_prompt=0;finished_line=0;fail_line=0;
      irq_entries=0;release_entries=0;trap_entries=0;
    end else begin
      if(dut.cpu.obs_retire_valid)begin
        if(dut.cpu.obs_retire_pc==`PC_wait_irq)irq_entries=irq_entries+1;
        if(dut.cpu.obs_retire_pc==`PC_wait_release)release_entries=release_entries+1;
        if(dut.cpu.obs_retire_pc==`PC_trap)trap_entries=trap_entries+1;
      end
      case(rx_state)
        0: if(previous_tx===1'b1 && tx===1'b0) begin rx_state=1;rx_count=116;end
        1: if(rx_count!=0) rx_count=rx_count-1;
           else begin
             if(tx!==1'b0)$fatal(1,"UART start bit");
             rx_state=2;rx_count=233;rx_bit=0;
           end
        2: if(rx_count!=0) rx_count=rx_count-1;
           else begin
             if(tx!==1'b0 && tx!==1'b1)$fatal(1,"UART unknown data");
             rx_byte[rx_bit]=tx;rx_count=233;
             if(rx_bit==7)rx_state=3;else rx_bit=rx_bit+1;
           end
        3: if(rx_count!=0)rx_count=rx_count-1;
           else begin
             if(tx!==1'b1)$fatal(1,"UART stop bit");
             if($test$plusargs("CORRUPT_SERIAL") && rx_byte=="B")rx_byte="C";
             $fwrite(fd,"%c",rx_byte);
             if(rx_byte==10)begin
               $display("UART[%0d]: %s",epoch,line);
               $fflush(fd);
               $fflush();
               if(line=="WAIT RELEASE KEY1 (30s timeout, 100ms stable)")releases=releases+1;
               if(line=="WAIT PRESS KEY1 ONCE (30s timeout)")press_prompt=1;
               if(line=="MANUAL: KEY0 reset -> repeat entire test; then cold power cycle -> repeat.")finished_line=1;
               if(line.len()>=4 && line.substr(0,3)=="FAIL")fail_line=1;
               line="";
             end else if(rx_byte!=13)line={line,rx_byte};
             rx_state=0;
           end
      endcase
      previous_tx=tx;
    end
  end

  task automatic reset_cpu;
    @(posedge clk);#1;rstn=0;key=1;
    repeat(24)@(posedge clk);
    #1;epoch=epoch+1;$fwrite(fd,"\n@@RESET %0d\n",epoch);rstn=1;
  endtask
  task automatic expire_wait;
    // Preserve firmware loop and threshold. Advance only peripheral time.
    repeat(2000)@(negedge clk);
    jumped_ticks=dut.ticks+32'd810000100;
    force dut.ticks=jumped_ticks;
    repeat(2)@(negedge clk);
    release dut.ticks;
    $display("INJECT: peripheral tick jump +810000100");
  endtask
  task automatic at_pc(input reg [31:0] target);
    // Raw pipeline PC can contain a flushed instruction. Require retirement.
    @(negedge clk);
    while(!(dut.cpu.obs_retire_valid && dut.cpu.obs_retire_pc==target))
      @(negedge clk);
  endtask
  // Optional ONLY for the four-state normal comparison; full-rate release
  // windows remain exercised by Verilator case 0. Firmware is not patched.
  initial begin : accelerated_release
    integer phase;
    #2;
    if($test$plusargs("FAST_RELEASE"))begin
      if(scenario!=0)$fatal(1,"FAST_RELEASE only supports normal case");
      for(phase=1;phase<=2;phase=phase+1)begin
        wait(release_entries==phase);
        repeat(2000)@(negedge clk);
        jumped_ticks=dut.ticks+32'd2700100;
        force dut.ticks=jumped_ticks;
        repeat(2)@(negedge clk);release dut.ticks;
        $display("INJECT: four-state release-window time acceleration phase=%0d",phase);
      end
    end
  end

  initial begin
    if(!$value$plusargs("CASE=%d",scenario))scenario=0;
    if(!$value$plusargs("LOG=%s",log_path))log_path="uart.log";
    fd=$fopen(log_path,"w");if(fd==0)$fatal(1,"log open");
    reset_cpu();
    case(scenario)
      1: begin
        at_pc(`PC_ram_check);
        @(negedge clk);dut.ram[0]=dut.ram[0]^32'h1;
        $display("INJECT: RAM word 0 bit 0");
      end
      2: begin
        force dut.soft_irq=1'b0;
        at_pc(`PC_wait_irq);expire_wait();
      end
      3: begin
        wait(press_prompt && irq_entries==3);expire_wait();
      end
      4: begin
        wait(press_prompt);repeat(1000)@(negedge clk);key=0;
        wait(releases==2 && release_entries==2);expire_wait();
      end
      5: begin
        wait(tx===1'b0);repeat(400)@(negedge clk);
        $display("INJECT: reset during UART frame");reset_cpu();
      end
      6: begin
        wait(press_prompt && irq_entries==3);
        $display("INJECT: reset while waiting KEY1");reset_cpu();
      end
      7: begin
        force dut.tx_busy=1'b1;
        $display("INJECT: UART status permanently busy");
      end
      8: begin
        at_pc(`PC_trap);
        $display("INJECT: reset inside exception handler");reset_cpu();
      end
      9: begin
        force dut.timer_irq=1'b0;
        wait(dut.compare_value!=32'hffffffff);
        at_pc(`PC_wait_irq);expire_wait();
      end
      10: begin
        key=0;
        wait(releases==1 && release_entries==1);expire_wait();
      end
      11: begin
        wait(releases==1);
        repeat(6)begin
          repeat(50000)@(negedge clk);key=0;
          repeat(50000)@(negedge clk);key=1;
          if(press_prompt)$fatal(1,"release stability accepted bounce too early");
        end
        $display("INJECT: six release bounce pulses, then stable release");
      end
      12: begin
        // Deliberately replace only the test ROM ECALL with EBREAK. The
        // firmware contract still expects cause 11, so E0 must be reported.
        dut.rom[(`PC_ecall_site-32'h80000000)/4]=32'h00100073;
        $display("INJECT: ECALL instruction replaced by EBREAK in test ROM");
      end
      13: begin
        wait(trap_entries==4);
        $display("INJECT: reset inside software interrupt handler");reset_cpu();
      end
      default: begin end
    endcase
    if(scenario==0 || scenario==5 || scenario==6 || scenario==8 || scenario==11 || scenario==13)begin
      wait(press_prompt);repeat(1000)@(negedge clk);key=0;
      repeat(20000)@(negedge clk);key=1;
      wait(finished_line);
      at_pc(`PC_idle);
      repeat(10000)@(negedge clk);
      if(fail_line)$fatal(1,"unexpected FAIL");
    end else begin
      at_pc(`PC_quiet_failure);
      repeat(3000)@(negedge clk);
      if(led!==8'h01)$fatal(1,"failure LED not set");
      if(scenario!=7 && !fail_line)$fatal(1,"missing FAIL line");
      if(finished_line)$fatal(1,"false success");
    end
    $fclose(fd);
    $display("DONE case=%0d cycles=%0d epochs=%0d",scenario,cycles,epoch);
    $finish;
  end
  initial begin
    repeat(150000000)@(posedge clk);
    $fatal(1,"watchdog case=%0d pc=%h",scenario,dut.cpu.writeBack_PC);
  end
endmodule
