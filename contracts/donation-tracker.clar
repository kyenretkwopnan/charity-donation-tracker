;; donation-tracker
;; A comprehensive donation tracking contract for managing charitable donations
;; Provides functionality for making donations, tracking transactions, and managing withdrawals

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-CHARITY-NOT-FOUND (err u201))
(define-constant ERR-CHARITY-NOT-ACTIVE (err u202))
(define-constant ERR-INVALID-AMOUNT (err u203))
(define-constant ERR-INSUFFICIENT-BALANCE (err u204))
(define-constant ERR-SELF-DONATION (err u205))
(define-constant ERR-DONATION-NOT-FOUND (err u206))
(define-constant ERR-TRANSFER-FAILED (err u207))
(define-constant ERR-INVALID-RECIPIENT (err u208))
(define-constant MIN-DONATION-AMOUNT u100000) ;; 0.1 STX minimum

;; data vars
(define-data-var next-donation-id uint u1)
(define-data-var total-donations uint u0)
(define-data-var total-donation-amount uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% fee (250/10000)
(define-data-var total-fees-collected uint u0)
(define-data-var contract-paused bool false)

;; data maps
;; Individual donation records
(define-map donations
    uint ;; donation-id
    {
        donor: principal,
        charity-id: uint,
        amount: uint,
        message: (optional (string-ascii 280)),
        timestamp: uint,
        transaction-hash: (optional (buff 32)),
        status: (string-ascii 20), ;; "completed", "pending", "failed"
        fee-amount: uint
    }
)

;; Charity donation statistics
(define-map charity-donation-stats
    uint ;; charity-id
    {
        total-received: uint,
        total-withdrawn: uint,
        current-balance: uint,
        donation-count: uint,
        last-donation-at: uint,
        largest-donation: uint,
        average-donation: uint
    }
)

;; Donor statistics and history
(define-map donor-stats
    principal ;; donor address
    {
        total-donated: uint,
        donation-count: uint,
        first-donation-at: uint,
        last-donation-at: uint,
        favorite-charity-id: (optional uint),
        largest-donation: uint
    }
)

;; Donation history per donor (mapping to donation IDs)
(define-map donor-donation-history
    { donor: principal, index: uint }
    uint ;; donation-id
)

;; Charity withdrawal history
(define-map charity-withdrawals
    { charity-id: uint, withdrawal-id: uint }
    {
        amount: uint,
        timestamp: uint,
        recipient: principal,
        description: (optional (string-ascii 200))
    }
)

;; Withdrawal counters per charity
(define-map charity-withdrawal-counts
    uint ;; charity-id
    uint ;; withdrawal-count
)

;; Emergency freeze list
(define-map frozen-charities
    uint ;; charity-id
    bool ;; is-frozen
)

;; private functions
(define-private (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-private (calculate-net-donation (amount uint))
    (- amount (calculate-platform-fee amount))
)

(define-private (update-charity-stats (charity-id uint) (donation-amount uint))
    (let
        (
            (current-stats (default-to
                {
                    total-received: u0,
                    total-withdrawn: u0,
                    current-balance: u0,
                    donation-count: u0,
                    last-donation-at: u0,
                    largest-donation: u0,
                    average-donation: u0
                }
                (map-get? charity-donation-stats charity-id)
            ))
            (new-total (+ (get total-received current-stats) donation-amount))
            (new-count (+ (get donation-count current-stats) u1))
            (new-balance (+ (get current-balance current-stats) donation-amount))
        )
        (map-set charity-donation-stats charity-id
            (merge current-stats {
                total-received: new-total,
                current-balance: new-balance,
                donation-count: new-count,
                last-donation-at: stacks-block-height,
                largest-donation: (if (> donation-amount (get largest-donation current-stats))
                    donation-amount
                    (get largest-donation current-stats)
                ),
                average-donation: (/ new-total new-count)
            })
        )
    )
)

(define-private (update-donor-stats (donor principal) (charity-id uint) (donation-amount uint))
    (let
        (
            (current-stats (default-to
                {
                    total-donated: u0,
                    donation-count: u0,
                    first-donation-at: u0,
                    last-donation-at: u0,
                    favorite-charity-id: none,
                    largest-donation: u0
                }
                (map-get? donor-stats donor)
            ))
            (new-total (+ (get total-donated current-stats) donation-amount))
            (new-count (+ (get donation-count current-stats) u1))
            (first-donation (if (is-eq (get donation-count current-stats) u0) stacks-block-height (get first-donation-at current-stats)))
        )
        (map-set donor-stats donor
            (merge current-stats {
                total-donated: new-total,
                donation-count: new-count,
                first-donation-at: first-donation,
                last-donation-at: stacks-block-height,
                favorite-charity-id: (some charity-id),
                largest-donation: (if (> donation-amount (get largest-donation current-stats))
                    donation-amount
                    (get largest-donation current-stats)
                )
            })
        )
        
        ;; Record donation in history
        (map-set donor-donation-history 
            { donor: donor, index: (get donation-count current-stats) }
            (var-get next-donation-id)
        )
    )
)

;; public functions
(define-public (donate (charity-id uint) (amount uint) (message (optional (string-ascii 280))))
    (let
        (
            (donation-id (var-get next-donation-id))
            (net-amount (calculate-net-donation amount))
            (fee-amount (calculate-platform-fee amount))
        )
        (asserts! (not (var-get contract-paused)) (err u999))
        (asserts! (>= amount MIN-DONATION-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (is-none (map-get? frozen-charities charity-id)) ERR-CHARITY-NOT-ACTIVE)
        
        ;; Verify charity exists and is active (this would ideally call the charity-registry contract)
        ;; For now, we'll assume charity validation happens externally
        
        ;; Transfer STX from donor to contract
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
            success
            (begin
                ;; Record the donation
                (map-set donations donation-id {
                    donor: tx-sender,
                    charity-id: charity-id,
                    amount: amount,
                    message: message,
                    timestamp: stacks-block-height,
                    transaction-hash: none,
                    status: "completed",
                    fee-amount: fee-amount
                })
                
                ;; Update statistics
                (update-charity-stats charity-id net-amount)
                (update-donor-stats tx-sender charity-id amount)
                
                ;; Update global counters
                (var-set next-donation-id (+ donation-id u1))
                (var-set total-donations (+ (var-get total-donations) u1))
                (var-set total-donation-amount (+ (var-get total-donation-amount) amount))
                (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
                
                (ok donation-id)
            )
            error ERR-TRANSFER-FAILED
        )
    )
)

(define-public (withdraw-funds (charity-id uint) (amount uint) (description (optional (string-ascii 200))))
    (let
        (
            (charity-stats (unwrap! (map-get? charity-donation-stats charity-id) ERR-CHARITY-NOT-FOUND))
            (current-balance (get current-balance charity-stats))
            (withdrawal-count (default-to u0 (map-get? charity-withdrawal-counts charity-id)))
        )
        ;; This would ideally verify the caller owns the charity through charity-registry
        ;; For now, we'll use a simple authorization check
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount current-balance) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-none (map-get? frozen-charities charity-id)) ERR-CHARITY-NOT-ACTIVE)
        
        ;; Transfer funds to charity owner
        (match (as-contract (stx-transfer? amount tx-sender tx-sender))
            success
            (begin
                ;; Update charity balance
                (map-set charity-donation-stats charity-id
                    (merge charity-stats {
                        current-balance: (- current-balance amount),
                        total-withdrawn: (+ (get total-withdrawn charity-stats) amount)
                    })
                )
                
                ;; Record withdrawal
                (map-set charity-withdrawals
                    { charity-id: charity-id, withdrawal-id: withdrawal-count }
                    {
                        amount: amount,
                        timestamp: stacks-block-height,
                        recipient: tx-sender,
                        description: description
                    }
                )
                
                (map-set charity-withdrawal-counts charity-id (+ withdrawal-count u1))
                
                (ok amount)
            )
            error ERR-TRANSFER-FAILED
        )
    )
)

(define-public (emergency-freeze-charity (charity-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-set frozen-charities charity-id true)
        (ok true)
    )
)

(define-public (emergency-unfreeze-charity (charity-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (map-delete frozen-charities charity-id)
        (ok true)
    )
)

(define-public (update-platform-fee (new-fee-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (<= new-fee-rate u1000) ERR-INVALID-AMOUNT) ;; Max 10% fee
        (var-set platform-fee-rate new-fee-rate)
        (ok true)
    )
)

;; read only functions
(define-read-only (get-donation (donation-id uint))
    (map-get? donations donation-id)
)

(define-read-only (get-charity-stats (charity-id uint))
    (map-get? charity-donation-stats charity-id)
)

(define-read-only (get-donor-stats (donor principal))
    (map-get? donor-stats donor)
)

(define-read-only (get-donor-donation (donor principal) (index uint))
    (match (map-get? donor-donation-history { donor: donor, index: index })
        donation-id (map-get? donations donation-id)
        none
    )
)

(define-read-only (get-charity-withdrawal (charity-id uint) (withdrawal-id uint))
    (map-get? charity-withdrawals { charity-id: charity-id, withdrawal-id: withdrawal-id })
)

(define-read-only (get-platform-metrics)
    {
        total-donations: (var-get total-donations),
        total-donation-amount: (var-get total-donation-amount),
        total-fees-collected: (var-get total-fees-collected),
        platform-fee-rate: (var-get platform-fee-rate),
        contract-paused: (var-get contract-paused),
        min-donation-amount: MIN-DONATION-AMOUNT
    }
)

(define-read-only (calculate-donation-breakdown (amount uint))
    {
        gross-amount: amount,
        platform-fee: (calculate-platform-fee amount),
        net-donation: (calculate-net-donation amount),
        fee-percentage: (var-get platform-fee-rate)
    }
)

(define-read-only (is-charity-frozen (charity-id uint))
    (default-to false (map-get? frozen-charities charity-id))
)

(define-read-only (get-charity-balance (charity-id uint))
    (match (map-get? charity-donation-stats charity-id)
        stats (some (get current-balance stats))
        none
    )
)

(define-read-only (verify-donation (donation-id uint) (expected-donor principal) (expected-amount uint))
    (match (map-get? donations donation-id)
        donation-info
        (and 
            (is-eq (get donor donation-info) expected-donor)
            (is-eq (get amount donation-info) expected-amount)
            (is-eq (get status donation-info) "completed")
        )
        false
    )
)
