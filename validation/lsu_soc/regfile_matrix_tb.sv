`timescale 1ns/1ps
`include "matrix_config.vh"
module regfile_matrix_tb;
  reg clk=0,rstn=0,grs_n=0;always #18.5185 clk=~clk;
  wire tx,led0;
`ifdef GATE
  GTP_GRS GRS_INST(.GRS_N(grs_n));
`endif
  mini_soc_first_board dut(.clk(clk),.rstn(rstn),.key(1'b1),.uart_rx(1'b1),.uart_tx(tx),.led0(led0));
`ifdef GATE
  wire fire=dut.soc.d_rsp_ready_vname.D && !dut.soc.d_rsp_ready_vname.R;
`else
  wire fire=dut.soc.cpu.dBus_cmd_valid && dut.soc.cpu.dBus_cmd_ready;
`endif
  wire wr=dut.soc.cpu.dBus_cmd_payload_wr;
  wire[31:0] addr=dut.soc.cpu.dBus_cmd_payload_address,data=dut.soc.d_data;
  reg[31:0] expected[0:`MATRIX_CASES-1];
  reg[1:0] contexts[0:`MATRIX_CASES-1];
  integer boot,case_id=0,fd,cfd,k,cycles=0,context_id;
  integer col1[0:3],col2[0:3],div_hits=0;
  reg done=0,at_div10=0;
`ifdef GATE
  reg hit1,hit2;
  always @(posedge dut.soc.cpu.RegFilePlugin_regFile.CLKA) begin
    hit1=rstn && dut.soc.cpu.RegFilePlugin_regFile.WEA &&
      dut.soc.cpu.RegFilePlugin_regFile.ADDRA==dut.soc.cpu.RegFilePlugin_regFile.ADDRB;
    hit2=rstn && dut.soc.cpu.RegFilePlugin_regFile_1.WEA &&
      dut.soc.cpu.RegFilePlugin_regFile_1.ADDRA==dut.soc.cpu.RegFilePlugin_regFile_1.ADDRB;
    if(case_id<`MATRIX_CASES) begin
      context_id=contexts[case_id];
      if(hit1) col1[context_id]=col1[context_id]+1;
      if(hit2) col2[context_id]=col2[context_id]+1;
      if(hit1 || hit2) $fdisplay(cfd,"%0d,%0d,%0d,%0d,%0d",boot,case_id,hit1,hit2,cycles);
    end
`ifdef POISON_RAW
    #0.001;
    release dut.soc.cpu.decode_RegFilePlugin_rs1Data;
    release dut.soc.cpu.decode_RegFilePlugin_rs2Data;
    #0.999;
    if(hit1) force dut.soc.cpu.decode_RegFilePlugin_rs1Data=32'hxxxxxxxx;
    if(hit2) force dut.soc.cpu.decode_RegFilePlugin_rs2Data=32'hxxxxxxxx;
`endif
  end
`endif
  always @(posedge clk) begin
    cycles=cycles+1;
    if(cycles%10000==0) begin $display("PROGRESS boot=%0d case=%0d cycles=%0d",boot,case_id,cycles);$fflush();end
    if(rstn) begin
      if(dut.soc.cpu.memory_DivPlugin_div_counter_value==10 && !at_div10) div_hits=div_hits+1;
      at_div10=(dut.soc.cpu.memory_DivPlugin_div_counter_value==10);
    end
    if(rstn && fire) begin
      if(wr!==1'b1 || (^addr)===1'bx || (^data)===1'bx) $fatal(1,"Unexpected/unknown matrix bus access");
      $fdisplay(fd,"%0d,%08h,%08h",boot,addr,data);
      if(addr==32'h10000010 && data==32'h6b) begin
        if(case_id!=`MATRIX_CASES) $fatal(1,"Early completion");
        done=1;
      end else begin
        if(case_id>=`MATRIX_CASES || addr!==(32'h80004800+case_id*4)) $fatal(1,"Wrong-path or out-of-order store case=%0d addr=%h",case_id,addr);
        if(data!==expected[case_id]) $fatal(1,"Matrix reference mismatch case=%0d actual=%h expected=%h",case_id,data,expected[case_id]);
        case_id=case_id+1;
      end
    end
  end
  initial begin
    $readmemh("matrix_expected.hex",expected);
    $readmemh("matrix_context.hex",contexts);
`ifdef EXPECTATION_MUTATION
    expected[0]=expected[0]^1;
`endif
    fd=$fopen("commands.csv","w");cfd=$fopen("collisions.csv","w");
    repeat(30) @(negedge clk);grs_n=1;
    for(boot=1;boot<=2;boot=boot+1) begin
      case_id=0;done=0;div_hits=0;at_div10=0;
      for(k=0;k<4;k=k+1) begin col1[k]=0;col2[k]=0;end
      repeat(20) @(negedge clk);rstn=1;
      wait(done);repeat(25) @(negedge clk);
      if(div_hits!=`MATRIX_DIVIDES) $fatal(1,"Divider stall coverage mismatch hits=%0d",div_hits);
      for(k=0;k<4;k=k+1) if ((`MATRIX_CONTEXTS >> k) & 1) begin
`ifdef GATE
        if(col1[k]==0 || col2[k]==0) $fatal(1,"Missing collision context=%0d",k);
`endif
        $display("COVER: boot=%0d context=%0d rs1_collisions=%0d rs2_collisions=%0d",boot,k,col1[k],col2[k]);
      end
      $display("PASS: matrix boot=%0d cases=%0d divider_stalls=%0d branch_cases=%0d",boot,`MATRIX_CASES,div_hits,`MATRIX_FLUSHES);$fflush();rstn=0;
    end
    $fclose(fd);$fclose(cfd);$display("PASS: regfile matrix functional regression (no SDF)");$finish;
  end
  initial begin repeat(100000) @(posedge clk);$fatal(1,"Matrix timeout");end
endmodule
