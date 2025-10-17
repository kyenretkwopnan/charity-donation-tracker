;; Simple validation test for charity donation tracker contract

;; Test 1: Basic contract deployment check
(contract-call? .charity-donation-tracker get-global-stats)

;; Test 2: Register charity function exists
(contract-call? .charity-donation-tracker register-charity "Test Charity" "Test Description" 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Test 3: Donation function exists  
(contract-call? .charity-donation-tracker donate u1 u1000000 "Test donation" false)
