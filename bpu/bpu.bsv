package bpu;

import BRAMCore::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import LFSR::*;
import ConfigReg::*;
import DReg::*;
import Connectable::*;
import GetPut::*;
/*===== project imports==== */
//import defined_types::*;
import btb :: *;
import branch2 :: *;
//`include "defined_parameters.bsv"

`define TAKEN True
`define NOT_TAKEN False
`define VADDR 40
`define SIZE_PC 32

typedef Bit#(`SIZE_PC) Gv_pc_size;
//return value of btb after extracting the branch pc
typedef struct{Bool hit_bram;Bool hit_vrg;Gv_ways way_num;} Gv_modreturn_btb deriving(Bits);
//return value of bpu as a whole; includes the predictor and btb returned values; branch address is extracted from btb return value and sent separately
typedef struct{Bool final_pred;Gv_return_predictor tage_return;Gv_modreturn_btb btb_return;} Gv_return_bpu deriving(Bits);

//according to the existing c-class interface
interface Ifc_bpu;
	//to pass the incoming pc to both the predictor as well as the btb
	interface Put#(Tuple2#(Bit#(3),Bit#(`VADDR))) send_prediction_request;
	//returns the final prediction as a Bool value along with the values returned by the predictor's and the btb's mn_get() methods, check their respective files; also sends the incoming pc
	interface Get#(Tuple4#(Bit#(3),Bit#(`VADDR),Bit#(`VADDR),Gv_return_bpu)) prediction_response;
	//initiates flush operations on both the btb as well as the predictor
	method Action ma_flush;
	//inputs training & update data for both the predictor as well as the btb; also inputs whether there was a 'hit' or a 'miss' on the BTB as a Bool and whether the branch was conditional or not
	method Action ma_training(Tuple3#(Bool,Gv_train_predictor,Gv_update_btb) training_data);
endinterface

(*synthesize*)
module mkbpu(Ifc_bpu);
	Ifc_branch tage_predictor <- mkbranch;
	Ifc_btb btb <- mkbtb;
	Reg#(Tuple2#(Bit#(3),Bit#(`VADDR))) rg_req_copy <- mkRegU;
	//FIFOF#(Tuple2#(Bit#(3),Bit#(`VADDR))) capture_prediction_request <-mkLFIFOF();
	interface send_prediction_request = interface Put 
		method Action put(Tuple2#(Bit#(3),Bit#(`VADDR)) req);
			let {epoch,vaddress} = req;
			`ifdef verbose $display($time,"\tBPU: Prediction Request for Address: %h",vaddress); `endif
			tage_predictor.ma_put(vaddress[31:0]);
			btb.ma_put(vaddress[31:0]);
			rg_req_copy<= req;
			//capture_prediction_request.enq(req);
		endmethod
	endinterface;
	
	//the final prediction depends not only on the prediction by the predictor but also on whether there was a hit or a miss in the BTB
	//if the predictor predicts 'taken' but there is a miss in the BTB, final prediction is 'not taken'
	interface prediction_response = interface Get
		method ActionValue#(Tuple4#(Bit#(3),Bit#(`VADDR),Bit#(`VADDR),Gv_return_bpu)) get;
			let tage_return= tage_predictor.mn_get();
			let btb_get= btb.mn_get();
			let {lv_epoch,lv_incoming_pc}= rg_req_copy;

			Bit#(`VADDR) branch_pc=zeroExtend(btb_get.branch_pc);

			Gv_modreturn_btb btb_return;
			btb_return.hit_bram= btb_get.hit_bram;
			btb_return.hit_vrg= btb_get.hit_vrg;
			btb_return.way_num= btb_get.way_num;

			Gv_return_bpu bpu_return;
			bpu_return.btb_return= btb_return;
			bpu_return.tage_return= tage_return;
			
			if(!(btb_return.hit_bram || btb_return.hit_vrg))
			begin
				bpu_return.final_pred= `NOT_TAKEN;
			end

			else
			begin
				if(btb_return.hit_bram)
				bpu_return.final_pred= unpack(tage_return.prediction);
				else
					bpu_return.final_pred= `TAKEN;
			end

			let resp=tuple4(lv_epoch,lv_incoming_pc,branch_pc,bpu_return);
			return resp;
		endmethod
	endinterface;
		
	//during training, we must check if the final prediction of 'not taken' was due to predictor alone or because there was a miss in the BTB
	//if it was due to miss in the BTB and the predictor predicted 'taken' and the prediction by the predictor was declared to be wrong by the processor, then the predictor was actually right
	//training must be done accordingly
	method Action ma_training(Tuple3#(Bool,Gv_train_predictor,Gv_update_btb) training_data);
		let {hit,predictor_train,btb_update} = training_data;
		let conditional = btb_update.conditional;
		if(conditional)
		begin
			if(!hit)
			begin
				btb.ma_update(btb_update);
				if(!predictor_train.truth)
				begin
					if(unpack(predictor_train.prediction))
					begin
						predictor_train.truth=True;
						tage_predictor.ma_train(predictor_train);
					end
				
					else
						tage_predictor.ma_train(predictor_train);
				end
		
				else
				begin
					if(unpack(predictor_train.prediction))
					begin
						predictor_train.truth=False;
						tage_predictor.ma_train(predictor_train);
					end
				
					else
						tage_predictor.ma_train(predictor_train);
				end
			end
		
			else
			
				tage_predictor.ma_train(predictor_train);
		end
			
		else
		begin
			if(!hit)
				btb.ma_update(btb_update);
		end
		

	endmethod
	
	method Action ma_flush;
		tage_predictor.ma_flush();
		btb.ma_flush();
	endmethod
	
endmodule 	
endpackage

