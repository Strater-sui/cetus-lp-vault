#[test_only]
module strater_lp_vault::test_math {

    use cetus_clmm::pool::get_amount_by_liquidity;
    use integer_mate::i32;

    // --------- Constants ---------

    // const UNIT_LIQUIDITY: u64 = 15811389; // this liquidity -> mint 1 BUCKETUS
    // const MAX_TICK_UPPER: u32 = 443636; // +443636
    // const MIN_TICK_LOWER: u32 = 4294523660; // -443636
    // const TARGET_TICK: u32 = 4294898216; // -69080
    // const TARGET_SQRT_PRICE: u128 = 583337266871351552; // price(y/x) = 0.001
    // const USDC_NORMALIZER: u64 = 1_000;

    const AB_NORMALIZER: u64 = 1_000;

    #[test]
    fun test_liquidity_formula() {
        let liquidity: u128 = 15811389;
        let target_sqrt_price = 583337266871351552;
        let target_value = compute_value(liquidity, target_sqrt_price);
        std::debug::print(&target_value);
        let double_target_value = compute_value(liquidity * 2, target_sqrt_price);
        // std::debug::print(&double_target_value);
        assert!(double_target_value == 2 * target_value, 0);
        let idx = 0;
        let current_sqrt_price = target_sqrt_price;
        while (idx < 1_000) {
            current_sqrt_price = current_sqrt_price * 10001 / 10000;
            let current_value = compute_value(liquidity, current_sqrt_price);
            // std::debug::print(&current_value);
            assert!(current_value >= target_value, 0);
            idx = idx + 1;
        };
        let idx = 0;
        let current_sqrt_price = target_sqrt_price;
        while (idx < 1_000) {
            current_sqrt_price = current_sqrt_price * 10000 / 10001;
            let current_value = compute_value(liquidity, current_sqrt_price);
            // std::debug::print(&current_value);
            assert!(current_value >= target_value, 0);
            idx = idx + 1;
        };
    }

    fun compute_value(
        liquidity: u128,
        current_sqrt_price: u128,
    ): u64 {
        let tick_lower = i32::from_u32(4294523660);
        let tick_upper = i32::from_u32(443636);
        let current_tick = i32::from_u32(4294898216);
        let (amount_a, amount_b) = get_amount_by_liquidity(
            tick_lower, tick_upper, current_tick, current_sqrt_price, liquidity, false,
        );
        let amount_b = amount_b * AB_NORMALIZER;
        amount_a + amount_b
    }
}