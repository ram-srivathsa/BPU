package Testbench;

import bpu :: *;
import branch2 :: *;
import btb :: *;
import Utils :: *;
import BRAMCore :: *;
import GetPut::*;

`define READ False

String gv_file_pc="branch_pc.dump";
String gv_file_taken="branch_taken.dump";
String gv_file_imm="branch_imm.dump";

(*synthesize*)
module mkTestbench(Empty);
	Ifc_bpu bpu <- mkbpu;
	BRAM_PORT#(Bit#(16),Bit#(40)) bram_pc <- mkBRAMCore1Load(64000,False,gv_file_pc,False);
	BRAM_PORT#(Bit#(16),Bit#(32)) bram_taken <- mkBRAMCore1Load(64000,False,gv_file_taken,True);
	BRAM_PORT#(Bit#(16),Bit#(44)) bram_imm <- mkBRAMCore1Load(64000,False,gv_file_imm,False);
	
	Reg#(Bit#(3)) rg_state <- mkReg(0);
	Reg#(Bit#(16)) rg_wait <- mkReg(0);
	Reg#(Bit#(16)) rg_count <- mkReg(0);

	Wire#(Bit#(40)) wr_pc <- mkWire;
	Reg#(Bit#(40)) rg_pc_copy <- mkReg(0);
	Reg#(Bit#(16)) rg_pc_addr <- mkReg(0);
	Reg#(Bool) rg_final_pred <- mkReg(False);

	Wire#(Bit#(32)) wr_actual_taken <- mkWire;
	
	Reg#(Gv_return_predictor) rg_return_pred <- mkRegU;
	Reg#(Gv_modreturn_btb) rg_return_btb <- mkRegU;
	
	Wire#(Bit#(44)) wr_imm <- mkWire;

	Reg#(Bit#(16)) rg_mispred <- mkReg(0);
	Reg#(Bit#(40)) rg_branch_pc <- mkReg(0);
	Reg#(Bit#(16)) cond_count <- mkReg(0);
	
	rule rl_flush(rg_state==0);
		bpu.ma_flush();
		rg_state<=1;
	endrule
	
	rule rl_wait(rg_state==1);
		//$display("1");
		rg_wait<= rg_wait+1;
		if(rg_wait==4096)
			rg_state<=2;
	endrule

	rule rl_fetch_pc(rg_state==2);
		//$display("2");
		bram_pc.put(`READ,rg_pc_addr,?);
		rg_state<=3;
	endrule

	rule rl_put(rg_state==3);
		//$display("3");
		let pc=bram_pc.read();
		Bit#(3) epoch=0;
		let req= tuple2(epoch,pc);
		bpu.send_prediction_request.put(req);
		rg_pc_copy<= pc;
		rg_state<=4;
	endrule

	rule rl_get(rg_state==4);
		//$display("4");
		//let {pred,pred_get,btb_get} <- bpu.prediction_response.get();
		let {epoch,pc,branch_pc,bpu_return} <- bpu.prediction_response.get();
		rg_final_pred<= bpu_return.final_pred;
		rg_return_pred<= bpu_return.tage_return;
		rg_return_btb<= bpu_return.btb_return;
		bram_taken.put(`READ,rg_pc_addr,?);
		bram_imm.put(`READ,rg_pc_addr,?);
		rg_branch_pc<= branch_pc;
		rg_state<=5;
	endrule
	
	rule rl_train(rg_state==5);
		//$display("5");
		let taken=bram_taken.read();
		let imm=bram_imm.read();
		Bool hit= (rg_return_btb.hit_bram || rg_return_btb.hit_vrg);
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
		

		if(taken[0]==1)
		begin
			cond_count<=cond_count+1;
			//if(!hit)
			//begin
				//$display("%0d:%h:%h",rg_pc_addr,rg_branch_pc[31:0],imm[31:0]);
				//rg_mispred<= rg_mispred+1;
			//	
			//end
		end
	
		pred_training_data.prediction= rg_return_pred.prediction;
		pred_training_data.counter=rg_return_pred.counter;
		pred_training_data.tag=rg_return_pred.tag;
		pred_training_data.bank_bits=rg_return_pred.bank_bits;
		pred_training_data.bank_num=rg_return_pred.bank_num;
		pred_training_data.bimodal=rg_return_pred.bimodal_counter;
		
		btb_update_data.pc= rg_pc_copy[31:0];
		//btb_update_data.conditional=True;
		btb_update_data.conditional= (imm[40]==0)?True:False;
		btb_update_data.branch_imm= imm[31:0];
		btb_update_data.way_num= rg_return_btb.way_num;
		
		//if(btb_update_data.conditional)
		//	cond_count<=cond_count+1;

		let train=tuple3(hit,pred_training_data,btb_update_data);
		bpu.ma_training(train);
		
		//$display("%0d:%h",btb_update_data.conditional,imm);
		rg_pc_addr<= rg_pc_addr+1;
		rg_state<= 2;
	endrule

	rule rl_end(rg_pc_addr==58800);
		$display("%0d:%0d",cond_count,rg_mispred);
		$finish;
	endrule

endmodule
endpackage
