/*
 *  yosys -- Yosys Open SYnthesis Suite
 *
 *  PMUX structure optimization pass (赛题二 自定义 pass)
 *  作品「信号星河：PMUX 通路择」
 *
 *  本文件随 yosys 主程序一同编译（非 plugin 动态加载），由
 *  techlibs/intel/synth_intel.cc 在综合流程内部显式调用。
 *
 *  插入点：synth_intel 的 map_ffram 段、techmap -map +/techmap.v 之前，
 *  此时 $pmux / $mux 与 $xor / $and / $or 仍为高层单元。
 *
 *  R1 规则（同构布尔分支公共操作数提出，确定性等价变换）：
 *
 *    对一个 $pmux / $mux，若其所有分支信号都被同一类型（$xor / $and / $or）、
 *    同宽度、无符号的二元布尔单元驱动，且这些单元共享同一个公共操作数 C，
 *    即分支 i 为  P_i  op  C （op ∈ {xor, and, or}），则由分配律：
 *
 *        MUX(P_i op C)  ≡  MUX(P_i)  op  C
 *
 *    把公共操作数 C 提出到 MUX 输出之后：MUX 只选择私有操作数 P_i，
 *    再在 MUX 输出级统一做一次 P  op C；消除 (分支数 − 1) 个重复布尔单元。
 *
 *    正确性边界（只在满足全部条件时才变换，否则原样保留，保证等价与安全）：
 *      - 仅 $xor / $and / $or（满足对自身的分配律）；$add / $sub 不满足，禁止套用。
 *      - 所有分支驱动同型、等宽（= MUX 数据宽）、A/B/Y 三端口等宽、无符号。
 *      - 公共操作数 C 不落在当前 MUX 的任何输入信号（A/B/S）上，避免引入组合环。
 *      - 分支信号必须恰好被一个高层布尔单元驱动；常量或无驱动分支放弃本规则。
 */

#include "kernel/yosys.h"
#include "kernel/sigtools.h"

USING_YOSYS_NAMESPACE
PRIVATE_NAMESPACE_BEGIN

struct PmuxOptPass : public Pass {
	PmuxOptPass() : Pass("pmux_opt", "PMUX structure optimization pass") { }

	void help() override
	{
		//   |---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|---v---|
		log("\n");
		log("    pmux_opt [selection]\n");
		log("\n");
		log("Custom PMUX structure optimization pass for the FPGA competition.\n");
		log("Rule R1 hoists a shared operand out of isomorphic boolean branches of\n");
		log("a $pmux / $mux after the multiplexer.\n");
		log("\n");
	}

	static bool is_bool_op(const RTLIL::IdString &t)
	{
		return t == ID($xor) || t == ID($and) || t == ID($or);
	}

	// 在一个模块内执行 R1；返回本模块命中的 MUX 数与被消除的旧驱动单元数。
	void optimize_module(RTLIL::Module *module, int &r1_hits, int &r1_removed)
	{
		// 1) Y 信号(规范化) -> 驱动单元 映射（高层网表，一驱动一信号）
		dict<RTLIL::SigSpec, RTLIL::Cell*> ydrv;
		for (auto cell : module->cells())
		{
			if (!cell->hasPort(ID::Y)) continue;
			RTLIL::SigSpec y = cell->getPort(ID::Y);
			y.sort_and_unify();
			ydrv[y] = cell;
		}

		// 2) 先快照所有 $pmux / $mux，避免遍历期间新增单元影响迭代
		std::vector<RTLIL::Cell*> targets;
		for (auto cell : module->cells())
			if (cell->type == ID($pmux) || cell->type == ID($mux))
				targets.push_back(cell);

		pool<RTLIL::Cell*> kill;

		for (auto mux : targets)
		{
			int w = mux->getPort(ID::A).size();
			if (w == 0) continue;

			// 收集 MUX 的全部分支信号：$pmux = A(默认) + B 的各段；$mux = A, B
			std::vector<RTLIL::SigSpec> branches;
			branches.push_back(mux->getPort(ID::A));
			if (mux->type == ID($pmux)) {
				RTLIL::SigSpec B = mux->getPort(ID::B);
				int n = B.size() / w;
				for (int i = 0; i < n; i++)
					branches.push_back(B.extract(i * w, w));
			} else {
				branches.push_back(mux->getPort(ID::B));
			}
			if (branches.size() < 2) continue;

			// 3) 逐分支定位驱动单元；任一非单驱动则放弃本 MUX
			std::vector<RTLIL::Cell*> drv;
			bool ok = true;
			for (auto &br : branches) {
				RTLIL::SigSpec key = br;
				key.sort_and_unify();
				auto it = ydrv.find(key);
				if (it == ydrv.end()) { ok = false; break; }
				drv.push_back(it->second);
			}
			if (!ok) continue;

			// 4) 同型、等宽、无符号校验
			RTLIL::IdString bt = drv[0]->type;
			if (!is_bool_op(bt)) continue;
			for (auto c : drv) {
				if (c->type != bt) { ok = false; break; }
				if (c->getPort(ID::Y).size() != w) { ok = false; break; }
				if (c->getPort(ID::A).size() != w || c->getPort(ID::B).size() != w) { ok = false; break; }
				if (c->hasParam(ID::A_SIGNED) && c->getParam(ID::A_SIGNED).as_int()) { ok = false; break; }
				if (c->hasParam(ID::B_SIGNED) && c->getParam(ID::B_SIGNED).as_int()) { ok = false; break; }
			}
			if (!ok) continue;

			// 5) 求公共操作数：先假定首单元的 A、B 为候选，逐分支核对
			RTLIL::SigSpec cA = drv[0]->getPort(ID::A); cA.sort_and_unify();
			RTLIL::SigSpec cB = drv[0]->getPort(ID::B); cB.sort_and_unify();
			bool matchA = true, matchB = true;
			for (size_t i = 1; i < drv.size(); i++) {
				RTLIL::SigSpec a = drv[i]->getPort(ID::A); a.sort_and_unify();
				RTLIL::SigSpec b = drv[i]->getPort(ID::B); b.sort_and_unify();
				if (!(a == cA || b == cA)) matchA = false;
				if (!(a == cB || b == cB)) matchB = false;
			}
			RTLIL::SigSpec common;
			if (matchA) common = cA;
			else if (matchB) common = cB;
			else continue;

			// 6) 防环：公共操作数不得引用当前 MUX 的任何输入（A/B/S）信号位
			std::set<RTLIL::SigBit> inbits;
			for (RTLIL::IdString port : {ID::A, ID::B, ID::S}) {
				if (!mux->hasPort(port)) continue;
				auto set = mux->getPort(port).to_sigbit_set();
				inbits.insert(set.begin(), set.end());
			}
			{
				auto cset = common.to_sigbit_set();
				for (auto bit : cset)
					if (inbits.count(bit)) { ok = false; break; }
			}
			if (!ok) continue;

			// 7) 提取各分支私有操作数；结构不闭合则放弃
			std::vector<RTLIL::SigSpec> priv;
			for (auto c : drv) {
				RTLIL::SigSpec a = c->getPort(ID::A); a.sort_and_unify();
				RTLIL::SigSpec b = c->getPort(ID::B); b.sort_and_unify();
				if (a == common) priv.push_back(b);
				else if (b == common) priv.push_back(a);
				else { ok = false; break; }
			}
			if (!ok) continue;

			// 8) 执行变换：MUX 改选私有操作数，输出接中间线；输出级统一 op common
			RTLIL::SigSpec oldY = mux->getPort(ID::Y);
			RTLIL::Wire *mid = module->addWire(NEW_ID, w);
			RTLIL::SigSpec midSig(mid);

			mux->setPort(ID::A, priv[0]);
			if (mux->type == ID($pmux)) {
				RTLIL::SigSpec newB;
				for (size_t i = 1; i < priv.size(); i++) newB.append(priv[i]);
				mux->setPort(ID::B, newB);
				// S_WIDTH 不变：分支数量未变
			} else {
				mux->setPort(ID::B, priv[1]);
			}
			mux->setPort(ID::Y, midSig);

			if (bt == ID($xor))
				module->addXor(NEW_ID, midSig, common, oldY, false);
			else if (bt == ID($and))
				module->addAnd(NEW_ID, midSig, common, oldY, false);
			else
				module->addOr(NEW_ID, midSig, common, oldY, false);

			for (auto c : drv) kill.insert(c);
			r1_hits++;
			r1_removed += (int)drv.size();
		}

		for (auto c : kill)
			module->remove(c);
	}

	void execute(std::vector<std::string> args, RTLIL::Design *design) override
	{
		log_header(design, "Executing PMUX_OPT pass (PMUX structure optimization).\n");

		size_t argidx = 1;
		extra_args(args, argidx, design);

		int total_pmux = 0, total_mux = 0;
		int r1_hits = 0, r1_removed = 0;

		for (auto module : design->selected_modules())
		{
			int pmux_cnt = 0, mux_cnt = 0;
			for (auto cell : module->selected_cells())
			{
				if (cell->type == "$pmux") pmux_cnt++;
				else if (cell->type == "$mux") mux_cnt++;
			}
			total_pmux += pmux_cnt;
			total_mux += mux_cnt;
			log("pmux_opt: module %-24s  $pmux=%-3d $mux=%-3d\n",
				module->name.c_str(), pmux_cnt, mux_cnt);

			int hits = 0, removed = 0;
			optimize_module(module, hits, removed);
			r1_hits += hits;
			r1_removed += removed;
		}

		log("pmux_opt: design totals  $pmux=%d $mux=%d | R1 hits=%d removed-drivers=%d\n",
			total_pmux, total_mux, r1_hits, r1_removed);
	}
} PmuxOptPass;

PRIVATE_NAMESPACE_END
