;; Charity Donation Tracker Smart Contract
;; Tracks donations, manages donor profiles, and implements reward system

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u402))
(define-constant ERR_CHARITY_NOT_FOUND (err u403))
(define-constant ERR_DONOR_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_BALANCE (err u405))
(define-constant ERR_ALREADY_EXISTS (err u406))
(define-constant ERR_INVALID_TIER (err u407))

;; Data Variables
(define-data-var next-charity-id uint u1)
(define-data-var next-donation-id uint u1)
(define-data-var total-donated uint u0)
(define-data-var reward-pool uint u0)

;; Data Maps
(define-map charities 
    { charity-id: uint }
    { 
        name: (string-ascii 64),
        description: (string-ascii 256),
        wallet: principal,
        total-received: uint,
        is-active: bool,
        created-at: uint
    }
)

(define-map donations
    { donation-id: uint }
    {
        donor: principal,
        charity-id: uint,
        amount: uint,
        message: (string-ascii 128),
        timestamp: uint,
        is-anonymous: bool
    }
)

(define-map donor-profiles
    { donor: principal }
    {
        total-donated: uint,
        donation-count: uint,
        tier: (string-ascii 16),
        rewards-earned: uint,
        first-donation: uint,
        last-donation: uint
    }
)

(define-map charity-donors
    { charity-id: uint, donor: principal }
    { total-donated: uint, donation-count: uint }
)

;; Donor tier thresholds (in microSTX)
(define-constant BRONZE_THRESHOLD u1000000)    ;; 1 STX
(define-constant SILVER_THRESHOLD u10000000)   ;; 10 STX  
(define-constant GOLD_THRESHOLD u50000000)     ;; 50 STX
(define-constant PLATINUM_THRESHOLD u100000000) ;; 100 STX

;; Public Functions

;; Register a new charity
(define-public (register-charity (name (string-ascii 64)) (description (string-ascii 256)) (wallet principal))
    (let ((charity-id (var-get next-charity-id)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
        
        (map-set charities 
            { charity-id: charity-id }
            {
                name: name,
                description: description,
                wallet: wallet,
                total-received: u0,
                is-active: true,
                created-at: block-height
            }
        )
        
        (var-set next-charity-id (+ charity-id u1))
        (ok charity-id)
    )
)

;; Make a donation to a charity
(define-public (donate (charity-id uint) (amount uint) (message (string-ascii 128)) (is-anonymous bool))
    (let (
        (donation-id (var-get next-donation-id))
        (charity-info (unwrap! (map-get? charities { charity-id: charity-id }) ERR_CHARITY_NOT_FOUND))
        (current-donor-profile (default-to 
            { total-donated: u0, donation-count: u0, tier: "NONE", rewards-earned: u0, first-donation: u0, last-donation: u0 }
            (map-get? donor-profiles { donor: tx-sender })
        ))
        (charity-donor-info (default-to 
            { total-donated: u0, donation-count: u0 }
            (map-get? charity-donors { charity-id: charity-id, donor: tx-sender })
        ))
        (new-total-donated (+ (get total-donated current-donor-profile) amount))
        (new-tier (calculate-tier new-total-donated))
        (reward-amount (calculate-reward-points amount))
    )
        (asserts! (get is-active charity-info) ERR_CHARITY_NOT_FOUND)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Transfer STX to charity wallet
        (try! (stx-transfer? amount tx-sender (get wallet charity-info)))
        
        ;; Record donation
        (map-set donations
            { donation-id: donation-id }
            {
                donor: tx-sender,
                charity-id: charity-id,
                amount: amount,
                message: message,
                timestamp: block-height,
                is-anonymous: is-anonymous
            }
        )
        
        ;; Update charity totals
        (map-set charities
            { charity-id: charity-id }
            (merge charity-info { total-received: (+ (get total-received charity-info) amount) })
        )
        
        ;; Update donor profile
        (map-set donor-profiles
            { donor: tx-sender }
            {
                total-donated: new-total-donated,
                donation-count: (+ (get donation-count current-donor-profile) u1),
                tier: new-tier,
                rewards-earned: (+ (get rewards-earned current-donor-profile) reward-amount),
                first-donation: (if (is-eq (get first-donation current-donor-profile) u0) block-height (get first-donation current-donor-profile)),
                last-donation: block-height
            }
        )
        
        ;; Update charity-specific donor stats
        (map-set charity-donors
            { charity-id: charity-id, donor: tx-sender }
            {
                total-donated: (+ (get total-donated charity-donor-info) amount),
                donation-count: (+ (get donation-count charity-donor-info) u1)
            }
        )
        
        ;; Update global stats
        (var-set next-donation-id (+ donation-id u1))
        (var-set total-donated (+ (var-get total-donated) amount))
        (var-set reward-pool (+ (var-get reward-pool) reward-amount))
        
        (ok donation-id)
    )
)

;; Deactivate a charity (only owner)
(define-public (deactivate-charity (charity-id uint))
    (let ((charity-info (unwrap! (map-get? charities { charity-id: charity-id }) ERR_CHARITY_NOT_FOUND)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
        (map-set charities
            { charity-id: charity-id }
            (merge charity-info { is-active: false })
        )
        (ok true)
    )
)

;; Read-only functions

;; Get charity information
(define-read-only (get-charity-info (charity-id uint))
    (map-get? charities { charity-id: charity-id })
)

;; Get donation information
(define-read-only (get-donation-info (donation-id uint))
    (map-get? donations { donation-id: donation-id })
)

;; Get donor profile
(define-read-only (get-donor-profile (donor principal))
    (map-get? donor-profiles { donor: donor })
)

;; Get donor stats for specific charity
(define-read-only (get-charity-donor-stats (charity-id uint) (donor principal))
    (map-get? charity-donors { charity-id: charity-id, donor: donor })
)

;; Get global statistics
(define-read-only (get-global-stats)
    {
        total-donated: (var-get total-donated),
        total-donations: (- (var-get next-donation-id) u1),
        total-charities: (- (var-get next-charity-id) u1),
        reward-pool: (var-get reward-pool)
    }
)

;; Private functions

;; Calculate donor tier based on total donations
(define-private (calculate-tier (total-amount uint))
    (if (>= total-amount PLATINUM_THRESHOLD)
        "PLATINUM"
        (if (>= total-amount GOLD_THRESHOLD)
            "GOLD"
            (if (>= total-amount SILVER_THRESHOLD)
                "SILVER"
                (if (>= total-amount BRONZE_THRESHOLD)
                    "BRONZE"
                    "NONE"
                )
            )
        )
    )
)

;; Calculate reward points (1% of donation amount)
(define-private (calculate-reward-points (amount uint))
    (/ amount u100)
)

;; Get tier multiplier for rewards
(define-private (get-tier-multiplier (tier (string-ascii 16)))
    (if (is-eq tier "PLATINUM")
        u150  ;; 1.5x multiplier
        (if (is-eq tier "GOLD")
            u125  ;; 1.25x multiplier
            (if (is-eq tier "SILVER")
                u110  ;; 1.1x multiplier
                u100  ;; 1x multiplier (bronze and none)
            )
        )
    )
)