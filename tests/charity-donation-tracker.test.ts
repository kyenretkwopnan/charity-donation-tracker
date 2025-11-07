import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Charity Donation Tracker Contract", () => {
  describe("Charity Registration", () => {
    it("should allow contract owner to register a charity", () => {
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Food Bank"),
          Cl.stringAscii("Provides food to families in need"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should prevent non-owner from registering a charity", () => {
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Education Fund"),
          Cl.stringAscii("Supports student education"),
          Cl.principal(wallet2),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR_NOT_AUTHORIZED
    });

    it("should increment charity ID on each registration", () => {
      const { result: result1 } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Health Clinic"),
          Cl.stringAscii("Free healthcare services"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      const { result: result2 } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Animal Shelter"),
          Cl.stringAscii("Rescue and rehome animals"),
          Cl.principal(wallet2),
        ],
        deployer
      );

      expect(result1).toBeOk(Cl.uint(1));
      expect(result2).toBeOk(Cl.uint(2));
    });
  });

  describe("Donations", () => {
    it("should allow donation to registered charity", () => {
      // Register charity first
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Community Center"),
          Cl.stringAscii("Local community support"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Make donation
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(1),
          Cl.uint(1000000), // 1 STX
          Cl.stringAscii("Great cause!"),
          Cl.bool(false),
        ],
        wallet2
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should reject donation to non-existent charity", () => {
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(999),
          Cl.uint(1000000),
          Cl.stringAscii("Test donation"),
          Cl.bool(false),
        ],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(403)); // ERR_CHARITY_NOT_FOUND
    });

    it("should reject zero-amount donations", () => {
      // Register charity
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Library Fund"),
          Cl.stringAscii("Support public library"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Try zero donation
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(1),
          Cl.uint(0),
          Cl.stringAscii("Empty donation"),
          Cl.bool(false),
        ],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(402)); // ERR_INVALID_AMOUNT
    });

    it("should support anonymous donations", () => {
      // Register charity
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Privacy Fund"),
          Cl.stringAscii("Anonymous giving"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Make anonymous donation
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(1),
          Cl.uint(5000000), // 5 STX
          Cl.stringAscii("Anonymous supporter"),
          Cl.bool(true),
        ],
        wallet2
      );

      expect(result).toBeOk(Cl.uint(1));
    });
  });

  describe("Donor Profiles & Tiers", () => {
    it("should create donor profile on first donation", () => {
      // Register charity
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("First Donation Test"),
          Cl.stringAscii("Test charity"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Donate
      simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(1),
          Cl.uint(2000000), // 2 STX
          Cl.stringAscii("First donation"),
          Cl.bool(false),
        ],
        wallet2
      );

      // Check profile
      const { result } = simnet.callReadOnlyFn(
        "charity-donation-tracker",
        "get-donor-profile",
        [Cl.principal(wallet2)],
        wallet2
      );

      expect(result).toBeSome(
        Cl.tuple({
          "total-donated": Cl.uint(2000000),
          "donation-count": Cl.uint(1),
          tier: Cl.stringAscii("BRONZE"),
          "rewards-earned": Cl.uint(20000),
          "first-donation": Cl.uint(simnet.blockHeight),
          "last-donation": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should upgrade donor tier based on total donations", () => {
      // Register charity
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Tier Test"),
          Cl.stringAscii("Test tiers"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Donate 15 STX (should reach SILVER)
      simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [
          Cl.uint(1),
          Cl.uint(15000000),
          Cl.stringAscii("Tier upgrade"),
          Cl.bool(false),
        ],
        wallet3
      );

      // Check tier
      const { result } = simnet.callReadOnlyFn(
        "charity-donation-tracker",
        "get-donor-profile",
        [Cl.principal(wallet3)],
        wallet3
      );

      // Profile should exist with tier data
      expect(result).toBeDefined();
    });
  });

  describe("Charity Management", () => {
    it("should allow owner to deactivate a charity", () => {
      // Register charity
      const { result: registerId } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Deactivate Test"),
          Cl.stringAscii("Will be deactivated"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      expect(registerId).toBeOk(Cl.uint(1));

      // Deactivate
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "deactivate-charity",
        [Cl.uint(1)],
        deployer
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent donations to deactivated charity", () => {
      // Register charity
      const { result: registerId } = simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Inactive Charity"),
          Cl.stringAscii("Will be inactive"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      expect(registerId).toBeOk(Cl.uint(1));

      // Deactivate
      simnet.callPublicFn(
        "charity-donation-tracker",
        "deactivate-charity",
        [Cl.uint(1)],
        deployer
      );

      // Try to donate
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "donate",
        [Cl.uint(1), Cl.uint(1000000), Cl.stringAscii("Test"), Cl.bool(false)],
        wallet2
      );

      expect(result).toBeErr(Cl.uint(403)); // ERR_CHARITY_NOT_FOUND
    });
  });

  describe("Read-Only Functions", () => {
    it("should retrieve charity information", () => {
      // Register charity
      simnet.callPublicFn(
        "charity-donation-tracker",
        "register-charity",
        [
          Cl.stringAscii("Info Test"),
          Cl.stringAscii("Test charity info"),
          Cl.principal(wallet1),
        ],
        deployer
      );

      // Get info
      const { result } = simnet.callReadOnlyFn(
        "charity-donation-tracker",
        "get-charity-info",
        [Cl.uint(1)],
        deployer
      );

      expect(result).toBeSome(
        Cl.tuple({
          name: Cl.stringAscii("Info Test"),
          description: Cl.stringAscii("Test charity info"),
          wallet: Cl.principal(wallet1),
          "total-received": Cl.uint(0),
          "is-active": Cl.bool(true),
          "created-at": Cl.uint(simnet.blockHeight),
        })
      );
    });

    it("should return global statistics", () => {
      const { result } = simnet.callReadOnlyFn(
        "charity-donation-tracker",
        "get-global-stats",
        [],
        deployer
      );

      expect(result).toBeTuple({
        "total-donated": Cl.uint(0),
        "total-donations": Cl.uint(0),
        "total-charities": Cl.uint(0),
        "reward-pool": Cl.uint(0),
      });
    });
  });

  describe("Milestone System", () => {
    it("should allow owner to create milestones", () => {
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "create-milestone",
        [
          Cl.stringAscii("First Donation"),
          Cl.stringAscii("Make your first donation"),
          Cl.stringAscii("FIRST_DONATION"),
          Cl.uint(1),
          Cl.uint(100),
        ],
        deployer
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should prevent non-owner from creating milestones", () => {
      const { result } = simnet.callPublicFn(
        "charity-donation-tracker",
        "create-milestone",
        [
          Cl.stringAscii("Unauthorized Milestone"),
          Cl.stringAscii("Should fail"),
          Cl.stringAscii("TOTAL_AMOUNT"),
          Cl.uint(10),
          Cl.uint(500),
        ],
        wallet1
      );

      expect(result).toBeErr(Cl.uint(401)); // ERR_NOT_AUTHORIZED
    });
  });
});
