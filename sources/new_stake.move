module staking::stake_new{

    use aptos_framework::account::SignerCapability;
    use std::string::String;
    use aptos_std::simple_map::SimpleMap;
    use aptos_token::token::{TokenId, check_collection_exists};
    use std::signer::address_of;
    use aptos_framework::account;
    use std::vector;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;
    use aptos_token::token;
    use aptos_std::simple_map;
    use aptos_framework::resource_account;

    struct PoolCapability has key{
        pool_cap:SignerCapability
    }

   struct PoolInfo has key{
       creator: address,
       collection_name: String,
       start_sec:u64,
       end_sec:u64,
       reward_per_day:u64,
       reward_per_nft:u64,
       total_nft:u64
   }

    struct DepositState has key {
        deposit_info:SimpleMap<TokenId,u64>
    }

    const ERR_NOT_AUTHORIZED:u64 = 1;
    const ERR_INITIALIZED:u64 = 2;
    const ERR_START_SEC_WRONG:u64 = 3;
    const ERR_INVALID_REWARD:u64 = 4;
    const ERR_END_SEC_WRONG:u64 = 5;
    const SHOULD_STAKE_NFT:u64 =6;
    const ERR_NO_REWARDS:u64 = 7;
    const ERR_NO_COLLECTION:u64 =8;

    fun init_module (
        admin:&signer,
    ){
        let signer_cap = resource_account::retrieve_resource_account_cap(admin,  @module_owner);
        let pool_signer = account::create_signer_with_capability(&signer_cap);

        move_to(&pool_signer,PoolCapability{
            pool_cap:signer_cap
        });

    }

    public entry fun create_pool<X>(
        admin:&signer,
        start_sec:u64,
        end_sec:u64,
        dpr:u64,
        collection_name:vector<u8>,
    ) acquires PoolCapability{

        assert!(!exists<PoolInfo>(@staking),ERR_INITIALIZED);
        assert!(check_collection_exists(address_of(admin),string::utf8(collection_name)),ERR_NO_COLLECTION);
        let pool_cap = borrow_global<PoolCapability>(@staking);
        let pool_signer = account::create_signer_with_capability(&pool_cap.pool_cap);

        let signer_addr = address_of(&pool_signer);
        let now = timestamp::now_seconds();

        assert!(start_sec> now,ERR_START_SEC_WRONG);
        assert!(dpr>0,ERR_INVALID_REWARD);
        assert!(end_sec>start_sec,ERR_END_SEC_WRONG);

        move_to(&pool_signer,PoolInfo{
            creator:address_of(admin),
            collection_name:string::utf8(collection_name),
            start_sec,
            end_sec,
            reward_per_day:dpr,
            reward_per_nft:0,
            total_nft:0
        });

        if (coin::is_account_registered<X>(signer_addr)){
            managed_coin::register<X>(&pool_signer);
        };
        if (coin::is_account_registered<X>(signer_addr)){
            managed_coin::register<X>(admin);
        };
        coin::transfer<X>(admin,signer_addr,(end_sec - start_sec) * dpr / 86400);
    }

    public entry fun stake_token(
        staker:&signer,
        token_names:vector<vector<u8>>
    ) acquires PoolCapability, PoolInfo, DepositState {
        let staker_addr = address_of(staker);

        assert!(!exists<PoolInfo>(@staking),ERR_INITIALIZED);
        
        let pool_cap = borrow_global<PoolCapability>(@staking);
        let pool_signer = account::create_signer_with_capability(&pool_cap.pool_cap);

        let pool_addr = address_of(&pool_signer);

        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);
        assert!(pool_info.start_sec>0, ERR_START_SEC_WRONG);

        let nft_length = vector::length(&token_names);
        assert!(nft_length>0,SHOULD_STAKE_NFT);

        pool_info.total_nft = pool_info.total_nft + nft_length;

        let i:u64 =0;
        let acc_reward_per_nft = pool_info.reward_per_nft; // modify here
        if(exists<DepositState>(staker_addr)){
            let deposit_state = borrow_global_mut<DepositState>(staker_addr);
            while (i < nft_length){
                let token_name = vector::borrow<vector<u8>>(&token_names,i);
                let token_id = token::create_token_id_raw(
                    staker_addr,
                    pool_info.collection_name,
                    string::utf8(*token_name),
                   0
                );
                simple_map::add<TokenId,u64>(&mut deposit_state.deposit_info,token_id,acc_reward_per_nft);
                token::direct_transfer(staker,&pool_signer,token_id,1);
                i = i + 1;
            }
        }else{
            let deposit_info = simple_map::create<TokenId,u64>();
            while (i < nft_length){
                let token_name = vector::borrow<vector<u8>>(&token_names,i);
                let token_id = token::create_token_id_raw(
                    staker_addr,
                    pool_info.collection_name,
                    string::utf8(*token_name),
                    0
                );
                simple_map::add<TokenId,u64>(&mut deposit_info,token_id,acc_reward_per_nft);
                token::direct_transfer(staker,&pool_signer,token_id,1);
                i = i + 1;
            };
            move_to(staker,DepositState{
                deposit_info
            })
        }
    }

    public entry fun unstake<X>(
        sender:&signer,
        token_names:vector<vector<u8>>
    ) acquires PoolInfo,PoolCapability,DepositState{
        let sender_addr = address_of(sender);

        assert!(!exists<PoolInfo>(@staking),ERR_INITIALIZED);
        let pool_cap = borrow_global<PoolCapability>(@staking);
        let pool_signer = account::create_signer_with_capability(&pool_cap.pool_cap);

        let pool_addr = address_of(&pool_signer);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);

        let nft_length = vector::length(&token_names);
        assert!(nft_length>0,SHOULD_STAKE_NFT);

        pool_info.total_nft = pool_info.total_nft - nft_length;

        let to_claim:u64 =0;
        let i:u64 =0;
        let acc_reward_per_nft = pool_info.reward_per_nft; // modify here
        let deposit_state = borrow_global_mut<DepositState>(sender_addr);

        while (i < nft_length){
            let token_name = vector::borrow<vector<u8>>(&token_names,i);
            let token_id = token::create_token_id_raw(
                pool_info.creator,
                pool_info.collection_name,
                string::utf8(*token_name),
                0
            );
            assert!(simple_map::contains_key<TokenId,u64>(&deposit_state.deposit_info,&token_id),ERR_NOT_AUTHORIZED);
            let (_, lastReward) = simple_map::remove(&mut deposit_state.deposit_info,&token_id);
            to_claim = to_claim +(acc_reward_per_nft - lastReward) / 100000000;
            token::direct_transfer(&pool_signer,sender,token_id,1);
            i = i + 1;
        };

        if (to_claim>0){
            if (!coin::is_account_registered<X>(sender_addr)){
                coin::register<X>(sender);
            };
            coin::transfer<X>(&pool_signer,sender_addr,to_claim);
        }
    }

    public entry fun claim_reward<X>(
        sender:&signer,
        token_names:vector<vector<u8>>
    ) acquires PoolInfo,PoolCapability,DepositState {
        let sender_addr = address_of(sender);
        assert!(!exists<PoolInfo>(@staking),ERR_INITIALIZED);
        let pool_cap = borrow_global<PoolCapability>(@staking);
        let pool_signer = account::create_signer_with_capability(&pool_cap.pool_cap);

        let pool_addr = address_of(&pool_signer);
        let pool_info = borrow_global_mut<PoolInfo>(pool_addr);

        let nft_length = vector::length(&token_names);
        assert!(nft_length>0,SHOULD_STAKE_NFT);

        let claimable:u64 =0;
        let i:u64 =0;
        let acc_reward_per_nft = pool_info.reward_per_nft; // modify here
        let deposit_state = borrow_global_mut<DepositState>(sender_addr);

        while(i < nft_length){
            let token_name = vector::borrow<vector<u8>>(&token_names,i);
            let token_id = token::create_token_id_raw(
                pool_info.creator,
                pool_info.collection_name,
                string::utf8(*token_name),
                0
            );
            assert!(simple_map::contains_key<TokenId,u64>(&deposit_state.deposit_info,&token_id),ERR_NOT_AUTHORIZED);
            let lastreward = simple_map::borrow_mut<TokenId,u64>(&mut deposit_state.deposit_info,&token_id);

            let to_claim = (acc_reward_per_nft - *lastreward) / 100000000;
            *lastreward = acc_reward_per_nft;
            claimable = claimable + to_claim;
            i = i+1
        };

        assert!(claimable > 0,ERR_NO_REWARDS);
        if (!coin::is_account_registered<X>(sender_addr)){
            coin::register<X>(sender);
        };
        coin::transfer<X>(&pool_signer,sender_addr,claimable);
    }

    fun update(poolState:&mut PoolInfo){
        let now = timestamp::now_seconds();
        if (now > poolState.end_sec){
            now = poolState.end_sec
        };
        if (now < poolState.end_sec) return;

        if (poolState.total_nft == 0 ){
            poolState.start_sec = now;
            return
        };

        let reward: u64 = (((now-poolState.start_sec as u128) *(poolState.reward_per_day as u128) * (100000000 as u128)) / (100 as u128) as u64);
        poolState.total_nft = poolState.reward_per_nft + reward / poolState.total_nft;
        poolState.start_sec = now;
    }
}