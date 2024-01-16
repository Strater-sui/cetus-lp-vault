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
        BUCKETUS,
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
            // std::debug::print(&buck_amount);
            // std::debug::print(&usdc_amount);
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

    #[test]
    fun test_withdraw() {
        let scenario_val = test_deposit();
        let scenario = &mut scenario_val;

        let user = @0x456;
        ts::next_tx(scenario, user);
        {
            let vault = ts::take_shared<CetusLpVault>(scenario);
            let treasury = ts::take_shared<BucketusTreasury>(scenario);
            let cetus_config = ts::take_shared<GlobalConfig>(scenario);
            let cetus_pool = ts::take_shared<Pool<BUCK, USDC>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let bucketus_in = coin::mint_for_testing<BUCKETUS>(1000000022/2, ts::ctx(scenario));
            let (buck_coin, usdc_coin) = bucketus::withdraw(
                &mut treasury,
                &mut vault,
                &cetus_config,
                &mut cetus_pool,
                &clock,
                bucketus_in,
                ts::ctx(scenario),
            );
            // std::debug::print(&buck_coin);
            // std::debug::print(&usdc_coin);
            balance::destroy_for_testing(coin::into_balance(buck_coin));
            balance::destroy_for_testing(coin::into_balance(usdc_coin));
            ts::return_shared(vault);
            ts::return_shared(treasury);
            ts::return_shared(cetus_config);
            ts::return_shared(cetus_pool);
            ts::return_shared(clock);
        };
        
        ts::end(scenario_val);
    }
}