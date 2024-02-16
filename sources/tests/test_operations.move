#[test_only]
module strater_lp_vault::test_operations {

    use sui::test_scenario::{Self as ts, Scenario};
    use sui::clock::Clock;
    use sui::transfer;
    use sui::balance;
    use sui::coin;
    use cetus_clmm::pool::{Self, Pool};
    use cetus_clmm::config::GlobalConfig;
    use strater_lp_vault::cetable::{
        Self,
        CETABLE,
        CetableTreasury,
        CetusLpVault,
        // AdminCap,
        // BeneficiaryCap,
    };
    use strater_lp_vault::test_create::{Self, USDT, USDC};
    use strater_lp_vault::test_math as math;

    #[test]
    fun test_deposit(): Scenario {
        let admin = @0xde1;
        let scenario_val = test_create::setup_lp_vault(
            admin,
            math::tick_lower(),
            math::tick_upper(),
            math::target_tick(),
            math::target_sqrt_price(),
            math::a_normalizer(),
            math::b_normalizer(),
        );
        let scenario = &mut scenario_val;

        let user = @0x123;
        ts::next_tx(scenario, user);
        {
            let vault = ts::take_shared<CetusLpVault>(scenario);
            let treasury = ts::take_shared<CetableTreasury>(scenario);
            let cetus_config = ts::take_shared<GlobalConfig>(scenario);
            let cetus_pool = ts::take_shared<Pool<USDT, USDC>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let (cetable_coin, receipt) = cetable::deposit(
                &mut treasury,
                &mut vault,
                &cetus_config,
                &mut cetus_pool,
                math::unit_liquidity(),
                &clock,
                ts::ctx(scenario),
            );
            assert!(coin::value(&cetable_coin) == 1000000, 0);
            transfer::public_transfer(cetable_coin, user);
            let (usdt_amount, usdc_amount) = pool::add_liquidity_pay_amount<USDT, USDC>(&receipt);
            std::debug::print(&usdt_amount);
            std::debug::print(&usdc_amount);
            let usdt_in = balance::create_for_testing(usdt_amount);
            let usdc_in = balance::create_for_testing(usdc_amount);
            pool::repay_add_liquidity(
                &cetus_config,
                &mut cetus_pool,
                usdt_in,
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
            let treasury = ts::take_shared<CetableTreasury>(scenario);
            let cetus_config = ts::take_shared<GlobalConfig>(scenario);
            let cetus_pool = ts::take_shared<Pool<USDT, USDC>>(scenario);
            let clock = ts::take_shared<Clock>(scenario);
            let cetable_in = coin::mint_for_testing<CETABLE>(1000000/2, ts::ctx(scenario));
            let (usdt_coin, usdc_coin) = cetable::withdraw(
                &mut treasury,
                &mut vault,
                &cetus_config,
                &mut cetus_pool,
                &clock,
                cetable_in,
                ts::ctx(scenario),
            );
            std::debug::print(&coin::value(&usdt_coin));
            std::debug::print(&coin::value(&usdc_coin));
            balance::destroy_for_testing(coin::into_balance(usdt_coin));
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