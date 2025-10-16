import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Contract owner can register charities",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const owner = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'register-charity', [
        types.ascii("Red Cross"),
        types.ascii("International humanitarian organization"),
        types.principal(wallet1.address)
      ], owner.address)
    ]);
    
    block.receipts[0].result.expectOk().expectUint(1);
  },
});

Clarinet.test({
  name: "Users can make donations to registered charities",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const owner = accounts.get('deployer')!;
    const donor = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity first
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'register-charity', [
        types.ascii("UNICEF"),
        types.ascii("Children's fund"),
        types.principal(charity_wallet.address)
      ], owner.address)
    ]);
    
    // Make donation
    block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'donate', [
        types.uint(1),
        types.uint(5000000), // 5 STX
        types.ascii("Great cause!"),
        types.bool(false)
      ], donor.address)
    ]);
    
    block.receipts[0].result.expectOk().expectUint(1);
  },
});

Clarinet.test({
  name: "Donor profiles are created and updated correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const owner = accounts.get('deployer')!;
    const donor = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'register-charity', [
        types.ascii("Save the Children"),
        types.ascii("Child welfare organization"),
        types.principal(charity_wallet.address)
      ], owner.address)
    ]);
    
    // Make donation
    block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'donate', [
        types.uint(1),
        types.uint(2000000), // 2 STX (Bronze tier)
        types.ascii("For the children"),
        types.bool(false)
      ], donor.address)
    ]);
    
    // Check donor profile
    const profile = chain.callReadOnlyFn('charity-donation-tracker', 'get-donor-profile', 
      [types.principal(donor.address)], owner.address);
    
    const profileData = profile.result.expectSome().expectTuple();
    assertEquals(profileData['total-donated'], types.uint(2000000));
    assertEquals(profileData['donation-count'], types.uint(1));
    assertEquals(profileData['tier'], types.ascii("BRONZE"));
  },
});

Clarinet.test({
  name: "Global stats are tracked correctly",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const owner = accounts.get('deployer')!;
    const donor1 = accounts.get('wallet_1')!;
    const donor2 = accounts.get('wallet_2')!;
    const charity_wallet = accounts.get('wallet_3')!;
    
    // Register charity
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'register-charity', [
        types.ascii("Doctors Without Borders"),
        types.ascii("Medical humanitarian organization"),
        types.principal(charity_wallet.address)
      ], owner.address)
    ]);
    
    // Make multiple donations
    block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'donate', [
        types.uint(1),
        types.uint(1000000),
        types.ascii("Great work!"),
        types.bool(false)
      ], donor1.address),
      Tx.contractCall('charity-donation-tracker', 'donate', [
        types.uint(1),
        types.uint(3000000),
        types.ascii("Keep it up!"),
        types.bool(true)
      ], donor2.address)
    ]);
    
    // Check global stats
    const stats = chain.callReadOnlyFn('charity-donation-tracker', 'get-global-stats', 
      [], owner.address);
    
    const statsData = stats.result.expectTuple();
    assertEquals(statsData['total-donated'], types.uint(4000000));
    assertEquals(statsData['total-donations'], types.uint(2));
    assertEquals(statsData['total-charities'], types.uint(1));
  },
});

Clarinet.test({
  name: "Cannot donate to non-existent charity",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const donor = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'donate', [
        types.uint(999), // Non-existent charity
        types.uint(1000000),
        types.ascii("Test donation"),
        types.bool(false)
      ], donor.address)
    ]);
    
    block.receipts[0].result.expectErr(types.uint(403)); // ERR_CHARITY_NOT_FOUND
  },
});

Clarinet.test({
  name: "Only owner can deactivate charities",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const owner = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity
    let block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'register-charity', [
        types.ascii("Test Charity"),
        types.ascii("Test description"),
        types.principal(charity_wallet.address)
      ], owner.address)
    ]);
    
    // Try to deactivate as non-owner (should fail)
    block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'deactivate-charity', [
        types.uint(1)
      ], user.address)
    ]);
    
    block.receipts[0].result.expectErr(types.uint(401)); // ERR_NOT_AUTHORIZED
    
    // Deactivate as owner (should succeed)
    block = chain.mineBlock([
      Tx.contractCall('charity-donation-tracker', 'deactivate-charity', [
        types.uint(1)
      ], owner.address)
    ]);
    
    block.receipts[0].result.expectOk(types.bool(true));
  },
});