/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  Copyright (C) 2012  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *  SOFTWARE.
 *
 *  赛题二优化（路线 D）：宽位宽 $alu 采用行波进位（ripple-carry）结构，
 *  替代通用 techmap.v 的 Brent-Kung 前缀树；窄位宽保持失败回退到通用实现，
 *  避免小位宽反增。语义与 $alu 完全等价（CI/BI/X/CO 契约同 _90_alu）。
 */

(* techmap_celltype = "$alu" *)
module _80_cycloneiv_alu (A, B, CI, BI, X, Y, CO);
	parameter A_SIGNED = 0;
	parameter B_SIGNED = 0;
	parameter A_WIDTH = 1;
	parameter B_WIDTH = 1;
	parameter Y_WIDTH = 1;

	(* force_downto *)
	input [A_WIDTH-1:0] A;
	(* force_downto *)
	input [B_WIDTH-1:0] B;
	(* force_downto *)
	output [Y_WIDTH-1:0] X, Y;

	input CI, BI;
	(* force_downto *)
	output [Y_WIDTH-1:0] CO;

	// 窄位宽回退通用 techmap.v（Brent-Kung）：实测 w=1..5 ripple 不占优，w=5 曾反增 +3。
	// 仅宽位宽（w>=6）ripple-carry 稳定占优。
	wire _TECHMAP_FAIL_ = Y_WIDTH < 6;

	(* force_downto *)
	wire [Y_WIDTH-1:0] A_buf, B_buf;
	\$pos #(.A_SIGNED(A_SIGNED), .A_WIDTH(A_WIDTH), .Y_WIDTH(Y_WIDTH)) A_conv (.A(A), .Y(A_buf));
	\$pos #(.A_SIGNED(B_SIGNED), .A_WIDTH(B_WIDTH), .Y_WIDTH(Y_WIDTH)) B_conv (.A(B), .Y(B_buf));

	(* force_downto *)
	wire [Y_WIDTH-1:0] AA = A_buf;
	(* force_downto *)
	wire [Y_WIDTH-1:0] BB = BI ? ~B_buf : B_buf;

	(* force_downto *)
	wire [Y_WIDTH:0] C;
	assign C[0] = CI;

	genvar i;
	generate for (i = 0; i < Y_WIDTH; i = i + 1) begin: slice
		\$fa #(.WIDTH(1)) fa_i (.A(AA[i]), .B(BB[i]), .C(C[i]), .X(C[i+1]), .Y(Y[i]));
	end endgenerate

	assign X = AA ^ BB;
	assign CO = C[Y_WIDTH:1];
endmodule
