#[test_only]
module strater_lp_vault::test_math {

    use cetus_clmm::pool::get_amount_by_liquidity;
    use integer_mate::i32;

    // --------- Constants ---------

    const UNIT_LIQUIDITY: u128 = 2500377417; // this liquidity -> mint 1 CETABLE
    const TICK_UPPER: u32 = 10; // +10
    const TICK_LOWER: u32 = 2; // +2
    const TARGET_TICK: u32 = 6; // +6
    const TARGET_SQRT_PRICE: u128 = 18452277267077120000; // price(y/x) = 1.0006
    const A_NORMALIZER: u64 = 1;
    const B_NORMALIZER: u64 = 1;

    #[test]
    fun test_liquidity_formula() {
        let liquidity: u128 = UNIT_LIQUIDITY;
        let target_sqrt_price = TARGET_SQRT_PRICE;
        let target_value = compute_value(liquidity, target_sqrt_price);
        std::debug::print(&target_value);
        let double_target_value = compute_value(liquidity * 2, target_sqrt_price);
        std::debug::print(&double_target_value);
        // assert!(double_target_value == 2 * target_value, 0);
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
            std::debug::print(&current_value);
            // assert!(current_value >= target_value, 0);
            idx = idx + 1;
        };
    }

    fun compute_value(
        liquidity: u128,
        current_sqrt_price: u128,
    ): u64 {
        let tick_lower = i32::from_u32(TICK_LOWER);
        let tick_upper = i32::from_u32(TICK_UPPER);
        let current_tick = i32::from_u32(TARGET_TICK);
        let (amount_a, amount_b) = get_amount_by_liquidity(
            tick_lower, tick_upper, current_tick, current_sqrt_price, liquidity, false,
        );
        amount_a * A_NORMALIZER + amount_b * B_NORMALIZER
    }

    public fun unit_liquidity(): u128 { UNIT_LIQUIDITY }
    public fun tick_upper(): u32 { TICK_UPPER }
    public fun tick_lower(): u32 { TICK_LOWER }
    public fun target_tick(): u32 { TARGET_TICK }
    public fun target_sqrt_price(): u128 { TARGET_SQRT_PRICE }
    public fun a_normalizer(): u64 { A_NORMALIZER }
    public fun b_normalizer(): u64 { B_NORMALIZER }
}