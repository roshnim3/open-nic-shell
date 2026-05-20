"""
Sim A: verifies the packetparser_322mhz pipeline integrated into p2p_322mhz.

Drives a UDP/MoldUDP64/ITCH Add Order packet onto s_axis_cmac_rx, then reads
the AXI-Lite registers and asserts the parsed fields match what was injected.
"""

import logging

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotbext.axi import (AxiLiteBus, AxiLiteMaster, AxiStreamBus,
                           AxiStreamFrame, AxiStreamSource)

# Register offsets — must match p2p_322mhz.sv localparams.
REG_MAGIC               = 0x00
REG_PACKET_COUNT        = 0x08
REG_PARSED_MSG_COUNT    = 0x0C
REG_LAST_MSG_TYPE       = 0x10
REG_LAST_SRC_IP         = 0x14
REG_LAST_DST_IP         = 0x18
REG_LAST_PORTS          = 0x1C
REG_LAST_MSG_NUM        = 0x28
REG_LAST_TIMESTAMP_LOW  = 0x30
REG_LAST_REF_NUM_LOW    = 0x38
REG_LAST_REF_NUM_HIGH   = 0x3C
REG_LAST_BUY_SELL       = 0x40
REG_LAST_SHARE_AMT      = 0x44
REG_LAST_STOCK_SYM_LOW  = 0x48
REG_LAST_STOCK_SYM_HIGH = 0x4C
REG_LAST_PRICE          = 0x50

EXPECTED_MAGIC = 0x49544348  # "ITCH"


def build_packet():
    # 14B Ethernet + 20B IPv4 + 8B UDP = 42B headers.
    # Then 20B MoldUDP64 + 2B msg_len + 36B ITCH Add Order = 58B UDP payload.
    # Total = 100B, neatly spanning two 64B AXI-Stream beats (64 + 36).
    ether = (
        b"\x52\x54\x00\x12\x34\x56"      # dst MAC
        + b"\x52\x54\x00\x65\x43\x21"    # src MAC
        + b"\x08\x00"                    # ethertype = IPv4
    )
    ipv4 = (
        b"\x45\x00\x00\x64"              # version/IHL, DSCP/ECN, total_length=100
        + b"\x00\x00\x40\x00"            # id, flags+frag
        + b"\x40\x11\xAB\xCD"            # ttl, protocol=UDP, header_checksum
        + b"\x01\x01\x01\x01"            # src IP = 1.1.1.1
        + b"\x02\x02\x02\x02"            # dst IP = 2.2.2.2
    )
    udp = (
        b"\x04\xD2"                      # src port = 0x04D2
        + b"\x16\x2E"                    # dst port = 0x162E
        + b"\x00\x42"                    # UDP length = 66
        + b"\x00\x00"                    # UDP checksum
    )
    moldudp = (
        b"\x00" * 10                     # session
        + b"\x00" * 8                    # sequence
        + b"\x00\x01"                    # msg_count = 1
    )
    msg_len_prefix = b"\x00\x24"         # 36 bytes
    itch_add_order = (
        b"\x41"                              # msg type = Add Order
        + b"\x12\x34"                        # stock_locate (parser only captures byte at +3)
        + b"\x00\x00"                        # tracking number
        + b"\x00\x00\x00\x00\x02\x30"        # timestamp = 0x230
        + b"\x01\x23\x45\x67\x89\xAB\xCD\xEF"  # order ref num
        + b"B"                               # buy/sell = 'B' (0x42)
        + b"\x00\x00\x10\x00"                # shares = 0x1000
        + b"AAPL\x00\x00\x00\x00"            # stock symbol
        + b"\x00\x98\x96\x80"                # price = 0x00989680
    )
    assert len(itch_add_order) == 36
    pkt = ether + ipv4 + udp + moldudp + msg_len_prefix + itch_add_order
    assert len(pkt) == 100
    return pkt


class TB:
    def __init__(self, dut):
        self.dut = dut
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        # 322 MHz CMAC clock and 125 MHz AXI-Lite clock.
        cocotb.fork(Clock(dut.cmac_clk, 3105, units="ps").start())
        cocotb.fork(Clock(dut.axil_aclk, 8, units="ns").start())

        self.source_cmac_rx = AxiStreamSource(
            AxiStreamBus.from_prefix(dut, "s_axis_cmac_rx"),
            dut.cmac_clk,
            dut.p2p_322mhz_inst.cmac_rstn,
            reset_active_level=False,
        )
        self.control = AxiLiteMaster(
            AxiLiteBus.from_prefix(dut, "s_axil"),
            dut.axil_aclk,
            dut.p2p_322mhz_inst.axil_aresetn,
            reset_active_level=False,
        )

    async def reset(self):
        self.dut.mod_rstn.setimmediatevalue(1)
        await RisingEdge(self.dut.axil_aclk)
        await RisingEdge(self.dut.axil_aclk)
        self.dut.mod_rstn.value = 0
        await ClockCycles(self.dut.axil_aclk, 5)
        self.dut.mod_rstn.value = 1
        await RisingEdge(self.dut.mod_rst_done)

    async def read_reg(self, offset):
        resp = await self.control.read(offset, 4)
        return int.from_bytes(resp.data, byteorder="little")


@cocotb.test()
async def test_parse_add_order(dut):
    tb = TB(dut)
    await tb.reset()

    # AXI-Lite sanity before touching the parser.
    magic = await tb.read_reg(REG_MAGIC)
    assert magic == EXPECTED_MAGIC, \
        f"REG_MAGIC = 0x{magic:08X}, expected 0x{EXPECTED_MAGIC:08X}"
    tb.log.info("REG_MAGIC OK")

    pkt = build_packet()
    tb.log.info(f"Sending {len(pkt)}-byte packet on s_axis_cmac_rx")
    await tb.source_cmac_rx.send(AxiStreamFrame(tdata=pkt))

    # Wait for the parser to consume the buffer and for the snapshot toggle
    # to cross from cmac_clk into axil_aclk. ~200 axil cycles is generous.
    await ClockCycles(dut.axil_aclk, 200)

    pkt_count    = await tb.read_reg(REG_PACKET_COUNT)
    parsed_count = await tb.read_reg(REG_PARSED_MSG_COUNT)
    tb.log.info(f"packet_count={pkt_count} parsed_count={parsed_count}")
    assert pkt_count    >= 1, f"REG_PACKET_COUNT = {pkt_count}"
    assert parsed_count >= 1, f"REG_PARSED_MSG_COUNT = {parsed_count}"

    msg_type = await tb.read_reg(REG_LAST_MSG_TYPE)
    src_ip   = await tb.read_reg(REG_LAST_SRC_IP)
    dst_ip   = await tb.read_reg(REG_LAST_DST_IP)
    ports    = await tb.read_reg(REG_LAST_PORTS)
    msg_num  = await tb.read_reg(REG_LAST_MSG_NUM)
    ts_low   = await tb.read_reg(REG_LAST_TIMESTAMP_LOW)
    ref_lo   = await tb.read_reg(REG_LAST_REF_NUM_LOW)
    ref_hi   = await tb.read_reg(REG_LAST_REF_NUM_HIGH)
    buy_sell = await tb.read_reg(REG_LAST_BUY_SELL)
    shares   = await tb.read_reg(REG_LAST_SHARE_AMT)
    sym_lo   = await tb.read_reg(REG_LAST_STOCK_SYM_LOW)
    sym_hi   = await tb.read_reg(REG_LAST_STOCK_SYM_HIGH)
    price    = await tb.read_reg(REG_LAST_PRICE)

    tb.log.info(
        "Parsed: type=0x%02X src=0x%08X dst=0x%08X ports=0x%08X "
        "msg_num=%d ts_low=0x%08X ref=0x%08X%08X buy_sell=0x%02X "
        "shares=0x%08X sym=0x%08X%08X price=0x%08X",
        msg_type & 0xFF, src_ip, dst_ip, ports, msg_num & 0xFFFF,
        ts_low, ref_hi, ref_lo, buy_sell & 0xFF,
        shares, sym_hi, sym_lo, price,
    )

    assert msg_type & 0xFF == 0x41,   f"msg_type=0x{msg_type:08X}"
    assert src_ip   == 0x01010101,    f"src_ip=0x{src_ip:08X}"
    assert dst_ip   == 0x02020202,    f"dst_ip=0x{dst_ip:08X}"
    assert ports    == 0x04D2162E,    f"ports=0x{ports:08X}"
    assert msg_num & 0xFFFF == 1,     f"msg_num=0x{msg_num:08X}"
    assert ts_low   == 0x00000230,    f"ts_low=0x{ts_low:08X}"
    assert ref_hi   == 0x01234567,    f"ref_hi=0x{ref_hi:08X}"
    assert ref_lo   == 0x89ABCDEF,    f"ref_lo=0x{ref_lo:08X}"
    assert buy_sell & 0xFF == 0x42,   f"buy_sell=0x{buy_sell:08X}"
    assert shares   == 0x00001000,    f"shares=0x{shares:08X}"
    # Stock symbol "AAPL\0\0\0\0" — first 4 bytes go into the high word.
    assert sym_hi   == 0x4141504C,    f"sym_hi=0x{sym_hi:08X}"
    assert sym_lo   == 0x00000000,    f"sym_lo=0x{sym_lo:08X}"
    assert price    == 0x00989680,    f"price=0x{price:08X}"
