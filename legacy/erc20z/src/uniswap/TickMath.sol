// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TickMath {
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        require(tick >= MIN_TICK && tick <= MAX_TICK, "Tick out of bounds");

        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));

        uint256 ratio = absTick & 1 != 0 ? 0xFFFcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 2 != 0) ratio = (ratio * 0xFFF97272373D413259A46990580E213A) >> 128;
        if (absTick & 4 != 0) ratio = (ratio * 0xFFF2e50F5F656932EF12357CF3C7FDCC) >> 128;
        if (absTick & 8 != 0) ratio = (ratio * 0xFFE5CACA7E10C8AEB5D1D0BDFA87C509) >> 128;
        if (absTick & 16 != 0) ratio = (ratio * 0xFFCB9843D60F6159C9DB58835C926644) >> 128;
        if (absTick & 32 != 0) ratio = (ratio * 0xFF973B41FA98C081472E6896DFB254C0) >> 128;
        if (absTick & 64 != 0) ratio = (ratio * 0xFF2EA16466C96A3843EC78B326B52861) >> 128;
        if (absTick & 128 != 0) ratio = (ratio * 0xFE5DEE046A99A2A811C461F1969C3053) >> 128;
        if (absTick & 256 != 0) ratio = (ratio * 0xFCBE86C7900A88AEDC413238B989F209) >> 128;
        if (absTick & 512 != 0) ratio = (ratio * 0xF987A7253AC413176F2B074CF7815E54) >> 128;
        if (absTick & 1024 != 0) ratio = (ratio * 0xF3392B0822B70005940C7A398E4B70F3) >> 128;
        if (absTick & 2048 != 0) ratio = (ratio * 0xE7159475A2C29B7443B29C7FA6E889D9) >> 128;
        if (absTick & 4096 != 0) ratio = (ratio * 0xD097F3BDFD2022B8845AD8F792AA5825) >> 128;
        if (absTick & 8192 != 0) ratio = (ratio * 0xA9F746462D870FDF8A65DC1F90E061E5) >> 128;
        if (absTick & 16384 != 0) ratio = (ratio * 0x70D869A156D2A1B890BB3DF62BAF32F7) >> 128;
        if (absTick & 32768 != 0) ratio = (ratio * 0x31BE135F97D08FD981231505542FCFA6) >> 128;
        if (absTick & 65536 != 0) ratio = (ratio * 0x9AA508B5B7A84E1C677DE54F3E99BC9) >> 128;
        if (absTick & 131072 != 0) ratio = (ratio * 0x5D6AF8DED63A05DCEFF8E6D297E7B9E4) >> 128;
        if (absTick & 262144 != 0) ratio = (ratio * 0x2216E584F5FA1EA926041BEDFE98) >> 128;
        if (absTick & 524288 != 0) ratio = (ratio * 0x48A170391F7DC42444E8FA2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}
