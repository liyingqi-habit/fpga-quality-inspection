`timescale 1ns/1ps
// Synthetic trace producer, NOT an LSU, CPU, AXI bridge or implementation proof.
module driver_tb;
  reg clk=0; always #5 clk=~clk;
  reg bus_reset=1, cpu_reset=0, allow_aw=1, allow_w=1;
  reg av=0,wv=0,br=0; wire ar,wr,bv; wire [1:0] resp;
  reg [31:0] addr=0,data=0; reg [3:0] strb=15;
  reg [7:0] delay_cycles=0; reg [1:0] code=0; reg never_respond=0;
  reg issue=0,retire=0,trap=0,release_slot=0,young_write=0;
  integer case_id=0,epoch=0,cycle=0,fd;
  reg [31:0] pc=0,trap_pc=0,trap_addr=0; reg [3:0] cause=0;
  write_target target(clk,bus_reset,allow_aw,allow_w,av,addr,ar,
    wv,data,strb,wr,bv,br,resp,delay_cycles,code,never_respond);
  always @(posedge clk) begin
    cycle=cycle+1;
    if(!bus_reset)
      $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
        cycle,case_id,epoch,cpu_reset,issue,pc,av,ar,addr,wv,wr,data,strb,bv,br,resp,
        retire,trap,trap_pc,trap_addr,cause,young_write,release_slot);
  end
  task tick; begin @(posedge clk); #1; @(negedge clk); end endtask
  task pulse_reset;
    begin cpu_reset=1; epoch=epoch+1; tick; cpu_reset=0; end
  endtask
  task send_aw;
    begin av=1; tick; av=0; end
  endtask
  task send_w;
    begin wv=1; tick; wv=0; end
  endtask
  // phase: 0 normal, 1 no channel accepted, 2 AW-only, 3 W-only,
  // 4 waiting B, 5 B handshake edge, 6 no response after CPU reset.
  task run_case(input integer id,order,latency,err,phase);
    integer j; reg [31:0] expected;
    begin
      case_id=id; pc=32'h80000100+4*id; addr=4*id;
      data=32'haabbcc00+id; strb=5; code=err; delay_cycles=latency;
      never_respond=(phase==6); issue=1; tick; issue=0;
      if(phase==1) begin
        pulse_reset; release_slot=1; tick; release_slot=0;
      end else begin
        if(order==0) begin
          send_aw;
          if(phase==2) pulse_reset;
          repeat(3) tick;
          send_w;
        end else if(order==1) begin
          send_w;
          if(phase==3) pulse_reset;
          repeat(3) tick;
          send_aw;
        end else begin
          // Present both while target applies independent backpressure.
          allow_aw=0; allow_w=0; av=1; wv=1;
          repeat(4) tick;
          allow_aw=1; allow_w=1; tick; av=0; wv=0;
        end
        if(phase==4 || phase==6) pulse_reset;
        if(phase==6) begin
          repeat(30) tick;
          if(bv) $fatal(1,"Never-response target produced B");
          // Stay quarantined forever; this case MUST be last.
        end else begin
          while(!bv) tick;
          repeat(3) tick; // B-channel backpressure, response must stay stable.
          br=1;
          if(phase==5) begin cpu_reset=1; epoch=epoch+1; end
          tick; br=0; cpu_reset=0;
          if(phase==0) begin
            if(err==0) retire=1;
            else begin trap=1;trap_pc=pc;trap_addr=addr;cause=7;end
            tick;retire=0;trap=0;
          end
          release_slot=1; tick; release_slot=0;
          expected=err==0 ? (32'h11bb3300 | id) : 32'h11223344;
          if(target.memory[id]!==expected) $fatal(1,"Target byte-mask/error policy wrong case=%0d",id);
        end
      end
      $display("TARGET_CASE: id=%0d phase=%0d response=%0d",id,phase,err);
      tick;
    end
  endtask
  initial begin
    fd=$fopen("trace.csv","w");
    if(!fd) $fatal(1,"Cannot create trace");
    $fdisplay(fd,"cycle,case,epoch,reset,issue,pc,av,ar,addr,wv,wr,data,strb,bv,br,resp,retire,trap,trap_pc,trap_addr,cause,young,release");
    tick;tick;bus_reset=0;
    run_case(0,0,0,0,0);
    run_case(1,1,7,0,0);
    run_case(2,2,31,0,0);
    run_case(3,0,9,2,0);
    run_case(4,1,3,3,0);
    run_case(5,0,0,0,1);
    run_case(6,0,8,0,2);
    run_case(7,1,8,0,3);
    run_case(8,2,15,0,4);
    run_case(9,0,2,2,5);
    run_case(10,0,0,0,0); // clean reuse following quarantined/drained cases
    run_case(11,2,0,0,6);
    $fclose(fd);
    $display("PASS: synthetic target scenarios, not CPU validation");
    $finish;
  end
  initial begin repeat(2000) @(posedge clk); $fatal(1,"Driver timeout"); end
endmodule
