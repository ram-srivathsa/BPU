package Testbench;

import bpu :: *;
import branch2 :: *;
import btb :: *;
import Utils :: *;
import BRAMCore :: *;
import GetPut::*;

`define READ False

//Dhrystone traces
String gv_file_pc="branch_pc.dump";
String gv_file_taken="branch_taken.dump";
String gv_file_imm="branch_imm.dump";

(*synthesize*)
module mkTestbench(Empty);
	Ifc_bpu bpu <- mkbpu;
	BRAM_PORT#(Bit#(16),Bit#(40)) bram_pc <- mkBRAMCore1Load(64000,False,gv_file_pc,False);
	BRAM_PORT#(Bit#(16),Bit#(32)) bram_taken <- mkBRAMCore1Load(64000,False,gv_file_taken,True);
	BRAM_PORT#(Bit#(16),Bit#(64)) bram_imm <- mkBRAMCore1Load(64000,False,gv_file_imm,False);
	
	//state of FSM
	Reg#(Bit#(3)) rg_state <- mkReg(0);
	//wait for flush to end
	Reg#(Bit#(16)) rg_wait <- mkReg(0);
	//to read pc value
	Wire#(Bit#(40)) wr_pc <- mkWire;
	Reg#(Bit#(40)) rg_pc_copy <- mkReg(0);
	//controls reading of file
	Reg#(Bit#(16)) rg_pc_addr <- mkReg(0);	
	//final prediction from bpu
	Reg#(Bool) rg_final_pred <- mkReg(False);

	//to read from branch_taken
	Wire#(Bit#(32)) wr_actual_taken <- mkWire;
	
	//predictor return value from mn_get	
	Reg#(Gv_return_predictor) rg_return_pred <- mkRegU;
	//btb return value from mn_get
	Reg#(Gv_return_btb) rg_return_btb <- mkRegU;
	
	//to read from branch_imm
	Wire#(Bit#(64)) wr_imm <- mkWire;

	//number of mispredictions
	Reg#(Bit#(16)) rg_mispred <- mkReg(0);
	
	//initiate flush
	rule rl_flush(rg_state==0);
		bpu.ma_flush();
		rg_state<=1;
	endrule
	
	//wait for flush to end
	rule rl_wait(rg_state==1);
		//$display("1");
		rg_wait<= rg_wait+1;
		if(rg_wait==4096)
			rg_state<=2;
	endrule

	//fetch from branch_pc
	rule rl_fetch_pc(rg_state==2);
		//$display("2");
		bram_pc.put(`READ,rg_pc_addr,?);
		rg_state<=3;
	endrule

	//put request into bpu
	rule rl_put(rg_state==3);
		//$display("3");
		let pc=bram_pc.read();
		Bit#(3) epoch=0;
		let req= tuple2(epoch,pc);
		bpu.send_prediction_request.put(req);
		rg_pc_copy<= pc;
		rg_state<=4;
	endrule

	//get response from bpu
	rule rl_get(rg_state==4);
		//$display("4");
		let {pred,pred_get,btb_get} <- bpu.prediction_response.get();
		rg_final_pred<= pred;
		rg_return_pred<= pred_get;
		rg_return_btb<= btb_get;
		bram_taken.put(`READ,rg_pc_addr,?);
		bram_imm.put(`READ,rg_pc_addr,?);
		rg_state<=5;
	endrule
	
	//train/update predictor and btb in bpu
	rule rl_train(rg_state==5);
		//$display("5");
		let taken=bram_taken.read();
		let imm=bram_imm.read();
		Gv_train_predictor pred_training_data;
		Gv_update_btb btb_update_data;

		pred_training_data.pc= rg_pc_copy[31:0];
		if(unpack(taken[0])==rg_final_pred)
			pred_training_data.truth=True;
		else
		begin
			pred_training_data.truth=False;
			rg_mispred<= rg_mispred+1;
		end

		pred_training_data.prediction= rg_return_pred.prediction;
		pred_training_data.counter=rg_return_pred.counter;
		pred_training_data.tag=rg_return_pred.tag;
		pred_training_data.bank_bits=rg_return_pred.bank_bits;
		pred_training_data.bank_num=rg_return_pred.bank_num;
		pred_training_data.bimodal=rg_return_pred.bimodal_counter;
		
		btb_update_data.pc= rg_pc_copy[31:0];
		btb_update_data.branch_imm= imm[11:0];
		btb_update_data.way_num= rg_return_btb.way_num;
		
		let train=tuple3(rg_return_btb.hit,pred_training_data,btb_update_data);
		bpu.ma_training(train);
		
		rg_pc_addr<= rg_pc_addr+1;
		rg_state<= 2;
	endrule

	//end simulation
	rule rl_end(rg_pc_addr==1000);
		$display("%0d",rg_mispred);
		$finish;
	endrule

endmodule
endpackage
