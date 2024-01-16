#[test_only]
module strater_lp_vault::test_operations {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::Clock;
    use sui::transfer;
    use sui::balance;
    use sui::coin;
    use cetus_clmm::pool::{Self, Pool};
    use cetus_clmm::config::GlobalConfig;
    use strater_lp_vault::bucketus::{
        Self,
        BucketusTreasury,
        CetusLpVault,
        // AdminCap,
        // BeneficiaryCap,
    };
    use strater_lp_vault::test_create::{Self, BUCK, USDC};

    #[test]
    fun test_deposit(): Scenario {
        let admin = @0xde1;
        let tick_lower = 4294523716;
        let tick_upper = 443580;
        let target_tick = 4294898216;
        let target_sqrt_price = 583337266871351552;
        let a_normalizer = 1;
        let b_normalizer = 1_000;
        let scenario_val = test_create::setup_lp_vault(
            admin,
            tick_lower,
            tick_upper,
            target_tick,
            target_sqrt_price,
            a_normalizer,
            b_normalizer,
        );
        let scenario = &mut scenario_val;

        let user = @0x123;
        ts::next_tx(scenario, user);
        {
            let vault = ts::take_shared<CetusLpVault>(scenario);
            let treasury = ts::take_shared<BucketusTreasury>(scenario);
            let cetus_config = ts::take_shared<GlobalConfig>(scenario);
            let cetus_pool = ts::take_shared<Pool<BUCK, USDC>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let (bucketus_coin, receipt) = bucketus::deposit(
                &mut treasury,
                &mut vault,
                &cetus_config,
                &mut cetus_pool,
                15811389,
                &clock,
                ts::ctx(scenario),
            );
            assert!(coin::value(&bucketus_coin) == 1000000022, 0);
            transfer::public_transfer(bucketus_coin, user);
            let (buck_amount, usdc_amount) = pool::add_liquidity_pay_amount<BUCK, USDC>(&receipt);
            let buck_in = balance::create_for_testing(buck_amount);
            let usdc_in = balance::create_for_testing(usdc_amount);
            pool::repay_add_liquidity(
                &cetus_config,
                &mut cetus_pool,
                buck_in,
                usdc_in,
                receipt,
            );
            ts::return_shared(vault);
            ts::return_shared(treasury);
            ts::return_shared(cetus_config);
            ts::return_shared(cetus_pool);
            ts::return_shared(clock);
        };

        scenario_val
    }

}