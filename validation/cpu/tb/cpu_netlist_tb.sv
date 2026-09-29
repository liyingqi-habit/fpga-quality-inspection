`timescale 1ns/1ps
// Black-box functional check of the unmodified PDS synthesis netlist.
module cpu_netlist_tb;
  reg clk=0, rstn=0, rx=1, grs_n=0;
  always #18.5185 clk=~clk;
  wire tx, led0;
  localparam DIV=234;
  GTP_GRS GRS_INST(.GRS_N(grs_n));
  mini_soc_first_board dut(.clk(clk),.rstn(rstn),.key(1'b1),
    .uart_rx(rx),.uart_tx(tx),.led0(led0));
  task expect_text(input string expected);
    reg [7:0] b;
    integer i,j;
    begin
      for(i=0;i<expected.len();i=i+1) begin
        @(negedge tx);
        repeat(DIV+DIV/2) @(negedge clk);
        for(j=0;j<8;j=j+1) begin b[j]=tx; repeat(DIV) @(negedge clk); end
        if(tx!==1'b1 || b!==expected[i])
          $fatal(1,"Netlist UART mismatch idx=%0d expected=%h actual=%h stop=%b",i,expected[i],b,tx);
        $write("%c",b); $fflush();
      end
    end
  endtask
  task sendbyte(input [7:0] b);
    integer i;
    begin
      @(negedge clk); rx=0; repeat(DIV) @(negedge clk);
      for(i=0;i<8;i=i+1) begin rx=b[i]; repeat(DIV) @(negedge clk); end
      rx=1;
    end
  endtask
  integer run;
  integer cycles=0;
  always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles%20000==0) begin
      $display("\nPROGRESS: netlist cycles=%0d tx=%b led0=%b",cycles,tx,led0);
      $fflush();
    end
  end
  initial begin
    repeat(30) @(negedge clk); grs_n=1;
    for(run=1;run<=2;run=run+1) begin
      repeat(20) @(negedge clk); rstn=1;
      expect_text("VEX MINI RV32IM\015\012SELFTEST PASS\015\012KEY=1\015\012");
      sendbyte(8'h5a); expect_text("Z");
      if(led0!==1'b1) $fatal(1,"Netlist LED0 unexpected");
      $display("\nPASS: netlist boot=%0d selftest and UART echo",run);
      @(negedge clk); rstn=0;
    end
    $display("PASS: synthesis netlist functional regression (no SDF)");
    $finish;
  end
  initial begin repeat(400000) @(posedge clk); $fatal(1,"Netlist timeout"); end
endmodule
