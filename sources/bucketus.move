module strater_lp_vault::bucketus {

    use std::option;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;
    use sui::object_table::{Self, ObjectTable};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::event;
    use cetus_clmm::position::{Self, Position as CetusPosition};
    use cetus_clmm::pool;
    use integer_mate::i32;

    // --------- Constants ---------

    const MAX_TICK_UPPER: u32 = 443636; // +443636
    const MIN_TICK_LOWER: u32 = 4294523660; // -443636
    const TARGET_TICK: u32 = 4294898216; // -69080
    const TARGET_SQRT_PRICE: u128 = 583337266871351552; // price(y/x) = 0.001
    const USDC_NORMALIZER: u64 = 1_000;
    const TARGET_CETUS_POOL_ID: address = @0x6ecf6d01120f5f055f9a605b56fd661412a81ec7c8b035255e333c664a0c12e7;

    // --------- Errors ---------

    const EInvalidPositionPoolId: u64 = 0;
    const EInvalidPositionRange: u64 = 1;
    const ENotEnoughRepayment: u64 = 2;

    // --------- OTW ---------
    
    struct BUCKETUS has drop {}

    // --------- Events ---------

    struct Deposit has copy, drop {
        position_id: ID,
        position_value: u64,        
    }

    struct Withdraw has copy, drop {
        position_id: ID,
        position_value: u64,
    }

    // --------- Objects ---------

    struct CetusLpVault has key {
        id: UID,
        treasury_cap: TreasuryCap<BUCKETUS>,
        table: ObjectTable<ID, CetusPosition>,
    }

    struct CetusLpProof has key, store {
        id: UID,
        position_id: ID,
        position_value: u64,        
    }

    fun init(otw: BUCKETUS, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            otw,
            9,
            b"BUCKETUS",
            b"SCET-BUCK/USDC-0.25 LP",
            b"Fungible LP token for BUCK/USDC (fee tier: 0.25) full range",
            option::some(url::new_unsafe_from_bytes(
                b"https://vb6zxndns5przvi3gv7fgo7auzf4qqremta27t4cj2bfawnrmifq.arweave.net/qH2btG2XXxzVGzV-UzvgpkvIQiRkwa_Pgk6CUFmxYgs"),
            ),
            ctx,
        );
        let vault = CetusLpVault {
            id: object::new(ctx),
            treasury_cap,
            table: object_table::new(ctx),
        };
        transfer::share_object(vault);
        let deployer = tx_context::sender(ctx);
        transfer::public_transfer(metadata, deployer);
    }

    public fun deposit(
        vault: &mut CetusLpVault,
        position: CetusPosition,
        ctx: &mut TxContext,
    ): (CetusLpProof, Coin<BUCKETUS>) {
        let position_id = object::id(&position);
        let position_value = compute_value(&position);
        let proof = CetusLpProof {
            id: object::new(ctx),
            position_id,
            position_value,
        };
        event::emit(Deposit { position_id, position_value });
        object_table::add(&mut vault.table, position_id, position);
        let bucketus_coin = coin::mint(&mut vault.treasury_cap, position_value, ctx);
        (proof, bucketus_coin)
    }

    public fun withdraw(
        vault: &mut CetusLpVault,
        proof: CetusLpProof,
        bucketus_coin: Coin<BUCKETUS>,
    ): CetusPosition {
        let CetusLpProof {
            id, position_id, position_value,
        } = proof;
        object::delete(id);
        assert!(
            coin::value(&bucketus_coin) == position_value,
            ENotEnoughRepayment,
        );
        coin::burn(&mut vault.treasury_cap, bucketus_coin);
        event::emit(Withdraw { position_id, position_value });
        object_table::remove(&mut vault.table, position_id)
    }

    public fun compute_value(position: &CetusPosition): u64 {
        // check Pool ID
        let pool_id = object::id_to_address(&position::pool_id(position));
        assert!(
            pool_id == TARGET_CETUS_POOL_ID,
            EInvalidPositionPoolId,
        );
        // check tick range
        let tick_lower = i32::from_u32(MIN_TICK_LOWER);
        let tick_upper = i32::from_u32(MAX_TICK_UPPER);
        let (p_tick_lower, p_tick_upper) = position::tick_range(position);
        assert!(
            i32::eq(p_tick_lower, tick_lower) &&
            i32::eq(p_tick_upper, tick_upper),
            EInvalidPositionRange,
        );
        // compute the value of the Cetus Position
        let target_tick = i32::from_u32(TARGET_TICK);
        let position_liquidity = position::liquidity(position);
        let (buck_amount, usdc_amount) = pool::get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            target_tick,
            TARGET_SQRT_PRICE,
            position_liquidity,
            false,
        );
        buck_amount + usdc_amount * USDC_NORMALIZER
    }
}