// ZX Spectrum for Altera DE1
//
// Copyright (c) 2009-2011 Mike Stirling
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

// PS/2 scancode to Spectrum matrix conversion
module keyboard(
   input        CLK,
   input        nRESET,
   
   // PS/2 interface
   input        PS2_CLK,
   input        PS2_DAT,
   
   // CPU address bus (row)
   input [15:0] A,
   // Column outputs to ULA
   output [4:0] KEYB,
   
   output reg   F11 = 1'b0,
   output reg   F1  = 1'b0
);
   
   // Interface to PS/2 block
   wire [7:0]   keyb_data;
   wire         keyb_valid;
  
   // Internal signals
   reg [4:0]    keys[7:0];
   reg          release_btn;
   
   // PS/2 interface
   ps2_intf ps2(
      CLK,
      nRESET,
		
		// PS/2 interface (could be bi-dir)
      PS2_CLK,
      PS2_DAT,

		// Byte-wide data interface - only valid for one clock
		// so must be latched externally if required
      keyb_data,
      keyb_valid
   );
   
   // Output addressed row to ULA
   assign KEYB = (A[8]  == 1'b0) ? keys[0] : 
                 (A[9]  == 1'b0) ? keys[1] : 
                 (A[10] == 1'b0) ? keys[2] : 
                 (A[11] == 1'b0) ? keys[3] : 
                 (A[12] == 1'b0) ? keys[4] : 
                 (A[13] == 1'b0) ? keys[5] : 
                 (A[14] == 1'b0) ? keys[6] : 
                 (A[15] == 1'b0) ? keys[7] : 
                                   5'b11111;

   always @(negedge nRESET or posedge CLK) begin
      if(!nRESET)begin
         release_btn <= 1'b0;
         
         keys[0] <= 5'b11111;
         keys[1] <= 5'b11111;
         keys[2] <= 5'b11111;
         keys[3] <= 5'b11111;
         keys[4] <= 5'b11111;
         keys[5] <= 5'b11111;
         keys[6] <= 5'b11111;
         keys[7] <= 5'b11111;
         F11     <= 1'b0;
         F1      <= 1'b0;
      end else begin
         if (keyb_valid) begin
            if (keyb_data == 8'he0)
               ;
            // Extended key code follows
            else if (keyb_data == 8'hf0)
               // Release code follows
               release_btn <= 1'b1;
            else begin
               // Cancel extended/release flags for next time
               release_btn <= 1'b0;

               case (keyb_data)
                  8'h12 : keys[0][0] <= release_btn; // Left shift (CAPS SHIFT)
                  8'h59 : keys[0][0] <= release_btn; // Right shift (CAPS SHIFT)
                  8'h1a : keys[0][1] <= release_btn; // Z
                  8'h22 : keys[0][2] <= release_btn; // X
                  8'h21 : keys[0][3] <= release_btn; // C
                  8'h2a : keys[0][4] <= release_btn; // V

                  8'h1c : keys[1][0] <= release_btn; // A
                  8'h1b : keys[1][1] <= release_btn; // S
                  8'h23 : keys[1][2] <= release_btn; // D
                  8'h2b : keys[1][3] <= release_btn; // F
                  8'h34 : keys[1][4] <= release_btn; // G

                  8'h15 : keys[2][0] <= release_btn; // Q
                  8'h1d : keys[2][1] <= release_btn; // W
                  8'h24 : keys[2][2] <= release_btn; // E
                  8'h2d : keys[2][3] <= release_btn; // R
                  8'h2c : keys[2][4] <= release_btn; // T

                  8'h16 : keys[3][0] <= release_btn; // 1
                  8'h1e : keys[3][1] <= release_btn; // 2
                  8'h26 : keys[3][2] <= release_btn; // 3
                  8'h25 : keys[3][3] <= release_btn; // 4
                  8'h2e : keys[3][4] <= release_btn; // 5

                  8'h45 : keys[4][0] <= release_btn; // 0
                  8'h46 : keys[4][1] <= release_btn; // 9
                  8'h3e : keys[4][2] <= release_btn; // 8
                  8'h3d : keys[4][3] <= release_btn; // 7
                  8'h36 : keys[4][4] <= release_btn; // 6

                  8'h4d : keys[5][0] <= release_btn; // P
                  8'h44 : keys[5][1] <= release_btn; // O
                  8'h43 : keys[5][2] <= release_btn; // I
                  8'h3c : keys[5][3] <= release_btn; // U
                  8'h35 : keys[5][4] <= release_btn; // Y

                  8'h5a : keys[6][0] <= release_btn; // ENTER
                  8'h4b : keys[6][1] <= release_btn; // L
                  8'h42 : keys[6][2] <= release_btn; // K
                  8'h3b : keys[6][3] <= release_btn; // J
                  8'h33 : keys[6][4] <= release_btn; // H

                  8'h29 : keys[7][0] <= release_btn; // SPACE
                  8'h14 : keys[7][1] <= release_btn; // CTRL (Symbol Shift)
                  8'h3a : keys[7][2] <= release_btn; // M
                  8'h31 : keys[7][3] <= release_btn; // N
                  8'h32 : keys[7][4] <= release_btn; // B

                  // Cursor keys - these are actually extended (E0 xx), but
                  // the scancodes for the numeric keypad cursor keys are
                  // are the same but without the extension, so we'll accept
                  // the codes whether they are extended or not
                  8'h6B : begin // Left (CAPS 5)
									keys[0][0] <= release_btn;
									keys[3][4] <= release_btn;
								end
                  8'h72 : begin // Down (CAPS 6)
									keys[0][0] <= release_btn;
									keys[4][4] <= release_btn;
								end
                  8'h75 : begin // Up (CAPS 7)
									keys[0][0] <= release_btn;
									keys[4][3] <= release_btn;
								end
                  8'h74 : begin // Right (CAPS 8)
									keys[0][0] <= release_btn;
									keys[4][2] <= release_btn;
								end

                  // Other special keys sent to the ULA as key combinations
                  8'h66 : begin // Backspace (CAPS 0)
									keys[0][0] <= release_btn;
									keys[4][0] <= release_btn;
								end
                  8'h58 : begin // Caps lock (CAPS 2)
									keys[0][0] <= release_btn;
									keys[3][1] <= release_btn;
								end
                  8'h76 : begin // Escape (CAPS SPACE)
									keys[0][0] <= release_btn;
									keys[7][0] <= release_btn;
								end

                  8'h78 : F11 <= !release_btn; // F11 key
                  8'h05 : F1  <= !release_btn; // F1 key
						default: 
								;
               endcase
            end
         end 
      end 
   end
endmodule
