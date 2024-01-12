module strater_lp_vault::bucketus {

    use std::option;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;
    use sui::dynamic_field as df;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::clock::Clock;
    use sui::balance::{Self, Balance};
    use cetus_clmm::position::{Self, Position};
    use cetus_clmm::pool::{Self, Pool, AddLiquidityReceipt};
    use cetus_clmm::config::GlobalConfig;
    use integer_mate::i32::{Self, I32};
    use integer_mate::full_math_u128;

    // --------- Errors ---------

    const PACKAGE_VERSION: u64 = 1;

    // --------- Errors ---------

    const EInvalidPackageVersion: u64 = 0;
    const EVaultLiquidityNotEnough: u64 = 1;

    // --------- OTW ---------
    
    struct BUCKETUS has drop {}

    // --------- Objects ---------

    struct AdminCap has key, store {
        id: UID,
    }

    struct BeneficiaryCap has key, store {
        id: UID,
    }

    struct BucketusTreasury has key {
        id: UID,
        version: u64,
        cap: TreasuryCap<BUCKETUS>,
    }

    struct CetusLpVault has key, store {
        id: UID,
        // settings
        position: Position,
        unit_liquidity: u64,
        target_tick: I32,
        target_sqrt_price: u128,
        a_normalizer: u64,
        b_normalizer: u64,
        // status
        bucketus_supply: u64,
    }

    // --------- Constructor ---------
    
    fun init(otw: BUCKETUS, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            otw,
            9,
            b"BUCKETUS",
            b"SCET-STABLE-LP",
            b"Fungible LP token for stable pair on Cetus",
            option::some(url::new_unsafe_from_bytes(
                b"https://vb6zxndns5przvi3gv7fgo7auzf4qqremta27t4cj2bfawnrmifq.arweave.net/qH2btG2XXxzVGzV-UzvgpkvIQiRkwa_Pgk6CUFmxYgs"),
            ),
            ctx,
        );
        let vault = BucketusTreasury {
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
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        tick_lower: u32,
        tick_upper: u32,
        unit_liquidity: u64,
        target_tick: u32,
        target_sqrt_price: u128,
        a_normalizer: u64,
        b_normalizer: u64,
        ctx: &mut TxContext,
    ) {
        let position = pool::open_position<A,B>(
            config, pool, tick_lower, tick_upper, ctx,
        );
        let vault = CetusLpVault {
            id: object::new(ctx),
            position,
            unit_liquidity,
            target_tick: i32::from(target_tick),
            target_sqrt_price,
            a_normalizer,
            b_normalizer,
            bucketus_supply: 0,
        };
        transfer::share_object(vault);
    }

    public fun claim_profit<T>(
        _: &BeneficiaryCap,
        treasury: &mut BucketusTreasury,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert_valid_package_version(treasury);
        coin::take(borrow_balance_mut<T>(treasury), amount, ctx)
    }

    public fun claim_profit_to<T>(
        cap: &BeneficiaryCap,
        treasury: &mut BucketusTreasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let profit = claim_profit<T>(cap, treasury, amount, ctx);
        transfer::public_transfer(profit, recipient);
    }

    public fun update_version(
        treasury: &mut BucketusTreasury,
        new_version: u64,
    ) {
        treasury.version = new_version;
    }

    // --------- Public Function ---------

    public fun deposit<A, B>(
        treasury: &mut BucketusTreasury,
        vault: &mut CetusLpVault,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        delta_liquidity: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<BUCKETUS>, AddLiquidityReceipt<A, B>) {
        assert_valid_package_version(treasury);
        let bucketus_amount = liquidity_to_bucketus_amount(vault, delta_liquidity);
        let bucketus_coin = mint(treasury, vault, bucketus_amount, ctx);
        let receipt = pool::add_liquidity<A, B>(
            config,
            pool,
            &mut vault.position,
            delta_liquidity,
            clock,
        );
        vault.bucketus_supply = vault.bucketus_supply + bucketus_amount;
        (bucketus_coin, receipt)
    }

    public fun withdraw<A, B>(
        treasury: &mut BucketusTreasury,
        vault: &mut CetusLpVault,
        config: &GlobalConfig,
        pool: &mut Pool<A, B>,
        clock: &Clock,
        bucketus_coin: Coin<BUCKETUS>,
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
        balance::join(borrow_balance_mut<A>(treasury), fee_a);
        balance::join(borrow_balance_mut<B>(treasury), fee_b);

        let bucketus_amount = coin::value(&bucketus_coin);
        let vault_supply = vault.bucketus_supply;
        let vault_liquidity = position::liquidity(vault_position);
        let delta_liquidity = full_math_u128::mul_div_floor(
            vault_liquidity,
            (bucketus_amount as u128),
            (vault_supply as u128),
        );
        let (out_a, out_b) = pool::remove_liquidity(
            config,
            pool,
            vault_position,
            delta_liquidity,
            clock,
        );
        burn(treasury, vault, bucketus_coin);
        (
            coin::from_balance(out_a, ctx),
            coin::from_balance(out_b, ctx),
        )
    }

    // --------- Getter Functions ---------

    public fun borrow_cetus_position(vault: &CetusLpVault): &Position {
        &vault.position
    }

    public fun borrow_treasury_cap(treasury: &BucketusTreasury): &TreasuryCap<BUCKETUS> {
        &treasury.cap
    }

    public fun vault_supply(vault: &CetusLpVault): u64 {
        vault.bucketus_supply
    }

    public fun liquidity_to_bucketus_amount(
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

    fun mint(
        treasury: &mut BucketusTreasury,
        vault: &mut CetusLpVault,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<BUCKETUS> {
        vault.bucketus_supply = vault.bucketus_supply + amount;
        coin::mint(&mut treasury.cap, amount, ctx)
    }

    fun burn(
        treasury: &mut BucketusTreasury,
        vault: &mut CetusLpVault,
        coin: Coin<BUCKETUS>,
    ) {
        let coin_value = coin::value(&coin);
        assert!(coin_value <= vault.bucketus_supply, EVaultLiquidityNotEnough);
        vault.bucketus_supply = vault.bucketus_supply - coin_value;
        coin::burn(&mut treasury.cap, coin);
    }

    struct BalanceType<phantom T> has copy, drop, store {}

    fun borrow_balance_mut<T>(
        treasury: &mut BucketusTreasury,
    ): &mut Balance<T> {
        let type = BalanceType<T> {};
        let id_mut = &mut treasury.id;
        if (!df::exists_(id_mut, type)) {
            df::add(id_mut, type, balance::zero<T>());
        };
        df::borrow_mut<BalanceType<T>, Balance<T>>(id_mut, type)
    }

    fun assert_valid_package_version(treasury: &BucketusTreasury) {
        assert!(treasury.version == PACKAGE_VERSION, EInvalidPackageVersion);
    }
}