`timescale 1ns/1ps
// Same firmware and bus-level oracle for RTL and the unmodified synthesis netlist.
module netlist_tb;
  reg clk=0,rstn=0,grs_n=0;always #18.5185 clk=~clk;
  wire tx,led0;
`ifdef GATE
  GTP_GRS GRS_INST(.GRS_N(grs_n));
`endif
  mini_soc_first_board dut(.clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led0(led0));
  reg[31:0] expected[0:255],shadow[0:255];
  integer boot,k,lane,index,reads=0,writes=0,fd,cycles=0,coll1=0,coll2=0;
  reg done=0;
`ifdef GATE
  // With RESPONSE_DELAY=0 this register D is the accepted-command pulse.
  // Hash-pinned netlist optimized away d_valid/formalMask as standalone nets.
  wire fire=dut.soc.d_rsp_ready_vname.D && !dut.soc.d_rsp_ready_vname.R;
  wire[3:0] mask=(dut.soc.d_size==0 ? 4'b0001 : dut.soc.d_size==1 ? 4'b0011 : 4'b1111)<<addr[1:0];
`else
  wire fire=dut.soc.cpu.dBus_cmd_valid && dut.soc.cpu.dBus_cmd_ready;
  wire[3:0] mask=dut.soc.cpu.dBus_cmd_payload_mask;
`endif
  wire wr=dut.soc.cpu.dBus_cmd_payload_wr;
  wire[31:0] addr=dut.soc.cpu.dBus_cmd_payload_address;
  wire[31:0] data=dut.soc.d_data;
`ifdef GATE
  reg hit1,hit2;
`ifdef POISON_RAW
  // Test-only fault injection: collision outputs are unspecified for this audit.
  // Hold X across the next consumer edge; never modify the vendor model/netlist.
  always @(posedge dut.soc.cpu.RegFilePlugin_regFile.CLKA) begin
    hit1=rstn && dut.soc.cpu.RegFilePlugin_regFile.WEA &&
      dut.soc.cpu.RegFilePlugin_regFile.ADDRA==dut.soc.cpu.RegFilePlugin_regFile.ADDRB;
    hit2=rstn && dut.soc.cpu.RegFilePlugin_regFile_1.WEA &&
      dut.soc.cpu.RegFilePlugin_regFile_1.ADDRA==dut.soc.cpu.RegFilePlugin_regFile_1.ADDRB;
    #0.001;
    release dut.soc.cpu.decode_RegFilePlugin_rs1Data;
    release dut.soc.cpu.decode_RegFilePlugin_rs2Data;
    #0.999;
    if(hit1) force dut.soc.cpu.decode_RegFilePlugin_rs1Data=32'hxxxxxxxx;
    if(hit2) force dut.soc.cpu.decode_RegFilePlugin_rs2Data=32'hxxxxxxxx;
  end
`endif
  // Actual primitive collisions, not inferred from source instruction distance.
  always @(posedge dut.soc.cpu.RegFilePlugin_regFile.CLKA) begin
    if(rstn && dut.soc.cpu.RegFilePlugin_regFile.WEA &&
       dut.soc.cpu.RegFilePlugin_regFile.ADDRA==dut.soc.cpu.RegFilePlugin_regFile.ADDRB) coll1=coll1+1;
    if(rstn && dut.soc.cpu.RegFilePlugin_regFile_1.WEA &&
       dut.soc.cpu.RegFilePlugin_regFile_1.ADDRA==dut.soc.cpu.RegFilePlugin_regFile_1.ADDRB) coll2=coll2+1;
  end
`endif
  always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles%10000==0) begin $display("PROGRESS cycles=%0d reads=%0d writes=%0d",cycles,reads,writes);$fflush();end
    if(rstn && fire) begin
      if((^addr)===1'bx || (wr && ((^data)===1'bx || (^mask)===1'bx))) $fatal(1,"Unknown bus command");
      $fdisplay(fd,"%0d,%0d,%08h,%08h,%01h",boot,wr,addr,wr?data:0,wr?mask:0);
      if(wr) begin
        writes=writes+1;
        if(addr>=32'h80004800 && addr<32'h80004c00) begin
          index=(addr-32'h80004800)>>2;
          for(lane=0;lane<4;lane=lane+1)
            if(mask[lane]) shadow[index][lane*8+:8]=data[lane*8+:8];
        end else if(addr==32'h10000010 && data==32'h5a) done=1;
        else $fatal(1,"Unexpected store/trap address=%h data=%h",addr,data);
      end else reads=reads+1;
    end
  end
  initial begin
    $readmemh("mixed_expected.hex",expected);
`ifdef EXPECTATION_MUTATION
    expected[4]=expected[4]^1;
`endif
    fd=$fopen("commands.csv","w");
    repeat(30) @(negedge clk);grs_n=1;
    for(boot=1;boot<=2;boot=boot+1) begin
      for(k=0;k<256;k=k+1) shadow[k]=32'hxxxxxxxx;
      reads=0;writes=0;done=0;coll1=0;coll2=0;
      repeat(20) @(negedge clk);rstn=1;
      wait(done);repeat(25) @(negedge clk);
      for(k=0;k<256;k=k+1) if(shadow[k]!==expected[k]) $fatal(1,"Reference mismatch word=%0d",k);
      if(reads!=192 || writes!=321) $fatal(1,"Missing mixed coverage");
`ifdef GATE
      if(coll1==0 || coll2==0) $fatal(1,"Primitive collision coverage missing");
`endif
      $display("PASS: boot=%0d words=256 reads=192 writes=321 collisions_rs1=%0d rs2=%0d",boot,coll1,coll2);$fflush();
      rstn=0;
    end
    $fclose(fd);$display("PASS: mixed netlist-compatible functional regression (no SDF)");$finish;
  end
  initial begin repeat(150000) @(posedge clk);$fatal(1,"Netlist mixed timeout");end
endmodule
