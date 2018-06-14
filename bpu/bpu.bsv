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

//according to the existing c-class interface
interface Ifc_bpu;
	//to pass the incoming pc to both the predictor as well as the btb
	interface Put#(Tuple2#(Bit#(3),Bit#(`VADDR))) send_prediction_request;
	//returns the final prediction as a Bool value along with the values returned by the predictor's and the btb's mn_get() methods, check their respective files
	interface Get#(Tuple3#(Bool,Gv_return_predictor,Gv_return_btb)) prediction_response;
	//initiates flush operations on both the btb as well as the predictor
	method Action ma_flush;
	//inputs training & update data for both the predictor as well as the btb; also inputs whether there was a 'hit' or a 'miss' on the BTB as a Bool 
	method Action ma_training(Tuple3#(Bool,Gv_train_predictor,Gv_update_btb) training_data);
endinterface

(*synthesize*)
module mkbpu(Ifc_bpu);
	Ifc_branch tage_predictor <- mkbranch;
	Ifc_btb btb <- mkbtb;
	Reg#(Gv_pc_size) rg_pc_copy <- mkReg(0);
	//FIFOF#(Tuple2#(Bit#(3),Bit#(`VADDR))) capture_prediction_request <-mkLFIFOF();
	interface send_prediction_request = interface Put 
		method Action put(Tuple2#(Bit#(3),Bit#(`VADDR)) req);
			let {epoch,vaddress} = req;
			`ifdef verbose $display($time,"\tBPU: Prediction Request for Address: %h",vaddress); `endif
			tage_predictor.ma_put(vaddress[31:0]);
			btb.ma_put(vaddress[31:0]);
			rg_pc_copy<= vaddress[31:0];
			//capture_prediction_request.enq(req);
		endmethod
	endinterface;
	
	//the final prediction depends not only on the prediction by the predictor but also on whether there was a hit or a miss in the BTB
	//if the predictor predicts 'taken' but there is a miss in the BTB, final prediction is 'not taken'
	interface prediction_response = interface Get
		method ActionValue#(Tuple3#(Bool,Gv_return_predictor,Gv_return_btb)) get;
			let tage_return= tage_predictor.mn_get();
			let btb_return= btb.mn_get();
			Bool final_predict;
			if(!btb_return.hit)
			begin
				final_predict= `NOT_TAKEN;
				btb_return.branch_pc= rg_pc_copy+4;
			end

			else
			begin
				final_predict= unpack(tage_return.prediction);
				if(!unpack(tage_return.prediction))
					btb_return.branch_pc= rg_pc_copy+4;
			end

			let resp=tuple3(final_predict,tage_return,btb_return);
			return resp;
		endmethod
	endinterface;
		
	//during training, we must check if the final prediction of 'not taken' was due to predictor alone or because there was a miss in the BTB
	//if it was due to miss in the BTB and the predictor predicted 'taken' and the prediction by the predictor was declared to be wrong by the processor, then the predictor was actually right
	//training must be done accordingly
	method Action ma_training(Tuple3#(Bool,Gv_train_predictor,Gv_update_btb) training_data);
		let {hit,predictor_train,btb_update} = training_data;
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
	endmethod
	
	method Action ma_flush;
		tage_predictor.ma_flush();
		btb.ma_flush();
	endmethod
	
endmodule 	
endpackage

