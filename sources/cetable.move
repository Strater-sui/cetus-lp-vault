module strater_lp_vault::cetable {

    use std::option;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;
    use sui::dynamic_field as df;
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::clock::Clock;
    use sui::balance::{Self, Balance};
    use sui::event;
    use cetus_clmm::position::{Self, Position};
    use cetus_clmm::pool::{Self, Pool, AddLiquidityReceipt};
    use cetus_clmm::config::GlobalConfig;
    use cetus_clmm::rewarder::RewarderGlobalVault;
    use integer_mate::i32::{Self, I32};
    use integer_mate::full_math_u128;

    // --------- Version ---------

    const PACKAGE_VERSION: u64 = 1;

    // --------- Errors ---------

    const EInvalidPackageVersion: u64 = 0;
    const EVaultLiquidityNotEnough: u64 = 1;
    const EInvalidTickRange: u64 = 2;

    // --------- OTW ---------
    
    struct CETABLE has drop {}

    // --------- Objects ---------

    struct AdminCap has key, store {
        id: UID,
    }

    struct BeneficiaryCap has key, store {
        id: UID,
    }

    struct CetableTreasury has key {
        id: UID,
        version: u64,
        cap: TreasuryCap<CETABLE>,
    }

    struct CetusLpVault has key, store {
        id: UID,
        // settings
        position: Position,
        target_tick: I32,
        target_sqrt_price: u128,
        a_normalizer: u64,
        b_normalizer: u64,
        // status
        cetable_supply: u64,
    }

    // --------- Events ---------

    struct NewVault<phantom A, phantom B> has copy, drop {
        vault_id: ID,
        pool_id: ID,
        tick_lower: u32,
        tick_upper: u32,
    }

    // deprecated
    #[allow(unused_field)]
    struct CollectFee<phantom T> has copy, drop {
        amount: u64,
    }

    struct CollectFeeFrom<phantom T> has copy, drop {
        pool_id: ID,
        amount: u64,
    }

    struct Deposit<phantom A, phantom B> has copy, drop {
        vault_id: ID,
        amount_a: u64,
        amount_b: u64,
        cetable_amount: u64,
    }

    struct Withdraw<phantom A, phantom B> has copy, drop {
        vault_id: ID,
        amount_a: u64,
        amount_b: u64,
        cetable_amount: u64,
    }

    // --------- Constructor ---------
    #[allow(unused_function)]
    fun init(otw: CETABLE, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            otw,
            9,
            b"CETABLE",
            b"SCET-STABLE-LP",
            b"Fungible LP token for stable pair on Cetus",
            option::some(url::new_unsafe_from_bytes(
                b"https://reb6vnedll4q6tlu63cmk7iu3y252525bgh3zf7tq5onis572pfq.arweave.net/iQPqtINa-Q9NdPbExX0U3jXdd10Jj7yX84dc1Eu_08s"),
            ),
            ctx,
        );
        let vault = CetableTreasury {
            id: object::new(ctx),
            version: PACKAGE_VERSION,
            cap: treasury_cap,
        };
        transfer::share_object(vault);
        let deployer = tx_context::sender(ctx);
        transfer::public_transfer(metadata, deployer);
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, deployer);
        let benef_cap = BeneficiaryCap { id: object::new(ctx) };
        transfer::transfer(benef_cap, deployer);
    }

    // --------- Admin Function ---------

    public fun create_vault<A, B>(
        _: &AdminCap,
        treasury: &CetableTreasury,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        tick_lower: u32,
        tick_upper: u32,
        target_tick: u32,
        target_sqrt_price: u128,
        a_normalizer: u64,
        b_normalizer: u64,
        ctx: &mut TxContext,
    ) {
        assert_valid_package_version(treasury); // BUC-4
        assert!(i32::gt(
            i32::from_u32(tick_upper),
            i32::from_u32(tick_lower),
        ), EInvalidTickRange); // BUC-3
        let position = pool::open_position<A,B>(
            config, pool, tick_lower, tick_upper, ctx,
        );
        let vault = CetusLpVault {
            id: object::new(ctx),
            position,
            target_tick: i32::from_u32(target_tick),
            target_sqrt_price,
            a_normalizer,
            b_normalizer,
            cetable_supply: 0,
        };
        let vault_id = object::id(&vault);
        transfer::share_object(vault);
        
        let pool_id = object::id(pool);
        event::emit(NewVault<A,B> {
            vault_id,
            pool_id,
            tick_lower,
            tick_upper,
        });
    }

    public fun claim_fee<T>(
        _: &BeneficiaryCap,
        treasury: &mut CetableTreasury,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert_valid_package_version(treasury);
        coin::take(borrow_balance_mut<T>(treasury), amount, ctx)
    }

    public fun claim_fee_to<T>(
        cap: &BeneficiaryCap,
        treasury: &mut CetableTreasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert_valid_package_version(treasury);
        let profit = claim_fee<T>(cap, treasury, amount, ctx);
        transfer::public_transfer(profit, recipient);
    }

    public fun claim_all<T>(
        _: &BeneficiaryCap,
        treasury: &mut CetableTreasury,
    ): Balance<T> {
        assert_valid_package_version(treasury);
        balance::withdraw_all(borrow_balance_mut<T>(treasury))
    }

    public fun claim_reward<A, B, C>(
        _: &BeneficiaryCap,
        vault: &CetusLpVault,
        cetus_config: &GlobalConfig,
        cetus_pool: &mut Pool<A, B>,
        cetus_vault: &mut RewarderGlobalVault,
        clock: &Clock,
    ): Balance<C> {
        let cetus_position = &vault.position;
        cetus_clmm::pool::collect_reward(
            cetus_config,
            cetus_pool,
            cetus_position,
            cetus_vault,
            true,
            clock,
        )
    }

    public fun claim_reward_to<A, B, C>(
        cap: &BeneficiaryCap,
        vault: &CetusLpVault,
        cetus_config: &GlobalConfig,
        cetus_pool: &mut Pool<A, B>,
        cetus_vault: &mut RewarderGlobalVault,
        clock: &Clock,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let reward = claim_reward<A, B, C>(
            cap, vault, cetus_config, cetus_pool, cetus_vault, clock,
        );
        let reward = coin::from_balance(reward, ctx);
        transfer::public_transfer(reward, recipient);
    }

    public fun update_version(
        _: &AdminCap, // BUC-1
        treasury: &mut CetableTreasury,
        new_version: u64,
    ) {
        assert_valid_package_version(treasury);
        treasury.version = new_version;
    }

    // --------- Public Function ---------

    public fun deposit<A, B>(
        treasury: &mut CetableTreasury,
        vault: &mut CetusLpVault,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        delta_liquidity: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<CETABLE>, AddLiquidityReceipt<A, B>) {
        assert_valid_package_version(treasury);
        let cetable_amount = liquidity_to_cetable_amount(vault, delta_liquidity);
        let cetable_coin = mint(treasury, vault, cetable_amount, ctx);
        let receipt = pool::add_liquidity<A, B>(
            config,
            pool,
            &mut vault.position,
            delta_liquidity,
            clock,
        );
        // vault.cetable_supply = vault.cetable_supply + cetable_amount; // BUC-2
        let vault_id = object::id(vault);
        let (amount_a, amount_b) = pool::add_liquidity_pay_amount(&receipt);
        event::emit(Deposit<A,B> {
            vault_id,
            amount_a,
            amount_b,
            cetable_amount,
        });
        (cetable_coin, receipt)
    }

    public fun withdraw<A, B>(
        treasury: &mut CetableTreasury,
        vault: &mut CetusLpVault,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        clock: &Clock,
        cetable_coin: Coin<CETABLE>,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        assert_valid_package_version(treasury);
        let vault_position = &mut vault.position;
        let (fee_a, fee_b) = pool::collect_fee(
            config,
            pool,
            vault_position,
            true,
        );
        let pool_id = object::id(pool);
        collect_fee(treasury, pool_id, fee_a);
        collect_fee(treasury, pool_id, fee_b);

        let cetable_amount = coin::value(&cetable_coin);
        let vault_supply = vault.cetable_supply;
        let vault_liquidity = position::liquidity(vault_position);
        let delta_liquidity = full_math_u128::mul_div_floor(
            vault_liquidity,
            (cetable_amount as u128),
            (vault_supply as u128),
        );
        let (out_a, out_b) = pool::remove_liquidity(
            config,
            pool,
            vault_position,
            delta_liquidity,
            clock,
        );
        burn(treasury, vault, cetable_coin);
        let vault_id = object::id(vault);
        event::emit(Withdraw<A,B> {
            vault_id,
            amount_a: balance::value(&out_a),
            amount_b: balance::value(&out_b),
            cetable_amount,
        });
        (
            coin::from_balance(out_a, ctx),
            coin::from_balance(out_b, ctx),
        )
    }

    // --------- Getter Functions ---------

    public fun borrow_cetus_position(vault: &CetusLpVault): &Position {
        &vault.position
    }

    public fun borrow_treasury_cap(treasury: &CetableTreasury): &TreasuryCap<CETABLE> {
        &treasury.cap
    }

    public fun vault_supply(vault: &CetusLpVault): u64 {
        vault.cetable_supply
    }

    public fun liquidity_to_cetable_amount(
        vault: &CetusLpVault,
        delta_liquidity: u128,
    ): u64 {
        let (tick_lower, tick_upper) = position::tick_range(&vault.position);
        let (amount_a, amount_b) = pool::get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            vault.target_tick,
            vault.target_sqrt_price,
            delta_liquidity,
            false,
        );
        amount_a * vault.a_normalizer + amount_b * vault.b_normalizer
    }

    // --------- Internal Functions ---------

    fun assert_valid_package_version(treasury: &CetableTreasury) {
        assert!(treasury.version == PACKAGE_VERSION, EInvalidPackageVersion);
    }

    fun mint(
        treasury: &mut CetableTreasury,
        vault: &mut CetusLpVault,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<CETABLE> {
        vault.cetable_supply = vault.cetable_supply + amount;
        coin::mint(&mut treasury.cap, amount, ctx)
    }

    fun burn(
        treasury: &mut CetableTreasury,
        vault: &mut CetusLpVault,
        coin: Coin<CETABLE>,
    ) {
        let coin_value = coin::value(&coin);
        assert!(coin_value <= vault.cetable_supply, EVaultLiquidityNotEnough);
        vault.cetable_supply = vault.cetable_supply - coin_value;
        coin::burn(&mut treasury.cap, coin);
    }

    struct BalanceType<phantom T> has copy, drop, store {}

    fun borrow_balance_mut<T>(
        treasury: &mut CetableTreasury,
    ): &mut Balance<T> {
        let type = BalanceType<T> {};
        let id_mut = &mut treasury.id;
        if (!df::exists_(id_mut, type)) {
            df::add(id_mut, type, balance::zero<T>());
        };
        df::borrow_mut<BalanceType<T>, Balance<T>>(id_mut, type)
    }

    fun collect_fee<T>(
        treasury: &mut CetableTreasury,
        pool_id: ID,
        fee: Balance<T>,
    ) {
        let amount = balance::value(&fee);
        balance::join(borrow_balance_mut<T>(treasury), fee);
        event::emit(CollectFeeFrom<T> { pool_id, amount });
    }

    // --------- Test-only Functions ---------
    #[test_only]
    use sui::test_utils::create_one_time_witness;
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(create_one_time_witness<CETABLE>(), ctx);
    }
}