//------------------------------------------------------------------------
// Title       : Neuron controller
// Version     : 0.1
// Author      : Khadeer Ahmed
// Date created: 11/28/2016
// -----------------------------------------------------------------------
// Discription : controller for the neuron
// NurnTyp_i: 0: I&F
//			  1: ReLU
// -----------------------------------------------------------------------
// Maintainance History
// -ver x.x : date : auth
//		details
//------------------------------------------------------------------------

`timescale 1ns/100ps

module NurnCtrlr
#(
	parameter NUM_NURNS    = 4  ,
	parameter NUM_AXONS    = 4  ,

	parameter NURN_CNT_BIT_WIDTH   = 2  ,
	parameter AXON_CNT_BIT_WIDTH   = 2	,

	parameter DIR_ID = ""
)
(
	input 												clk_i			,
	input 												rst_n_i			,

	input 												start_i			,

	//data path
	output 												rstAcc_o 		,
	output 	reg											accEn_o 		,
	output 	reg											cmp_th_o 		,
	output 												buffMembPot_o 	,
	output 	reg											updtPostSpkHist_o,
	output 												addLrnRt_o 		,
	output 												enQuant_o 		,
	output 	reg											buffBias_o 		,
	output 												lrnUseBias_o 	,
	output 												cmpSTDP_o 		,
	output 	reg [1:0] 									sel_rclAdd_B_o,
	output 	reg [1:0] 									sel_wrBackStat_B_o,

	//config mem
	input 												biasLrnMode_i 	,
	output [NURN_CNT_BIT_WIDTH-1:0]						Addr_Config_A_o,
	output reg											rdEn_Config_A_o 	,

	input 												NurnType_i 		,
	output [NURN_CNT_BIT_WIDTH-1:0]						Addr_Config_B_o,
	output 	reg											rdEn_Config_B_o ,

	input 												axonLrnMode_i 	,
	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_Config_C_o,
	output 												rdEn_Config_C_o 	,

	//status mem
	output reg [NURN_CNT_BIT_WIDTH+2-1:0] 				Addr_StatRd_A_o,
	output reg											rdEn_StatRd_A_o	,

	output reg [NURN_CNT_BIT_WIDTH+2-1:0] 				Addr_StatWr_B_o,
	output 												wrEn_StatWr_B_o	,

	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_StatRd_C_o,
	output 												rdEn_StatRd_C_o	,

	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_StatWr_D_o,
	output 												wrEn_StatWr_D_o	,

	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_StatRd_E_o,
	output 	reg											rdEn_StatRd_E_o	,

	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_StatRd_F_o,
	output 												rdEn_StatRd_F_o	,

	output [NURN_CNT_BIT_WIDTH+AXON_CNT_BIT_WIDTH-1:0] 	Addr_StatWr_G_o,
	output 												wrEn_StatWr_G_o	

);

	//STATE ENCODING
	//--------------------------------------------------//
	//recall state machine								//learning state machine
	parameter [5:0] RCL_IDLE_S		 	= 6'h01;     	parameter [3:0] LRN_IDLE_S		= 4'h1;
	parameter [5:0] RCL_ACC_WT_S		= 6'h02;     	parameter [3:0] LRN_RD_PARM_S	= 4'h2;
	parameter [5:0] RCL_ACC_BIAS_S		= 6'h04; 		parameter [3:0] LRN_WEIGHT_S	= 4'h4;
	parameter [5:0] RCL_ACC_MEMB_POT_S	= 6'h08;		parameter [3:0] LRN_BIAS_S		= 4'h8;
	parameter [5:0] RCL_THRESHOLD_S	 	= 6'h10;
	parameter [5:0] RCL_WR_BACK_S	 	= 6'h20;

	//SELECT LINE ENCODING
	//--------------------------------------------------//
	//recall adder select lines
	parameter [1:0] RCL_ADD_B_WT       = 2'b00;
	parameter [1:0] RCL_ADD_B_BIAS     = 2'b01;
	parameter [1:0] RCL_ADD_B_MEMB_POT = 2'b10;
	parameter [1:0] RCL_ADD_B_NEG_TH   = 2'b11;

	//status port B writeback select lines
	parameter [1:0] WR_BACK_STAT_B_BIAS      = 2'b00;
	parameter [1:0] WR_BACK_STAT_B_MEMB_POT  = 2'b01;
	parameter [1:0] WR_BACK_STAT_B_TH        = 2'b10;
	parameter [1:0] WR_BACK_STAT_B_POST_HIST = 2'b11;

	//--------------------------------------------------//

	//WIRE DECLARATIONS
	//--------------------------------------------------//
	wire rclCntr_Nurn_done, rclCntr_Axon_done, lrnCntr_Axon_done, PStgEn_rdWt, PStgEn_rdBias;

	//REGISTER DECLARATION
	//--------------------------------------------------//
	reg [5:0] Rcl_CurrState, Rcl_NextState;
	reg [3:0] Lrn_CurrState, Lrn_NextState;
	reg [NURN_CNT_BIT_WIDTH-1:0] rclCntr_Nurn;
	reg [AXON_CNT_BIT_WIDTH-1:0] rclCntr_Axon, lrnCntr_Axon;
	reg rclCntr_Nurn_rst, rclCntr_Axon_rst, lrnCntr_Axon_rst;
	reg rclCntr_Nurn_inc, rclCntr_Axon_inc, lrnCntr_Axon_inc;
	reg accEn, StatRd_A_bias, StatRd_A_MembPot, StatRd_A_Th, cmp_th, wr_th, wr_MembPot;
	reg rstAcc, rstAcc_1_dly, lrn_en, rdPostSpkHist, wrPostSpkHist;
	reg enLrnWtPipln, enLrnBiasPipln, init_WrBackAddr, inc_wrBackAddr, cmpSTDP_win/* synthesis preserve */;

	reg rstAcc_dly, enLrnWtPipln_dly, PStgEn_lrnRt, PStgEn_quant, PStgEn_shift, PStgEn_deltaW;
	reg PStgEn_wrBack,cmpSTDP_win_dly;
	reg [1:0] wrEn_th_dly, wr_MembPot_dly;
	reg [5:0] inc_wrBackAddr_Pipln, LrnBias_Pipln;
	reg [3:0] init_WrBackAddr_Pipln;
	reg [1:0] sel_rclAdd_B;

	reg [NURN_CNT_BIT_WIDTH-1:0] rclNurnAddr_buff, lrnWrBack_Nurn;
	reg [AXON_CNT_BIT_WIDTH-1:0] lrnCntr_Axon_Pipln, lrnWrBackCntr_Axon;


	//LOGIC
	//--------------------------------------------------//

	//--------------------------------------------------//
	//----------------- state machine ------------------//

	//state registers
	always @ (posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			Rcl_CurrState <= RCL_IDLE_S;
			Lrn_CurrState <= LRN_IDLE_S;
		end else if (clk_i == 1'b1) begin
			Rcl_CurrState <= Rcl_NextState;
			Lrn_CurrState <= Lrn_NextState;
		end
	end
	//--------------------------------------------------//

	//Recall next state logic and combinational output
	always @(*) begin
		rclCntr_Nurn_rst 	= 1'b0;
		rclCntr_Axon_rst 	= 1'b0;
		rstAcc 				= 1'b0;
		rclCntr_Axon_inc 	= 1'b0;
		rdEn_StatRd_E_o 	= 1'b0;
		accEn 				= 1'b0;
		StatRd_A_bias 		= 1'b0;
		StatRd_A_MembPot	= 1'b0;
		StatRd_A_Th 		= 1'b0;
		cmp_th 		 		= 1'b0;
		rdEn_Config_B_o     = 1'b0;
		wr_th 				= 1'b0;
		wr_MembPot			= 1'b0;
		rstAcc_1_dly		= 1'b0;
		rclCntr_Nurn_inc	= 1'b0;
		lrn_en 				= 1'b0;
		buffBias_o			= 1'b0;
		sel_rclAdd_B		= RCL_ADD_B_WT;

		case (Rcl_CurrState)
			RCL_IDLE_S: begin
				if (start_i == 1'b1) begin
					rclCntr_Nurn_rst = 1'b1;
					rclCntr_Axon_rst = 1'b1;
					rstAcc = 1'b1;

					Rcl_NextState = RCL_ACC_WT_S;
				end else begin
					Rcl_NextState = RCL_IDLE_S;
				end
			end

			RCL_ACC_WT_S: begin
				rclCntr_Axon_inc = 1'b1;	
				rdEn_StatRd_E_o = 1'b1;
				accEn = 1'b1;
				sel_rclAdd_B = RCL_ADD_B_WT;

				if (rclCntr_Axon_done == 1'b1) begin
					Rcl_NextState = RCL_ACC_BIAS_S;
				end else begin
					Rcl_NextState = RCL_ACC_WT_S;
				end
			end

			RCL_ACC_BIAS_S: begin
				StatRd_A_bias = 1'b1;
				accEn = 1'b1;
				sel_rclAdd_B = RCL_ADD_B_BIAS;

				Rcl_NextState = RCL_ACC_MEMB_POT_S;
			end

			RCL_ACC_MEMB_POT_S: begin
				StatRd_A_MembPot = 1'b1;
				buffBias_o = 1'b1;//will be used while learning
				accEn = 1'b1;
				sel_rclAdd_B = RCL_ADD_B_MEMB_POT;
				rdEn_Config_B_o = 1'b1;
				
				Rcl_NextState = RCL_THRESHOLD_S;
			end

			RCL_THRESHOLD_S: begin
				StatRd_A_Th = 1'b1;
				cmp_th = 1'b1;
				wr_MembPot = 1'b1;

				if (NurnType_i == 1'b1) begin//ReLU
					accEn = 1'b1;
					sel_rclAdd_B = RCL_ADD_B_NEG_TH;
				end				

				Rcl_NextState = RCL_WR_BACK_S;
			end

			RCL_WR_BACK_S: begin
				wr_th = 1'b1;
				lrn_en = 1'b1;

				if (rclCntr_Nurn_done == 1'b1) begin
					Rcl_NextState = RCL_IDLE_S; //will take few more clocks to process pipelined signals
				end	else begin
					rclCntr_Nurn_inc = 1'b1;
					rclCntr_Axon_rst = 1'b1;
					rstAcc_1_dly = 1'b1;

					Rcl_NextState = RCL_ACC_WT_S;
				end			
			end

			default: begin
				Rcl_NextState = RCL_IDLE_S;
			end
		endcase
	end
	//--------------------------------------------------//

	//Learn next state logic and combinational output
	always @(*) begin
		lrnCntr_Axon_rst = 1'b0;
		rdEn_Config_A_o = 1'b0;
		rdPostSpkHist = 1'b0;
		lrnCntr_Axon_inc = 1'b0;
		enLrnWtPipln = 1'b0;
		enLrnBiasPipln = 1'b0;
		init_WrBackAddr = 1'b0;
		inc_wrBackAddr = 1'b0;
		cmpSTDP_win = 1'b0;

		case (Lrn_CurrState)
			LRN_IDLE_S: begin
				if (lrn_en == 1'b1) begin
					lrnCntr_Axon_rst = 1'b1;

					Lrn_NextState = LRN_RD_PARM_S;
				end else begin
					Lrn_NextState = LRN_IDLE_S;
				end
			end

			LRN_RD_PARM_S: begin
				rdEn_Config_A_o = 1'b1;
				rdPostSpkHist = 1'b1;
				init_WrBackAddr = 1'b1;

				Lrn_NextState = LRN_WEIGHT_S;
			end

			LRN_WEIGHT_S: begin
				lrnCntr_Axon_inc = 1'b1;
				enLrnWtPipln = 1'b1;
				inc_wrBackAddr = 1'b1;
				cmpSTDP_win = 1'b1;
				
				if (lrnCntr_Axon_done == 1'b1) begin
					Lrn_NextState = LRN_BIAS_S;
				end else begin
					Lrn_NextState = LRN_WEIGHT_S;
				end
			end

			LRN_BIAS_S: begin
				if (biasLrnMode_i == 1'b1) begin
					enLrnBiasPipln = 1'b1;
				end

				Lrn_NextState = LRN_IDLE_S;
			end

			default: begin
				Lrn_NextState = LRN_IDLE_S;
			end
		endcase
	end
	//--------------------------------------------------//
	//--------------------------------------------------//

	//counters
	//--------------------------------------------------//
	always @(posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			rclCntr_Nurn <= 0;
			rclCntr_Axon <= 0;
			lrnCntr_Axon <= 0;
			rclNurnAddr_buff <= 0;
			lrnWrBack_Nurn <= 0;
			lrnWrBackCntr_Axon <= 0;
		end else begin
			if (rclCntr_Nurn_rst == 1'b1) begin
				rclCntr_Nurn <= 0;	
			end else if ((rclCntr_Nurn_done == 1'b0) && (rclCntr_Nurn_inc == 1'b1)) begin
				rclCntr_Nurn <= rclCntr_Nurn + 1;
			end

			if (rclCntr_Axon_rst == 1'b1) begin
				rclCntr_Axon <= 0;	
			end else if ((rclCntr_Axon_done == 1'b0) && (rclCntr_Axon_inc == 1'b1)) begin
				rclCntr_Axon <= rclCntr_Axon + 1;
			end

			if (lrnCntr_Axon_rst == 1'b1) begin
				lrnCntr_Axon <= 0;	
			end else if ((lrnCntr_Axon_done == 1'b0) && (lrnCntr_Axon_inc == 1'b1)) begin
				lrnCntr_Axon <= lrnCntr_Axon + 1;
			end

			if (wr_MembPot == 1'b1) begin
				rclNurnAddr_buff <= rclCntr_Nurn;
			end

			if (init_WrBackAddr_Pipln[0] == 1'b1) begin
				lrnWrBack_Nurn <= rclNurnAddr_buff;
				lrnWrBackCntr_Axon <= 0;
			end else if (inc_wrBackAddr_Pipln[0] == 1'b1) begin
				lrnWrBackCntr_Axon <= lrnWrBackCntr_Axon + 1;
			end

		end
	end
	assign rclCntr_Nurn_done = (rclCntr_Nurn == NUM_NURNS-1) ? 1'b1 : 1'b0;
	assign rclCntr_Axon_done = (rclCntr_Axon == NUM_AXONS-1) ? 1'b1 : 1'b0;
	assign lrnCntr_Axon_done = (lrnCntr_Axon == NUM_AXONS-1) ? 1'b1 : 1'b0;

	//Address generation
	//--------------------------------------------------//
	always @(*) begin
		//status read port A
		rdEn_StatRd_A_o = 1'b0;
		Addr_StatRd_A_o = {rclCntr_Nurn,2'b00};
		if (StatRd_A_bias == 1'b1) begin
			rdEn_StatRd_A_o = 1'b1;
			Addr_StatRd_A_o = {rclCntr_Nurn,2'b00};
		end else if (StatRd_A_MembPot == 1'b1) begin
			rdEn_StatRd_A_o = 1'b1;
			Addr_StatRd_A_o = {rclCntr_Nurn,2'b01};
		end else if (StatRd_A_Th == 1'b1) begin
			rdEn_StatRd_A_o = 1'b1;
			Addr_StatRd_A_o = {rclCntr_Nurn,2'b10};
		end else if (rdPostSpkHist == 1'b1) begin
			rdEn_StatRd_A_o = 1'b1;
			Addr_StatRd_A_o = {rclNurnAddr_buff,2'b11};
		end

		//status write port B
		Addr_StatWr_B_o = {rclNurnAddr_buff,2'b00};
		if (LrnBias_Pipln[0] == 1'b1) begin
			Addr_StatWr_B_o = {lrnWrBack_Nurn,2'b00};
		end else if (wr_MembPot_dly[0] == 1'b1) begin
			Addr_StatWr_B_o = {rclNurnAddr_buff,2'b01};
		end else if (wrEn_th_dly[0] == 1'b1) begin
			Addr_StatWr_B_o = {rclNurnAddr_buff,2'b10};
		end else if (wrPostSpkHist == 1'b1) begin
			Addr_StatWr_B_o = {rclNurnAddr_buff,2'b11};
		end
	end
	assign Addr_Config_B_o = rclCntr_Nurn;
	assign Addr_Config_A_o = rclNurnAddr_buff;
	assign Addr_StatRd_E_o = {rclCntr_Nurn,rclCntr_Axon};
	assign Addr_StatRd_C_o = {rclNurnAddr_buff,lrnCntr_Axon};
	assign Addr_Config_C_o = {rclNurnAddr_buff,lrnCntr_Axon};
	assign Addr_StatRd_F_o = {rclNurnAddr_buff,lrnCntr_Axon_Pipln};
	assign Addr_StatWr_D_o = {lrnWrBack_Nurn,lrnWrBackCntr_Axon};
	assign Addr_StatWr_G_o = {lrnWrBack_Nurn,lrnWrBackCntr_Axon};


	//pipelined and registered control signals
	//--------------------------------------------------//
	always @(posedge clk_i or negedge rst_n_i) begin
		if (rst_n_i == 1'b0) begin
			accEn_o <= 1'b0;
			cmp_th_o <= 1'b0;
			rstAcc_dly <= 1'b0;
			sel_rclAdd_B_o <= RCL_ADD_B_WT;
			wr_MembPot_dly <= 2'b0;
			wrEn_th_dly <= 2'b0;
			updtPostSpkHist_o <= 1'b0;
			wrPostSpkHist <= 1'b0;
			cmpSTDP_win_dly <= 1'b0;

			//learn pipeline
			lrnCntr_Axon_Pipln <= 0;
			enLrnWtPipln_dly <= 0;
			PStgEn_lrnRt <= 0;
			PStgEn_quant <= 0;
			PStgEn_shift <= 0;
			PStgEn_deltaW <= 0;
			PStgEn_wrBack <= 0;
			inc_wrBackAddr_Pipln <= 6'b0;
			init_WrBackAddr_Pipln <= 4'b0;
			LrnBias_Pipln <= 6'b0;
			//------------------------
		end else begin
			accEn_o <= accEn;
			cmp_th_o <= cmp_th;
			rstAcc_dly <= rstAcc_1_dly;
			sel_rclAdd_B_o <= sel_rclAdd_B;
			updtPostSpkHist_o <= rdPostSpkHist;
			wrPostSpkHist <= updtPostSpkHist_o;
			cmpSTDP_win_dly <= cmpSTDP_win;

			wr_MembPot_dly <= {wr_MembPot,wr_MembPot_dly[1]};
			wrEn_th_dly <= {wr_th,wrEn_th_dly[1]};
			

			//learn pipeline
			lrnCntr_Axon_Pipln <= lrnCntr_Axon;
			//LRN_WEIGHT_S: enLrnWtPipln <= 1
			enLrnWtPipln_dly <= enLrnWtPipln;
			//PStgEn_rdWt = axonLrnMode_i & enLrnWtPipln_dly;
			PStgEn_lrnRt <= PStgEn_rdWt | PStgEn_rdBias;
			PStgEn_quant <= PStgEn_lrnRt;
			PStgEn_shift <= PStgEn_quant;
			PStgEn_deltaW <= PStgEn_shift;
			PStgEn_wrBack <= PStgEn_deltaW;
			//LRN_WEIGHT_S: inc_wrBackAddr = 1'b1;
			inc_wrBackAddr_Pipln <= {inc_wrBackAddr,inc_wrBackAddr_Pipln[5:1]};
			//wrEn_StatWr_G_o = PStgEn_wrBack & inc_wrBackAddr_Pipln[0];
			init_WrBackAddr_Pipln <= {init_WrBackAddr,init_WrBackAddr_Pipln[3:1]};
			LrnBias_Pipln <= {enLrnBiasPipln,LrnBias_Pipln[5:1]};
			//------------------------
		end
	end
	assign rstAcc_o = rstAcc_dly | rstAcc;
	assign wrEn_StatWr_B_o = wr_MembPot_dly[0] | wrEn_th_dly[0] | wrPostSpkHist | LrnBias_Pipln[0];
	assign buffMembPot_o = wr_MembPot_dly[1];
	assign cmpSTDP_o = cmpSTDP_win_dly;
	
	//learn pipeline
	assign rdEn_StatRd_C_o = enLrnWtPipln;
	assign rdEn_Config_C_o = enLrnWtPipln;
	assign PStgEn_rdWt = axonLrnMode_i & enLrnWtPipln_dly;
	assign rdEn_StatRd_F_o = PStgEn_rdWt;
	assign addLrnRt_o = PStgEn_lrnRt;
	assign enQuant_o = PStgEn_quant;
	assign enShift_o = PStgEn_shift;
	assign enDeltaW_o = PStgEn_deltaW;
	assign wrEn_StatWr_D_o = PStgEn_wrBack & inc_wrBackAddr_Pipln[0];
	//weight memory writing enable signal
	assign wrEn_StatWr_G_o = PStgEn_wrBack & inc_wrBackAddr_Pipln[0];
	assign PStgEn_rdBias = LrnBias_Pipln[5];
	assign lrnUseBias_o = PStgEn_rdBias;
	//------------------------

	//write back select line
	always @(*) begin
		sel_wrBackStat_B_o = WR_BACK_STAT_B_BIAS;
		if (wr_MembPot_dly[0] == 1'b1) begin
			sel_wrBackStat_B_o = WR_BACK_STAT_B_MEMB_POT;
		end else if (wrEn_th_dly[0] == 1'b1) begin
			sel_wrBackStat_B_o = WR_BACK_STAT_B_TH;
		end else if (wrPostSpkHist == 1'b1) begin
			sel_wrBackStat_B_o = WR_BACK_STAT_B_POST_HIST;
		end else if (LrnBias_Pipln[0] == 1'b1) begin
			sel_wrBackStat_B_o = WR_BACK_STAT_B_BIAS;
		end

	end

endmodule
