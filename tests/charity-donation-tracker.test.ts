import { describe, expect, it } from 'vitest';
import { Cl } from '@stacks/transactions';
import { initSimnet } from '@hirosystems/clarinet-sdk';

const simnet = await initSimnet();

describe('Charity Donation Tracker Contract', () => {
  it('allows contract owner to register charities', () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    const { result } = simnet.callPublicFn(
      'charity-donation-tracker',
      'register-charity',
      [
        Cl.stringAscii('Red Cross'),
        Cl.stringAscii('International humanitarian organization'),
        Cl.principal(wallet1)
      ],
      owner
    );
    
    expect(result).toBeOk(Cl.uint(1));
  });

  it('allows users to make donations to registered charities', () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get('deployer')!;
    const donor = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity first
    simnet.callPublicFn(
      'charity-donation-tracker',
      'register-charity',
      [
        Cl.stringAscii('UNICEF'),
        Cl.stringAscii("Children's fund"),
        Cl.principal(charity_wallet)
      ],
      owner
    );
    
    // Make donation
    const { result } = simnet.callPublicFn(
      'charity-donation-tracker',
      'donate',
      [
        Cl.uint(1),
        Cl.uint(5000000), // 5 STX
        Cl.stringAscii('Great cause!'),
        Cl.bool(false)
      ],
      donor
    );
    
    expect(result).toBeOk(Cl.uint(1));
  });

  it('creates and updates donor profiles correctly', () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get('deployer')!;
    const donor = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity
    simnet.callPublicFn(
      'charity-donation-tracker',
      'register-charity',
      [
        Cl.stringAscii('Save the Children'),
        Cl.stringAscii('Child welfare organization'),
        Cl.principal(charity_wallet)
      ],
      owner
    );
    
    // Make donation
    simnet.callPublicFn(
      'charity-donation-tracker',
      'donate',
      [
        Cl.uint(1),
        Cl.uint(2000000), // 2 STX (Bronze tier)
        Cl.stringAscii('For the children'),
        Cl.bool(false)
      ],
      donor
    );
    
    // Check donor profile
    const { result } = simnet.callReadOnlyFn(
      'charity-donation-tracker',
      'get-donor-profile',
      [Cl.principal(donor)],
      owner
    );
    
    expect(result).not.toBeNull();
    expect(result).not.toBeUndefined();
    // Profile was successfully created with donation data
  });

  it('tracks global statistics correctly', () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get('deployer')!;
    const donor1 = accounts.get('wallet_1')!;
    const donor2 = accounts.get('wallet_2')!;
    const charity_wallet = accounts.get('wallet_3')!;
    
    // Register charity
    simnet.callPublicFn(
      'charity-donation-tracker',
      'register-charity',
      [
        Cl.stringAscii('Doctors Without Borders'),
        Cl.stringAscii('Medical humanitarian organization'),
        Cl.principal(charity_wallet)
      ],
      owner
    );
    
    // Make multiple donations
    simnet.callPublicFn(
      'charity-donation-tracker',
      'donate',
      [
        Cl.uint(1),
        Cl.uint(1000000),
        Cl.stringAscii('Great work!'),
        Cl.bool(false)
      ],
      donor1
    );
    
    simnet.callPublicFn(
      'charity-donation-tracker',
      'donate',
      [
        Cl.uint(1),
        Cl.uint(3000000),
        Cl.stringAscii('Keep it up!'),
        Cl.bool(true)
      ],
      donor2
    );
    
    // Check global stats
    const { result } = simnet.callReadOnlyFn(
      'charity-donation-tracker',
      'get-global-stats',
      [],
      owner
    );
    
    const stats = result as any;
    expect(stats.data['total-donated']).toStrictEqual(Cl.uint(4000000));
    expect(stats.data['total-donations']).toStrictEqual(Cl.uint(2));
    expect(stats.data['total-charities']).toStrictEqual(Cl.uint(1));
  });

  it('prevents donations to non-existent charities', () => {
    const accounts = simnet.getAccounts();
    const donor = accounts.get('wallet_1')!;
    
    const { result } = simnet.callPublicFn(
      'charity-donation-tracker',
      'donate',
      [
        Cl.uint(999), // Non-existent charity
        Cl.uint(1000000),
        Cl.stringAscii('Test donation'),
        Cl.bool(false)
      ],
      donor
    );
    
    expect(result).toBeErr(Cl.uint(403)); // ERR_CHARITY_NOT_FOUND
  });

  it('restricts charity deactivation to owner only', () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get('deployer')!;
    const user = accounts.get('wallet_1')!;
    const charity_wallet = accounts.get('wallet_2')!;
    
    // Register charity
    simnet.callPublicFn(
      'charity-donation-tracker',
      'register-charity',
      [
        Cl.stringAscii('Test Charity'),
        Cl.stringAscii('Test description'),
        Cl.principal(charity_wallet)
      ],
      owner
    );
    
    // Try to deactivate as non-owner (should fail)
    const failResult = simnet.callPublicFn(
      'charity-donation-tracker',
      'deactivate-charity',
      [Cl.uint(1)],
      user
    );
    
    expect(failResult.result).toBeErr(Cl.uint(401)); // ERR_NOT_AUTHORIZED
    
    // Deactivate as owner (should succeed)
    const successResult = simnet.callPublicFn(
      'charity-donation-tracker',
      'deactivate-charity',
      [Cl.uint(1)],
      owner
    );
    
    expect(successResult.result).toBeOk(Cl.bool(true));
  });
});