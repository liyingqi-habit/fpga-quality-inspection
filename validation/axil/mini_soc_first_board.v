// Offline six-port wrapper; physical pin compatibility is NOT established.
module mini_soc_first_board(input wire clk,rstn,key,uart_rx,output wire uart_tx,led0);
  wire [7:0] gpio;
  axil_soc soc(.clk(clk),.rstn(rstn),.key(key),.uart_rx(uart_rx),.uart_tx(uart_tx),.led(gpio));
  assign led0=gpio[0];
endmodule
