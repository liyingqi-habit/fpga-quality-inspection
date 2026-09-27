`timescale 1ns/1ps
module cpu_directed_tb;
  reg clk=0, rstn=0;
  always #5 clk=~clk;
  wire tx;
  wire [7:0] led;
  localparam DIV=10;
  mini_soc #(.CLK_HZ(1152000), .DEBOUNCE_CYCLES(8)) dut(
    .clk(clk), .rstn(rstn), .key(1'b1), .uart_rx(1'b1), .uart_tx(tx), .led(led));
  integer stalled=0, writes=0, bytes_seen=0;
  reg holding=0;
  reg [70:0] held;
  wire [70:0] command={dut.d_write,dut.d_addr,dut.d_data,dut.d_size,dut.d_mask};
  always @(posedge clk) begin
    if(dut.reset) begin stalled=0; writes=0; holding=0; end
    else begin
      if(holding && (!dut.d_valid || command !== held))
        $fatal(1,"Command changed while backpressured");
      holding=dut.d_valid && !dut.d_ready;
      if(holding) begin stalled=stalled+1; held=command; end
      if(dut.uart_start) begin
        if(writes>=2 || dut.d_data[7:0] !== (writes==0 ? 8'h41 : 8'h42))
          $fatal(1,"Duplicate or incorrect accepted UART write");
        writes=writes+1;
      end
      if(led[7]) $fatal(1,"CPU directed failure signature=%h case=%0d",led,led & 8'h7f);
    end
  end
  task getbyte(output reg [7:0] b);
    integer i;
    begin
      @(negedge tx);
      repeat(DIV+DIV/2) @(negedge clk);
      for(i=0;i<8;i=i+1) begin b[i]=tx; repeat(DIV) @(negedge clk); end
      if(tx!==1'b1) $fatal(1,"Invalid UART stop bit");
    end
  endtask
  reg [7:0] b;
  initial forever begin
    getbyte(b);
    if(bytes_seen>=2 || b !== (bytes_seen==0 ? 8'h41 : 8'h42))
      $fatal(1,"UART wire output incorrect: %h",b);
    bytes_seen=bytes_seen+1;
  end
  integer run;
  initial begin
    for(run=1;run<=2;run=run+1) begin
      repeat(20) @(negedge clk); rstn=1;
      wait(led==8'h55 && bytes_seen==2 && !dut.tx_busy);
      repeat(30) @(negedge clk);
      if(stalled<20 || writes!=2 || dut.fault_count!==32'd1)
        $fatal(1,"Missing evidence: stall=%0d writes=%0d faults=%0d",stalled,writes,dut.fault_count);
      $display("PASS: run=%0d cases=27 UART=AB accepted=2 backpressure_cycles=%0d",run,stalled);
`ifdef MIGRATED_SOC
      $display("PASS: migrated case26 checks precise store trap PC/address/cause and mret");
`else
      $display("KNOWN_GAP: invalid store continued, diagnostic count=1; no precise store trap");
`endif
      rstn=0; bytes_seen=0;
    end
    $display("PASS: directed CPU tests and reset/reboot (RTL only)");
    $finish;
  end
  initial begin repeat(100000) @(posedge clk); $fatal(1,"Directed test timeout"); end
endmodule
