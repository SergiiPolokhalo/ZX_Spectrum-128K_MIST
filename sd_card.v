// 
// sd_card.v
//
// This file implelents a sd card for the MIST board since on the board
// the SD card is connected to the ARM IO controller and the FPGA has no
// direct connection to the SD card. This file provides a SD card like
// interface to the IO controller easing porting of cores that expect
// a direct interface to the SD card.
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// http://elm-chan.org/docs/mmc/mmc_e.html
//
/////////////////////////////////////////////////////////////////////////

//
// Made module syncrhroneous. Total code refactoring. (Sorgelig)
//

module sd_card
(
	// Global clock. It should be around 100MHz (higher is better).
	input         clk_sys,

	// config
	input         allow_sdhc,
	output reg    sd_conf_req = 1,
	input   [7:0] sd_conf,
	output		  sd_sdhc,

	// block level
	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input			  sd_ack,
	input			  sd_ack_conf,

	// byte level
	output  [9:0] sd_addr,  // 512b data + 16b cid + 16b csd + 1b conf
	input	  [7:0] sd_dout,
	output  [7:0] sd_din,
	output reg    sd_din_wr,

	// SPI interface
	input         spi_clk,
	input         spi_ss,
	input         spi_di,
	output reg    spi_do
);

assign     sd_lba  = sd_sdhc ? lba : {9'd0, lba[31:9]};
assign     sd_sdhc = allow_sdhc && sd_conf[0];
assign     sd_addr = buffer_ptr;
assign     sd_din  = buffer_dout;

wire[31:0] OCR = { 1'b1, sd_sdhc, 30'h0 };  // bit30 = 1 -> high capaciry card (sdhc) // bit31 = 0 -> card power up finished
wire [7:0] READ_DATA_TOKEN = 8'hfe;
wire [7:0] WRITE_DATA_RESPONSE = 8'h05;

// number of bytes to wait after a command before sending the reply
localparam NCR=3;

localparam RD_STATE_IDLE       = 2'd0;
localparam RD_STATE_WAIT_IO    = 2'd1;
localparam RD_STATE_SEND_TOKEN = 2'd2;
localparam RD_STATE_SEND_DATA  = 2'd3;

localparam WR_STATE_IDLE       = 3'd0;
localparam WR_STATE_EXP_DTOKEN = 3'd1;
localparam WR_STATE_RECV_DATA  = 3'd2;
localparam WR_STATE_RECV_CRC0  = 3'd3;
localparam WR_STATE_RECV_CRC1  = 3'd4;
localparam WR_STATE_SEND_DRESP = 3'd5;
localparam WR_STATE_BUSY       = 3'd6;

reg [31:0] lba;
reg  [9:0] buffer_ptr;
reg  [7:0] buffer_dout;

always @(posedge clk_sys) begin
	reg [1:0] read_state;
	reg [2:0] write_state;
	reg [6:0] sbuf;
	reg       cmd55;
	reg [7:0] cmd;
	reg [2:0] bit_cnt;    // counts bits 0-7 0-7 ...
	reg [3:0] byte_cnt;   // counts bytes
	reg [7:0] reply;
	reg [7:0] reply0, reply1, reply2, reply3;
	reg [3:0] reply_len;
	reg       tx_finish;
	reg       rx_finish;
	reg       old_sck;
	reg       synced;
	reg [5:0] ack;
	reg       io_ack;
	reg [2:0] write_prc;

	if(write_prc) begin
		write_prc <= write_prc + 1'b1;
		if((write_prc < 3) & (buffer_ptr < 512)) sd_din_wr <= 1;
		else if(write_prc < 5) sd_din_wr <= 0;
		else begin
			buffer_ptr <= buffer_ptr + 1'b1;
			write_prc <= 0;
		end
	end else sd_din_wr <= 0;

	ack <= {ack[4:0], sd_ack};
	if(ack[5:4] == 2'b10) io_ack <= 1;
	if(ack[5:4] == 2'b01) {sd_rd,sd_wr} <= 0;
	if(sd_ack_conf) sd_conf_req <= 0;

	// cs is active low
	if(spi_ss) begin
		bit_cnt  <= 0;
		byte_cnt <= 15;
		synced   <= 0;
		spi_do   <= 1;
		sbuf     <= 7'b1111111;
		tx_finish<= 0;
		rx_finish<= 0;
		read_state  <= RD_STATE_IDLE;
		write_state <= WR_STATE_IDLE;
	end

	old_sck <= spi_clk;
	if(old_sck & ~spi_clk & ~spi_ss) begin
		tx_finish <= 0;
		spi_do <= 1;				// default: send 1's (busy/wait)

		if(byte_cnt == 5+NCR) begin
			spi_do <= reply[~bit_cnt];

			if(bit_cnt == 7) begin
				// these three commands all have a reply_len of 0 and will thus
				// not send more than a single reply byte

				// CMD9: SEND_CSD
				// CMD10: SEND_CID
				if((cmd == 'h49) | (cmd ==  'h4a))
					read_state <= RD_STATE_SEND_TOKEN;      // jump directly to data transmission
						
				// CMD17: READ_SINGLE_BLOCK
				if(cmd == 'h51) begin
					io_ack <= 0;
					read_state <= RD_STATE_WAIT_IO;         // start waiting for data from io controller
					sd_rd <= 1;                      // trigger request to io controller
				end
			end
		end
		else if((reply_len > 0) && (byte_cnt == 5+NCR+1)) spi_do <= reply0[~bit_cnt];
		else if((reply_len > 1) && (byte_cnt == 5+NCR+2)) spi_do <= reply1[~bit_cnt];
		else if((reply_len > 2) && (byte_cnt == 5+NCR+3)) spi_do <= reply2[~bit_cnt];
		else if((reply_len > 3) && (byte_cnt == 5+NCR+4)) spi_do <= reply3[~bit_cnt];
		else begin
			if(byte_cnt > 5+NCR && read_state==RD_STATE_IDLE && write_state==WR_STATE_IDLE) tx_finish <= 1;
			spi_do <= 1;
		end

		// ---------- read state machine processing -------------

		case(read_state)
			RD_STATE_IDLE: ; // do nothing


			// waiting for io controller to return data
			RD_STATE_WAIT_IO: begin
				if(io_ack & (bit_cnt == 7)) read_state <= RD_STATE_SEND_TOKEN;
			end

			// send data token
			RD_STATE_SEND_TOKEN: begin
				spi_do <= READ_DATA_TOKEN[~bit_cnt];
	
				if(bit_cnt == 7) begin
					read_state <= RD_STATE_SEND_DATA;   // next: send data
					buffer_ptr <= 0;
					if(cmd == 'h49) buffer_ptr <= 528;
					if(cmd == 'h4A) buffer_ptr <= 512;
				end
			end

			// send data
			RD_STATE_SEND_DATA: begin

				spi_do <= sd_dout[~bit_cnt];

				if(bit_cnt == 7) begin
					// sent 512 sector data bytes?
					if((cmd == 'h51) & (&buffer_ptr[8:0])) read_state <= RD_STATE_IDLE;

					// sent 16 cid/csd data bytes?
					else if(((cmd == 'h49) | (cmd == 'h4a)) & (&buffer_ptr[3:0])) read_state <= RD_STATE_IDLE;

					else buffer_ptr <= buffer_ptr + 1'd1;    // not done yet -> trigger read of next data byte
				end
			end
		endcase

		// ------------------ write support ----------------------
		// send write data response
		if(write_state == WR_STATE_SEND_DRESP) spi_do <= WRITE_DATA_RESPONSE[~bit_cnt];

		// busy after write until the io controller sends ack
		if(write_state == WR_STATE_BUSY) spi_do <= 0;
   end

	if(~old_sck & spi_clk & ~spi_ss) begin

	   if(synced) bit_cnt <= bit_cnt + 1'd1;

		if((bit_cnt != 7) && (write_state==WR_STATE_EXP_DTOKEN) && ({ sbuf, spi_di} == 8'hfe )) begin
			write_state <= WR_STATE_RECV_DATA;
			bit_cnt <= 0; // atchoum
		end
		// assemble byte
		else if(bit_cnt != 7) sbuf[6:0] <= { sbuf[5:0], spi_di };
		else begin
			// finished reading one byte
			// byte counter runs against 15 byte boundary
			if(byte_cnt != 15) byte_cnt <= byte_cnt + 1'd1;

			// byte_cnt > 6 -> complete command received
			// first byte of valid command is 01xxxxxx
			// don't accept new commands once a write or read command has been accepted
 			if((byte_cnt > 5) & (write_state == WR_STATE_IDLE) & (read_state == RD_STATE_IDLE) && !rx_finish) begin
				byte_cnt <= 0;
				cmd <= { sbuf, spi_di};

			   // set cmd55 flag if previous command was 55
			   cmd55 <= (cmd == 'h77);
			end

			// parse additional command bytes
			if(byte_cnt == 0) lba[31:24] <= { sbuf, spi_di};
			if(byte_cnt == 1) lba[23:16] <= { sbuf, spi_di};
			if(byte_cnt == 2) lba[15:8]  <= { sbuf, spi_di};
			if(byte_cnt == 3) lba[7:0]   <= { sbuf, spi_di};

			// last byte (crc) received, evaluate
			if(byte_cnt == 4) begin

				// default:
				reply <= 4;      // illegal command
				reply_len <= 0;  // no extra reply bytes
				rx_finish <= 1;

				case(cmd)
					// CMD0: GO_IDLE_STATE
					'h40: reply <= 1;    // ok, busy

					// CMD1: SEND_OP_COND
					'h41: reply <= 0;    // ok, not busy

					// CMD8: SEND_IF_COND (V2 only)
					'h48: begin
							reply  <= 1;   // ok, busy

							reply0 <= 'h00;
							reply1 <= 'h00;
							reply2 <= 'h01;
							reply3 <= 'hAA;
							reply_len <= 4;
						end

					// CMD9: SEND_CSD
					'h49: reply <= 0;    // ok

					// CMD10: SEND_CID
					'h4a: reply <= 0;    // ok

					// CMD16: SET_BLOCKLEN
					'h50: begin
							// we only support a block size of 512
							if(sd_lba == 512) reply <= 0;  // ok
								else reply <= 'h40;         // parmeter error
						end

					// CMD17: READ_SINGLE_BLOCK
					'h51: reply <= 0;    // ok

					// CMD24: WRITE_BLOCK
					'h58: begin
							reply <= 0;    // ok
							write_state <= WR_STATE_EXP_DTOKEN;  // expect data token
							rx_finish <=0;
							buffer_ptr <= 0;
						end

					// ACMD41: APP_SEND_OP_COND
					'h69: if(cmd55) reply <= 0;    // ok, not busy

					// CMD55: APP_COND
					'h77: reply <= 1;    // ok, busy

					// CMD58: READ_OCR
					'h7a: begin
							reply <= 0;    // ok

							reply0 <= OCR[31:24];   // bit 30 = 1 -> high capacity card
							reply1 <= OCR[23:16];
							reply2 <= OCR[15:8];
							reply3 <= OCR[7:0];
							reply_len <= 4;
						end

					// CMD59: CRC_ON_OFF
					'h7b: reply <= 0;    // ok
				endcase
			end

				// ---------- handle write -----------
			case(write_state)
				// do nothing in idle state
				WR_STATE_IDLE: ;

				// waiting for data token
				WR_STATE_EXP_DTOKEN:
					if({ sbuf, spi_di} == 8'hfe ) write_state <= WR_STATE_RECV_DATA;

				// transfer 512 bytes
				WR_STATE_RECV_DATA: begin
					// push one byte into local buffer
					write_prc  <= 1;
					buffer_dout <= {sbuf, spi_di};

					// all bytes written?
					if(buffer_ptr == 511) write_state <= WR_STATE_RECV_CRC0;
				end

				// transfer 1st crc byte
				WR_STATE_RECV_CRC0:
					write_state <= WR_STATE_RECV_CRC1;

				// transfer 2nd crc byte
				WR_STATE_RECV_CRC1:
					write_state <= WR_STATE_SEND_DRESP;

				// send data response
				WR_STATE_SEND_DRESP: begin
					write_state <= WR_STATE_BUSY;
					io_ack <= 0;
					sd_wr <= 1;               // trigger write request to io ontroller
				end

				// wait for io controller to accept data
				WR_STATE_BUSY:
					if(io_ack) begin
						write_state <= WR_STATE_IDLE;
						rx_finish <= 1;
					end
			endcase
		end
		
		// wait for first 0 bit until start counting bits
		if(!synced && !spi_di) begin
			synced   <= 1;
			bit_cnt  <= 1; // byte assembly prepare for next time loop
			sbuf     <= 7'b1111110; // byte assembly prepare for next time loop
			rx_finish<= 0;
		end else if (synced && tx_finish && rx_finish ) begin
			synced   <= 0;
			bit_cnt  <= 0;
			rx_finish<= 0;
		end
	end
end

endmodule
