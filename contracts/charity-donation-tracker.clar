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
        
        ;; Check for milestone achievements
        (try! (check-donor-milestones tx-sender))
        
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

;; === DONOR MILESTONE REWARDS SYSTEM ===
;; Independent feature for tracking donor achievements and special milestones

;; Milestone Constants
(define-constant ERR_MILESTONE_NOT_FOUND (err u408))
(define-constant ERR_MILESTONE_ALREADY_CLAIMED (err u409))
(define-constant ERR_MILESTONE_NOT_ACHIEVED (err u410))
(define-constant ERR_INVALID_MILESTONE_TYPE (err u411))

;; Milestone Types
(define-constant MILESTONE_FIRST_DONATION "FIRST_DONATION")
(define-constant MILESTONE_CONSECUTIVE_MONTHS "CONSECUTIVE_MONTHS")
(define-constant MILESTONE_TOTAL_AMOUNT "TOTAL_AMOUNT")
(define-constant MILESTONE_CHARITY_SUPPORTER "CHARITY_SUPPORTER")
(define-constant MILESTONE_COMMUNITY_BUILDER "COMMUNITY_BUILDER")

;; Milestone Data Variables
(define-data-var next-milestone-id uint u1)
(define-data-var total-milestones-achieved uint u0)

;; Milestone Definitions Map
(define-map milestone-definitions
    { milestone-id: uint }
    {
        title: (string-ascii 64),
        description: (string-ascii 256),
        milestone-type: (string-ascii 32),
        requirement-value: uint,
        reward-points: uint,
        is-active: bool,
        created-at: uint
    }
)

;; Donor Milestone Achievements Map
(define-map donor-milestones
    { donor: principal, milestone-id: uint }
    {
        achieved-at: uint,
        claimed-at: uint,
        reward-claimed: bool,
        achievement-value: uint
    }
)

;; Donor Milestone Progress Map
(define-map donor-milestone-progress
    { donor: principal }
    {
        total-milestones-achieved: uint,
        total-milestone-points: uint,
        consecutive-donation-months: uint,
        last-donation-month: uint,
        supported-charities-count: uint,
        community-referrals: uint
    }
)

;; Public Functions for Milestone System

;; Create a new milestone (owner only)
(define-public (create-milestone 
    (title (string-ascii 64)) 
    (description (string-ascii 256))
    (milestone-type (string-ascii 32))
    (requirement-value uint)
    (reward-points uint)
)
    (let ((milestone-id (var-get next-milestone-id)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> (len title) u0) ERR_INVALID_AMOUNT)
        (asserts! (> reward-points u0) ERR_INVALID_AMOUNT)
        (asserts! (is-valid-milestone-type milestone-type) ERR_INVALID_MILESTONE_TYPE)
        
        (map-set milestone-definitions
            { milestone-id: milestone-id }
            {
                title: title,
                description: description,
                milestone-type: milestone-type,
                requirement-value: requirement-value,
                reward-points: reward-points,
                is-active: true,
                created-at: block-height
            }
        )
        
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

;; Check and award milestones for a donor
(define-public (check-donor-milestones (donor principal))
    (let (
        (donor-profile (unwrap! (map-get? donor-profiles { donor: donor }) ERR_DONOR_NOT_FOUND))
        (milestone-progress (default-to 
            { total-milestones-achieved: u0, total-milestone-points: u0, consecutive-donation-months: u0, 
              last-donation-month: u0, supported-charities-count: u0, community-referrals: u0 }
            (map-get? donor-milestone-progress { donor: donor })
        ))
    )
        ;; Check for first donation milestone
        (unwrap-panic (check-first-donation-milestone donor donor-profile))
        
        ;; Check for total amount milestones
        (unwrap-panic (check-total-amount-milestones donor (get total-donated donor-profile)))
        
        ;; Update milestone progress
        (map-set donor-milestone-progress
            { donor: donor }
            milestone-progress
        )
        
        (ok true)
    )
)

;; Claim milestone reward
(define-public (claim-milestone-reward (milestone-id uint))
    (let (
        (milestone-def (unwrap! (map-get? milestone-definitions { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
        (achievement (unwrap! (map-get? donor-milestones { donor: tx-sender, milestone-id: milestone-id }) ERR_MILESTONE_NOT_ACHIEVED))
        (current-donor-profile (unwrap! (map-get? donor-profiles { donor: tx-sender }) ERR_DONOR_NOT_FOUND))
    )
        (asserts! (get is-active milestone-def) ERR_MILESTONE_NOT_FOUND)
        (asserts! (not (get reward-claimed achievement)) ERR_MILESTONE_ALREADY_CLAIMED)
        
        ;; Mark as claimed
        (map-set donor-milestones
            { donor: tx-sender, milestone-id: milestone-id }
            (merge achievement { claimed-at: block-height, reward-claimed: true })
        )
        
        ;; Add reward points to donor profile
        (map-set donor-profiles
            { donor: tx-sender }
            (merge current-donor-profile { 
                rewards-earned: (+ (get rewards-earned current-donor-profile) (get reward-points milestone-def))
            })
        )
        
        ;; Update reward pool
        (var-set reward-pool (+ (var-get reward-pool) (get reward-points milestone-def)))
        
        (ok (get reward-points milestone-def))
    )
)

;; Read-only functions for Milestone System

;; Get milestone definition
(define-read-only (get-milestone-definition (milestone-id uint))
    (map-get? milestone-definitions { milestone-id: milestone-id })
)

;; Get donor milestone achievement
(define-read-only (get-donor-milestone (donor principal) (milestone-id uint))
    (map-get? donor-milestones { donor: donor, milestone-id: milestone-id })
)

;; Get donor milestone progress
(define-read-only (get-donor-milestone-progress (donor principal))
    (map-get? donor-milestone-progress { donor: donor })
)

;; Get all achieved milestones for a donor
(define-read-only (get-donor-achieved-milestones (donor principal))
    (let ((progress (default-to 
            { total-milestones-achieved: u0, total-milestone-points: u0, consecutive-donation-months: u0, 
              last-donation-month: u0, supported-charities-count: u0, community-referrals: u0 }
            (map-get? donor-milestone-progress { donor: donor })
        )))
        progress
    )
)

;; Get milestone statistics
(define-read-only (get-milestone-stats)
    {
        total-milestones: (- (var-get next-milestone-id) u1),
        total-achievements: (var-get total-milestones-achieved)
    }
)

;; Private functions for Milestone System

;; Validate milestone type
(define-private (is-valid-milestone-type (milestone-type (string-ascii 32)))
    (or 
        (is-eq milestone-type MILESTONE_FIRST_DONATION)
        (or
            (is-eq milestone-type MILESTONE_CONSECUTIVE_MONTHS)
            (or
                (is-eq milestone-type MILESTONE_TOTAL_AMOUNT)
                (or
                    (is-eq milestone-type MILESTONE_CHARITY_SUPPORTER)
                    (is-eq milestone-type MILESTONE_COMMUNITY_BUILDER)
                )
            )
        )
    )
)

;; Check first donation milestone
(define-private (check-first-donation-milestone (donor principal) (donor-profile (tuple (total-donated uint) (donation-count uint) (tier (string-ascii 16)) (rewards-earned uint) (first-donation uint) (last-donation uint))))
    (if (and 
            (> (get donation-count donor-profile) u0)
            (is-none (map-get? donor-milestones { donor: donor, milestone-id: u1 }))
        )
        (begin
            (map-set donor-milestones
                { donor: donor, milestone-id: u1 }
                {
                    achieved-at: (get first-donation donor-profile),
                    claimed-at: u0,
                    reward-claimed: false,
                    achievement-value: u1
                }
            )
            (var-set total-milestones-achieved (+ (var-get total-milestones-achieved) u1))
            (ok true)
        )
        (ok true)
    )
)

;; Check total amount milestones
(define-private (check-total-amount-milestones (donor principal) (total-amount uint))
    (begin
        ;; Check 10 STX milestone (milestone-id: u2)
        (if (and (>= total-amount u10000000) (is-none (map-get? donor-milestones { donor: donor, milestone-id: u2 })))
            (begin
                (map-set donor-milestones
                    { donor: donor, milestone-id: u2 }
                    {
                        achieved-at: block-height,
                        claimed-at: u0,
                        reward-claimed: false,
                        achievement-value: total-amount
                    }
                )
                (var-set total-milestones-achieved (+ (var-get total-milestones-achieved) u1))
            )
            false
        )
        
        ;; Check 100 STX milestone (milestone-id: u3)
        (if (and (>= total-amount u100000000) (is-none (map-get? donor-milestones { donor: donor, milestone-id: u3 })))
            (begin
                (map-set donor-milestones
                    { donor: donor, milestone-id: u3 }
                    {
                        achieved-at: block-height,
                        claimed-at: u0,
                        reward-claimed: false,
                        achievement-value: total-amount
                    }
                )
                (var-set total-milestones-achieved (+ (var-get total-milestones-achieved) u1))
            )
            false
        )
        
        (ok true)
    )
)
