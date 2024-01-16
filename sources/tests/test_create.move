#[test_only]
#[lint_allow(share_owned)]
module strater_lp_vault::test_create {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use cetus_clmm::pool;
    use cetus_clmm::config;
    use strater_lp_vault::bucketus::{
        Self,
        BucketusTreasury,
        // CetusLpVault,
        AdminCap,
        // BeneficiaryCap,
    };

    struct CoinA has drop {}

    struct CoinB has drop {}

    public fun setup_lp_vault(
        admin: address,
        tick_lower: u32,
        tick_upper: u32,
        target_tick: u32,
        target_sqrt_price: u128,
        a_normalizer: u64,
        b_normalizer: u64,
    ): Scenario {
        let scenario_val = ts::begin(admin);
        let scenario = &mut scenario_val;
        {
            bucketus::init_for_testing(ts::ctx(scenario));
            let clock = clock::create_for_testing(ts::ctx(scenario));
            clock::share_for_testing(clock);
        };

        ts::next_tx(scenario, admin);
        {
            let clock = ts::take_shared<Clock>(scenario);
            let (cetus_cap, cetus_config) = config::new_global_config_for_test(
                ts::ctx(scenario),
                0,
            );
            transfer::public_transfer(cetus_cap, admin);
            let cetus_pool = pool::new_for_test<CoinA, CoinB>(
                60,
                583337266871351552,
                2_500,
                std::string::utf8(b""),
                0,
                &clock,
                ts::ctx(scenario),
            );

            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let treasury = ts::take_shared<BucketusTreasury>(scenario);
            bucketus::create_vault<CoinA, CoinB>(
                &admin_cap,
                &treasury,
                &cetus_config,
                &mut cetus_pool,
                tick_lower,
                tick_upper,
                target_tick,
                target_sqrt_price,
                a_normalizer,
                b_normalizer,
                ts::ctx(scenario),
            );
            ts::return_shared(treasury);
            ts::return_shared(clock);
            ts::return_to_sender(scenario, admin_cap);
            transfer::public_share_object(cetus_config);
            transfer::public_share_object(cetus_pool);
        };

        scenario_val
    }

    #[test]
    fun test_create_vault() {
        let admin = @0xde1;
        let tick_lower = 4294523716;
        let tick_upper = 443580;
        let target_tick = 4294898216;
        let target_sqrt_price = 583337266871351552;
        let a_normalizer = 1;
        let b_normalizer = 1_000;
        let scenario_val = setup_lp_vault(
            admin,
            tick_lower,
            tick_upper,
            target_tick,
            target_sqrt_price,
            a_normalizer,
            b_normalizer,
        );
        ts::end(scenario_val);
    }

    #[test]
    #[expected_failure(abort_code = bucketus::EInvalidTickRange)]
    fun test_create_vault_with_invalid_tick_range() {
        let admin = @0xde1;
        let tick_lower = 443636;
        let tick_upper = 4294523660;
        let target_tick = 4294898216;
        let target_sqrt_price = 583337266871351552;
        let a_normalizer = 1;
        let b_normalizer = 1_000;
        let scenario_val = setup_lp_vault(
            admin,
            tick_lower,
            tick_upper,
            target_tick,
            target_sqrt_price,
            a_normalizer,
            b_normalizer,
        );
        ts::end(scenario_val);
    }
}