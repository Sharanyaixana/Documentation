`timescale 1ns/1ps

module top_tb;

parameter DEPTH = 8'd128;
parameter ADDR_WIDTH = 3'd7;
parameter IDLE = 3'd0;
parameter START = 3'd1;
parameter WAIT_FOR_MID = 3'd2;
parameter MID = 3'd3;
parameter PAIR_READY = 3'd4;

integer CLK_PERIOD_CNTRL = 5;
integer CLK_PERIOD_TIMING = 4;
integer CLK_PERIOD_ANALOG = 3;
integer CLK_PERIOD_READ = 8;
integer max_ana_ratio ; 
integer max_time_ratio ; 



reg rst_n;
reg timing_clk;
reg ctrl_clk;
reg rd_clk;
reg analog_clk;
reg [9:0] adc_data;
reg adc_trigger;
reg adc_eoc;
wire analog_done;
wire low_storage;
wire wfull;
wire rempty;
wire [19:0] rd_data;

// Config registers for param control
reg [7:0] start_to_mid_delay_val;
reg [7:0] mid_to_start_delay_val;
reg       rd_en_val;
reg [4:0] delay_start_val;
reg [4:0] delay_mid_val;
reg [3:0] max_analog_delay_val_ctrl;
reg [5:0] max_analog_delay_val_ana;
reg 	  over_max_delay;

// checker 
integer i, j , error , sweep1 ,sweep2;
reg [19:0] captured_data [0:127];
reg [9:0] adc1, adc2;
reg fail1, fail2, fail3, fail4, fail5, fail6, fail7; 

// Instantiate DUT
top #(
	.DEPTH(DEPTH),
	.ADDR_WIDTH(ADDR_WIDTH),
	.IDLE(IDLE),
	.START(START),
    	.WAIT_FOR_MID(WAIT_FOR_MID),
	.MID(MID),
	.PAIR_READY(PAIR_READY)
) u_top(
	.rst_n(rst_n),
	.timing_clk(timing_clk),
	.start_to_mid_delay(start_to_mid_delay_val),
	.mid_to_start_delay(mid_to_start_delay_val),
	.ctrl_clk(ctrl_clk),
	.rd_clk(rd_clk),
	.rd_en(rd_en_val),
	.over_max_delay(over_max_delay),
	.delay_start(delay_start_val),
	.delay_mid(delay_mid_val),
	.analog_clk(analog_clk),
	.max_analog_delay_ctrl(max_analog_delay_val_ctrl),
	.max_analog_delay_ana(max_analog_delay_val_ana),
	.adc_eoc(adc_eoc),
	.adc_data(adc_data),
	.start_slot_detected(start_slot_detected),
	.mid_slot_detected(mid_slot_detected),
    	.analog_done(analog_done),
	.low_storage(low_storage),
    	.rd_data(rd_data),
	.wfull(wfull),
	.rempty(rempty)
);

// Clocks
initial begin ctrl_clk = 0; forever #CLK_PERIOD_CNTRL ctrl_clk = ~ctrl_clk; end
initial begin timing_clk = 0; forever #CLK_PERIOD_TIMING timing_clk = ~timing_clk; end
initial begin analog_clk = 0; forever #CLK_PERIOD_ANALOG analog_clk = ~analog_clk; end
initial begin rd_clk = 0; forever #CLK_PERIOD_READ rd_clk = ~rd_clk; end

// max_analog
assign max_ana_ratio = (CLK_PERIOD_CNTRL > CLK_PERIOD_ANALOG) ? CLK_PERIOD_CNTRL/CLK_PERIOD_ANALOG : CLK_PERIOD_ANALOG/CLK_PERIOD_CNTRL;

// max_time
assign max_time_ratio = (CLK_PERIOD_CNTRL > CLK_PERIOD_TIMING) ? CLK_PERIOD_CNTRL/CLK_PERIOD_TIMING : CLK_PERIOD_TIMING/CLK_PERIOD_CNTRL;

// Task to perform analog capture
task do_analog_capture(
	input [7:0] start_to_mid,
	input [7:0] mid_to_start,
	input       rd_enable,
	input [4:0] delay_start_t,
	input [4:0] delay_mid_t,
	input [3:0] max_analog
);
begin
	start_to_mid_delay_val = start_to_mid;
	mid_to_start_delay_val = mid_to_start;
	rd_en_val              = rd_enable;
	delay_start_val        = delay_start_t;
	delay_mid_val          = delay_mid_t;
	max_analog_delay_val_ctrl  = max_analog;
	// based on calculation
	max_analog_delay_val_ana   = (CLK_PERIOD_CNTRL > CLK_PERIOD_ANALOG) ? (((max_analog - 3) * max_ana_ratio) -5 ) : (((max_analog - 3) / max_ana_ratio) -5) ;	
	over_max_delay 	       = 1'b0;
	
	wait(start_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	wait(mid_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	#50 adc_eoc=1'b0;
	adc_data = 0;

end
endtask

task read_data_from_fifo(
	input integer num_reads
);
begin 
	rd_en_val = 1'b1;
	@(posedge rd_clk);
	repeat(num_reads) begin 
		@(posedge rd_clk);
	end
	rd_en_val = 1'b0;
end
endtask

// Task to perform analog capture
task do_analog_capture_checker(
	input [7:0] start_to_mid,
	input [7:0] mid_to_start,
	input       rd_enable,
	input [4:0] delay_start_t,
	input [4:0] delay_mid_t,
	input [3:0] max_analog,
	input integer store_index
);
begin
	start_to_mid_delay_val = (CLK_PERIOD_CNTRL > CLK_PERIOD_TIMING) ? 
                         ((start_to_mid * max_time_ratio > 255) ? 255 : (start_to_mid * max_time_ratio)) : 
                         ((start_to_mid / max_time_ratio > 255) ? 255 : (start_to_mid / max_time_ratio));

	mid_to_start_delay_val = (CLK_PERIOD_CNTRL > CLK_PERIOD_TIMING) ? 
                         ((mid_to_start * max_time_ratio > 255) ? 255 : (mid_to_start * max_time_ratio)) : 
                         ((mid_to_start / max_time_ratio > 255) ? 255 : (mid_to_start / max_time_ratio));
	rd_en_val              = rd_enable;
	delay_start_val        = delay_start_t;
	delay_mid_val          = delay_mid_t;
	max_analog_delay_val_ctrl  = max_analog;
	// based on calculation
	max_analog_delay_val_ana   = (CLK_PERIOD_CNTRL > CLK_PERIOD_ANALOG) ? (((max_analog - 3) * max_ana_ratio) -5 ) : (((max_analog - 3) / max_ana_ratio) -5) ;
	over_max_delay	       = 1'b0;

	wait(start_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc1 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;

	wait(mid_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc2 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	//store to memory 
	captured_data[store_index] = {adc1,adc2};

end
endtask

task read_data_from_fifo_checker(
	input integer num_reads
);
begin 
	rd_en_val = 1'b1;
	j=1'b0;
	@(posedge rd_clk);
	repeat(num_reads) begin 
		@(posedge rd_clk);
		if(rd_data !== captured_data[j]) 
		begin
			$display("error rd_data = %0h , doesnt match captured = %0h , j = %0d",rd_data,captured_data[j], j);
			error = error +1;
		end
		else 
		begin
			$display("correct rd_data = %0h ,  match captured = %0h , j = %0d",rd_data,captured_data[j], j);
		end
		j = j+1;

	end
	rd_en_val = 1'b0;
end
endtask

task write_data_to_fifo (
	input integer write_num
);
begin 
	for (i=0 ; i<write_num ; i= i+1) 
	begin
	// slot capture
	do_analog_capture(8'd50, 8'd32, 1'b0, 5'd20, 5'd25, 4'd10);
	$display("capture number : %0d",i);
	end 

end
endtask

task checking_data (
	input integer number
);
begin 
	for (i=0 ; i< number ; i= i+1) 
	begin
	// slot capture
	do_analog_capture_checker (8'd50, 8'd32, 1'b0, 5'd20, 5'd25, 4'd10,i);
	$display("capture number : %0d",i);
	end 

	read_data_from_fifo_checker(number);
	if (error) 
		begin 
			$display ("test checking data failed error :%0d", error);
			fail1 = 1'b1;
			error = 0;
		end


end
endtask

task reset; 
begin 
	#6 rst_n = 1'b0;
	#6 rst_n = 1'b1;
end 
endtask

task reset_fail;
begin 
	error = 0;
	fail1 = 0;
	fail2 = 0;
	fail3 = 0;
	fail4 = 0;
	fail5 = 0;
	fail6 = 0;
	fail7 = 0;

end
endtask

task reset_all;
begin
	
	reset();
	reset_fail();
end
endtask

task sweep_delay(
input integer sweep_delay
);
begin 
	i = 0; error = 0;
	for (sweep1 = 19; sweep1 < sweep_delay; sweep1 = sweep1 +1)
	begin 
		for (sweep2 = 19; sweep2 < sweep_delay ; sweep2 = sweep2 +1 )
		begin 
			do_analog_capture_checker (8'd50, 8'd50, 1'b0, sweep1, sweep2, 4'd10 , i);
			i = i +1;

			if (i == 120)begin 
				read_data_from_fifo_checker(i);
				i = 0;
				reset();
			end

		end
	end
	read_data_from_fifo_checker(i-1);
	if (error) 
		begin
		$display ("test sweep_delay failed error :%0d", error);
		fail2 = 1'b1;
		error = 0;
	end
end
endtask

task sweep_delta(
input integer sweep_delay
);
begin 
	i = 0; error = 0;
	for (sweep1 = 36; sweep1 < sweep_delay; sweep1 = sweep1 +1)
	begin 
		for (sweep2 = 36; sweep2 < sweep_delay ; sweep2 = sweep2 +1 )
		begin 
			do_analog_capture_checker (sweep1, sweep2, 1'b0, 5'd20, 5'd20, 4'd10 , i);
			i = i +1;

			if (i == 120)begin 
				read_data_from_fifo_checker(i);
				i = 0;
				reset();
			end

		end
	end
	read_data_from_fifo_checker(i-1);
	if (error) 
		begin
		$display ("test sweep_delta failed error :%0d", error);
		fail6 = 1'b1;
		error = 0;
	end
end
endtask


task long_delay (
	input integer number
);
begin 
	for (i=0 ; i< number ; i= i+1) 
	begin
	// slot capture
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd10, i , 1'b1 , 1'b1);
	$display("capture number : %0d",i);
	end 

	read_data_from_fifo_checker_long(number);
	if (error)
		begin
			$display ("test checking data failed error :%0d", error);
			fail3 = 1'b1;
			error = 0;
		end

	for (i=0 ; i< number ; i= i+1) 
	begin
	// slot capture
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd10, i , 1'b1 , 1'b0);
	$display("capture number : %0d",i);
	end 

	read_data_from_fifo_checker_long(number);
	if (error)
		begin
			$display ("test checking data failed error :%0d", error);
			fail4 = 1'b1;
			error = 0;
		end


	for (i=0 ; i< number ; i= i+1) 
	begin
	// slot capture
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd10, i , 1'b0 , 1'b1);
	$display("capture number : %0d",i);
	end 

	read_data_from_fifo_checker_long(number);
	if (error)
		begin
			$display ("test checking data failed error :%0d", error);
			fail5 = 1'b1;
			error = 0;
		end


end
endtask

task do_analog_capture_checker_long(
	input [7:0] start_to_mid,
	input [7:0] mid_to_start,
	input       rd_enable,
	input [4:0] delay_start_t,
	input [4:0] delay_mid_t,
	input [3:0] max_analog,
	input integer store_index,
	input 	    delay_1,
	input	    delay_2
);
begin
	start_to_mid_delay_val = start_to_mid;
	mid_to_start_delay_val = mid_to_start;
	rd_en_val              = rd_enable;
	delay_start_val        = delay_start_t;
	delay_mid_val          = delay_mid_t;
	max_analog_delay_val_ctrl  = max_analog;
	// based on calculation
	max_analog_delay_val_ana   = (CLK_PERIOD_CNTRL > CLK_PERIOD_ANALOG) ? (((max_analog - 3) * max_ana_ratio) -5 ) : (((max_analog - 3) / max_ana_ratio) -5) ;	
	over_max_delay 	       = delay_1;
	
	wait(start_slot_detected);
	wait(analog_done);
	over_max_delay 	       = delay_2;
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc1 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	
	wait(mid_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc2 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	//store to memory 
	captured_data[store_index] = {adc1,adc2};

end
endtask

task read_data_from_fifo_checker_long(
	input integer num_reads
);
begin 
	rd_en_val = 1'b1;
	j=1'b0;
	@(posedge rd_clk);
	repeat(num_reads) begin 
		@(posedge rd_clk);
		if(rd_data !== 0) 
		begin
			$display("error rd_data = %0h , j = %0d",rd_data, j);
			error = error +1;
		end
		else 
		begin
			$display("correc rd_data = %0h ,  j = %0d",rd_data, j);
		end
		j = j+1;

	end
	rd_en_val = 1'b0;
end
endtask

task do_analog_capture_checker_short(
	input [7:0] start_to_mid,
	input [7:0] mid_to_start,
	input       rd_enable,
	input [4:0] delay_start_t,
	input [4:0] delay_mid_t,
	input [3:0] max_analog,
	input integer store_index,
	input 	    delay_1,
	input	    delay_2
);
begin
	start_to_mid_delay_val = start_to_mid;
	mid_to_start_delay_val = mid_to_start;
	rd_en_val              = rd_enable;
	delay_start_val        = delay_start_t;
	delay_mid_val          = delay_mid_t;
	max_analog_delay_val_ctrl  = max_analog;
	// based on calculation
	max_analog_delay_val_ana   =  1'b1 ;	
	over_max_delay 	       = delay_1;
	
	wait(start_slot_detected);
	wait(analog_done);
	over_max_delay 	       = delay_2;
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc1 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	
	wait(mid_slot_detected);
	wait(analog_done);
	adc_trigger = 1'b1;
	#3 adc_trigger = 1'b0;
	adc_eoc = 1'b1;
	adc_data = $urandom % 11'd1024;
	adc2 = adc_data;
	#50 adc_eoc=1'b0;
	adc_data = 0;
	
	//store to memory 
	captured_data[store_index] = {adc1,adc2};

end
endtask


task regression;
begin 
	
	reset();
	
	// write for X values
	// CHECK FIFO OVERFLOW + BASIC DELAY TEST + OVERWRITE BEFORE READ
	 write_data_to_fifo(300);

	// read for X values
	// CHECK FIFO BURST READ + READ AND WRITE
	 read_data_from_fifo(128);
	
	// reset 
	// RESET CHECK
	 reset();

	
	// WR_POINTER < RD_POINTER for CODE COV
 	 write_data_to_fifo(127);
	 read_data_from_fifo(120);
	 write_data_to_fifo(127);
	 read_data_from_fifo(120);
	 write_data_to_fifo(127);

	// reset 
	// RESET CHECK
	 reset();

	// X data checked 
	// CHECK FIFO BURST READ
	 checking_data(128);

	 reset();

	// Sweep at PD delay 
	// DELAY SWEEP
	 sweep_delay(32);
	
	 reset();
 
	// Give analog delay more than max analog 
	// LONG ANALOG DELAY
	 long_delay(2);

	 reset();

	
	// giving different delta between the slot 
	// EXTRA WAIT BETWEEN SLOTS
	 sweep_delta(255);
	
	if (fail1|fail2|fail3|fail4|fail5|fail6|fail7)
	$display ("you know nothing John Snow");	   	
end
endtask

task different_clk;
begin
	
	reset_all();

	//NOMINAL CASE
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	//SLOW CONTROLLER
	CLK_PERIOD_CNTRL = 10;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	//FAST CONTROLLER
	CLK_PERIOD_CNTRL = 2;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	//FAST TIME DOMAIN
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 2;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	// SLOW ANALOG MODULE
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 7;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	// FAST ANALOG MODULE
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 2;
	CLK_PERIOD_READ = 8;

	reset_all();

	regression();

	reset_all();

	// FAST READ DOMAIN
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 2;

	reset_all();

	regression();

	reset_all();

	// SLOW READ DOMAIN
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 4;
	CLK_PERIOD_ANALOG = 3;
	CLK_PERIOD_READ = 10;

	reset_all();

	regression();

	reset_all();
	
	// SYNCHRONIZE DOMAIN
	CLK_PERIOD_CNTRL = 5;
	CLK_PERIOD_TIMING = 5;
	CLK_PERIOD_ANALOG = 5;
	CLK_PERIOD_READ = 5;

	reset_all();

	regression();

end
endtask



	
// Main stimulus
initial begin
	rst_n = 0;
	adc_trigger = 0;
	adc_eoc = 0;
	adc_data = 10'b0;

	reset();

	reset_all();

	

	// different max_analog
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd7, 1'b1 , 1'b0 , 1'b0);
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd10, 1'b1 , 1'b0 , 1'b0);
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd7, 1'b1 , 1'b0 , 1'b0);
	do_analog_capture_checker_long (8'd100, 8'd100, 1'b0, 5'd20, 5'd20, 4'd13, 1'b1 , 1'b0 , 1'b0);

	reset();

	reset_all();

	different_clk();
	

       
 

       
	#500 $finish;
end

endmodule
