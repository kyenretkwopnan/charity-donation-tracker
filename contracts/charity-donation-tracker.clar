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
        created-at: uint,
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
        is-anonymous: bool,
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
        last-donation: uint,
    }
)

(define-map charity-donors
    {
        charity-id: uint,
        donor: principal,
    }
    {
        total-donated: uint,
        donation-count: uint,
    }
)

;; Donor tier thresholds (in microSTX)
(define-constant BRONZE_THRESHOLD u1000000) ;; 1 STX
(define-constant SILVER_THRESHOLD u10000000) ;; 10 STX  
(define-constant GOLD_THRESHOLD u50000000) ;; 50 STX
(define-constant PLATINUM_THRESHOLD u100000000) ;; 100 STX

;; Public Functions

;; Register a new charity
(define-public (register-charity
        (name (string-ascii 64))
        (description (string-ascii 256))
        (wallet principal)
    )
    (let ((charity-id (var-get next-charity-id)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)

        (map-set charities { charity-id: charity-id } {
            name: name,
            description: description,
            wallet: wallet,
            total-received: u0,
            is-active: true,
            created-at: block-height,
        })

        (var-set next-charity-id (+ charity-id u1))
        (ok charity-id)
    )
)

;; Make a donation to a charity
(define-public (donate
        (charity-id uint)
        (amount uint)
        (message (string-ascii 128))
        (is-anonymous bool)
    )
    (let (
            (donation-id (var-get next-donation-id))
            (charity-info (unwrap! (map-get? charities { charity-id: charity-id })
                ERR_CHARITY_NOT_FOUND
            ))
            (current-donor-profile (default-to {
                total-donated: u0,
                donation-count: u0,
                tier: "NONE",
                rewards-earned: u0,
                first-donation: u0,
                last-donation: u0,
            }
                (map-get? donor-profiles { donor: tx-sender })
            ))
            (charity-donor-info (default-to {
                total-donated: u0,
                donation-count: u0,
            }
                (map-get? charity-donors {
                    charity-id: charity-id,
                    donor: tx-sender,
                })
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
        (map-set donations { donation-id: donation-id } {
            donor: tx-sender,
            charity-id: charity-id,
            amount: amount,
            message: message,
            timestamp: block-height,
            is-anonymous: is-anonymous,
        })

        ;; Update charity totals
        (map-set charities { charity-id: charity-id }
            (merge charity-info { total-received: (+ (get total-received charity-info) amount) })
        )

        ;; Update donor profile
        (map-set donor-profiles { donor: tx-sender } {
            total-donated: new-total-donated,
            donation-count: (+ (get donation-count current-donor-profile) u1),
            tier: new-tier,
            rewards-earned: (+ (get rewards-earned current-donor-profile) reward-amount),
            first-donation: (if (is-eq (get first-donation current-donor-profile) u0)
                block-height
                (get first-donation current-donor-profile)
            ),
            last-donation: block-height,
        })

        ;; Update charity-specific donor stats
        (map-set charity-donors {
            charity-id: charity-id,
            donor: tx-sender,
        } {
            total-donated: (+ (get total-donated charity-donor-info) amount),
            donation-count: (+ (get donation-count charity-donor-info) u1),
        })

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
    (let ((charity-info (unwrap! (map-get? charities { charity-id: charity-id })
            ERR_CHARITY_NOT_FOUND
        )))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)

        (map-set charities { charity-id: charity-id }
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
(define-read-only (get-charity-donor-stats
        (charity-id uint)
        (donor principal)
    )
    (map-get? charity-donors {
        charity-id: charity-id,
        donor: donor,
    })
)

;; Get global statistics
(define-read-only (get-global-stats)
    {
        total-donated: (var-get total-donated),
        total-donations: (- (var-get next-donation-id) u1),
        total-charities: (- (var-get next-charity-id) u1),
        reward-pool: (var-get reward-pool),
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
        u150 ;; 1.5x multiplier
        (if (is-eq tier "GOLD")
            u125 ;; 1.25x multiplier
            (if (is-eq tier "SILVER")
                u110 ;; 1.1x multiplier
                u100 ;; 1x multiplier (bronze and none)
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
        created-at: uint,
    }
)

;; Donor Milestone Achievements Map
(define-map donor-milestones
    {
        donor: principal,
        milestone-id: uint,
    }
    {
        achieved-at: uint,
        claimed-at: uint,
        reward-claimed: bool,
        achievement-value: uint,
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
        community-referrals: uint,
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
        (asserts! (is-valid-milestone-type milestone-type)
            ERR_INVALID_MILESTONE_TYPE
        )

        (map-set milestone-definitions { milestone-id: milestone-id } {
            title: title,
            description: description,
            milestone-type: milestone-type,
            requirement-value: requirement-value,
            reward-points: reward-points,
            is-active: true,
            created-at: block-height,
        })

        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

;; Check and award milestones for a donor
(define-public (check-donor-milestones (donor principal))
    (let (
            (donor-profile (unwrap! (map-get? donor-profiles { donor: donor })
                ERR_DONOR_NOT_FOUND
            ))
            (milestone-progress (default-to {
                total-milestones-achieved: u0,
                total-milestone-points: u0,
                consecutive-donation-months: u0,
                last-donation-month: u0,
                supported-charities-count: u0,
                community-referrals: u0,
            }
                (map-get? donor-milestone-progress { donor: donor })
            ))
        )
        ;; Check for first donation milestone
        (unwrap-panic (check-first-donation-milestone donor donor-profile))

        ;; Check for total amount milestones
        (unwrap-panic (check-total-amount-milestones donor (get total-donated donor-profile)))

        ;; Update milestone progress
        (map-set donor-milestone-progress { donor: donor } milestone-progress)

        (ok true)
    )
)

;; Claim milestone reward
(define-public (claim-milestone-reward (milestone-id uint))
    (let (
            (milestone-def (unwrap!
                (map-get? milestone-definitions { milestone-id: milestone-id })
                ERR_MILESTONE_NOT_FOUND
            ))
            (achievement (unwrap!
                (map-get? donor-milestones {
                    donor: tx-sender,
                    milestone-id: milestone-id,
                })
                ERR_MILESTONE_NOT_ACHIEVED
            ))
            (current-donor-profile (unwrap! (map-get? donor-profiles { donor: tx-sender })
                ERR_DONOR_NOT_FOUND
            ))
        )
        (asserts! (get is-active milestone-def) ERR_MILESTONE_NOT_FOUND)
        (asserts! (not (get reward-claimed achievement))
            ERR_MILESTONE_ALREADY_CLAIMED
        )

        ;; Mark as claimed
        (map-set donor-milestones {
            donor: tx-sender,
            milestone-id: milestone-id,
        }
            (merge achievement {
                claimed-at: block-height,
                reward-claimed: true,
            })
        )

        ;; Add reward points to donor profile
        (map-set donor-profiles { donor: tx-sender }
            (merge current-donor-profile { rewards-earned: (+ (get rewards-earned current-donor-profile)
                (get reward-points milestone-def)
            ) }
            ))

        ;; Update reward pool
        (var-set reward-pool
            (+ (var-get reward-pool) (get reward-points milestone-def))
        )

        (ok (get reward-points milestone-def))
    )
)

;; Read-only functions for Milestone System

;; Get milestone definition
(define-read-only (get-milestone-definition (milestone-id uint))
    (map-get? milestone-definitions { milestone-id: milestone-id })
)

;; Get donor milestone achievement
(define-read-only (get-donor-milestone
        (donor principal)
        (milestone-id uint)
    )
    (map-get? donor-milestones {
        donor: donor,
        milestone-id: milestone-id,
    })
)

;; Get donor milestone progress
(define-read-only (get-donor-milestone-progress (donor principal))
    (map-get? donor-milestone-progress { donor: donor })
)

;; Get all achieved milestones for a donor
(define-read-only (get-donor-achieved-milestones (donor principal))
    (let ((progress (default-to {
            total-milestones-achieved: u0,
            total-milestone-points: u0,
            consecutive-donation-months: u0,
            last-donation-month: u0,
            supported-charities-count: u0,
            community-referrals: u0,
        }
            (map-get? donor-milestone-progress { donor: donor })
        )))
        progress
    )
)

;; Get milestone statistics
(define-read-only (get-milestone-stats)
    {
        total-milestones: (- (var-get next-milestone-id) u1),
        total-achievements: (var-get total-milestones-achieved),
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
(define-private (check-first-donation-milestone
        (donor principal)
        (donor-profile {
            total-donated: uint,
            donation-count: uint,
            tier: (string-ascii 16),
            rewards-earned: uint,
            first-donation: uint,
            last-donation: uint,
        })
    )
    (if (and
            (> (get donation-count donor-profile) u0)
            (is-none (map-get? donor-milestones {
                donor: donor,
                milestone-id: u1,
            }))
        )
        (begin
            (map-set donor-milestones {
                donor: donor,
                milestone-id: u1,
            } {
                achieved-at: (get first-donation donor-profile),
                claimed-at: u0,
                reward-claimed: false,
                achievement-value: u1,
            })
            (var-set total-milestones-achieved
                (+ (var-get total-milestones-achieved) u1)
            )
            (ok true)
        )
        (ok true)
    )
)

;; Check total amount milestones
(define-private (check-total-amount-milestones
        (donor principal)
        (total-amount uint)
    )
    (begin
        ;; Check 10 STX milestone (milestone-id: u2)
        (if (and (>= total-amount u10000000) (is-none (map-get? donor-milestones {
                donor: donor,
                milestone-id: u2,
            })))
            (begin
                (map-set donor-milestones {
                    donor: donor,
                    milestone-id: u2,
                } {
                    achieved-at: block-height,
                    claimed-at: u0,
                    reward-claimed: false,
                    achievement-value: total-amount,
                })
                (var-set total-milestones-achieved
                    (+ (var-get total-milestones-achieved) u1)
                )
            )
            false
        )

        ;; Check 100 STX milestone (milestone-id: u3)
        (if (and (>= total-amount u100000000) (is-none (map-get? donor-milestones {
                donor: donor,
                milestone-id: u3,
            })))
            (begin
                (map-set donor-milestones {
                    donor: donor,
                    milestone-id: u3,
                } {
                    achieved-at: block-height,
                    claimed-at: u0,
                    reward-claimed: false,
                    achievement-value: total-amount,
                })
                (var-set total-milestones-achieved
                    (+ (var-get total-milestones-achieved) u1)
                )
            )
            false
        )

        (ok true)
    )
)

;; === VOLUNTEER REGISTRY SYSTEM ===
;; Independent feature for managing volunteer registrations, service tracking, and badge recognition

;; Volunteer System Constants
(define-constant ERR_VOLUNTEER_NOT_FOUND (err u420))
(define-constant ERR_VOLUNTEER_ALREADY_EXISTS (err u421))
(define-constant ERR_INVALID_HOURS (err u422))
(define-constant ERR_BADGE_NOT_FOUND (err u423))
(define-constant ERR_BADGE_ALREADY_EARNED (err u424))
(define-constant ERR_INSUFFICIENT_HOURS (err u425))
(define-constant ERR_INVALID_SKILL_LEVEL (err u426))

;; Volunteer Badge Types
(define-constant BADGE_NEWCOMER "NEWCOMER")
(define-constant BADGE_REGULAR "REGULAR")
(define-constant BADGE_DEDICATED "DEDICATED")
(define-constant BADGE_CHAMPION "CHAMPION")
(define-constant BADGE_SPECIALIST "SPECIALIST")
(define-constant BADGE_LEADER "LEADER")

;; Volunteer Data Variables
(define-data-var next-volunteer-id uint u1)
(define-data-var next-service-entry-id uint u1)
(define-data-var next-badge-id uint u1)
(define-data-var total-volunteer-hours uint u0)
(define-data-var total-active-volunteers uint u0)

;; Volunteer Profiles Map
(define-map volunteer-profiles
    { volunteer: principal }
    {
        volunteer-id: uint,
        name: (string-ascii 64),
        skills: (string-ascii 128),
        experience-level: (string-ascii 16),
        total-hours: uint,
        total-sessions: uint,
        registration-date: uint,
        last-activity: uint,
        is-active: bool,
        preferred-causes: (string-ascii 256),
    }
)

;; Volunteer Service Records Map
(define-map volunteer-service-records
    { service-id: uint }
    {
        volunteer: principal,
        charity-id: uint,
        service-date: uint,
        hours-worked: uint,
        service-type: (string-ascii 64),
        description: (string-ascii 256),
        verified: bool,
        verified-by: (optional principal),
    }
)

;; Volunteer Badge Definitions Map
(define-map volunteer-badge-definitions
    { badge-id: uint }
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        badge-type: (string-ascii 32),
        hours-requirement: uint,
        sessions-requirement: uint,
        skill-requirement: (string-ascii 16),
        reward-points: uint,
        is-active: bool,
    }
)

;; Volunteer Earned Badges Map
(define-map volunteer-earned-badges
    {
        volunteer: principal,
        badge-id: uint,
    }
    {
        earned-at: uint,
        verified: bool,
        hours-at-earning: uint,
        sessions-at-earning: uint,
    }
)

;; Volunteer Charity Relationships Map
(define-map volunteer-charity-stats
    {
        volunteer: principal,
        charity-id: uint,
    }
    {
        total-hours: uint,
        total-sessions: uint,
        first-service: uint,
        last-service: uint,
        favorite-service-type: (string-ascii 64),
    }
)

;; Public Functions for Volunteer Registry System

;; Register as a volunteer
(define-public (register-volunteer
        (name (string-ascii 64))
        (skills (string-ascii 128))
        (experience-level (string-ascii 16))
        (preferred-causes (string-ascii 256))
    )
    (let ((volunteer-id (var-get next-volunteer-id)))
        (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
        (asserts!
            (is-none (map-get? volunteer-profiles { volunteer: tx-sender }))
            ERR_VOLUNTEER_ALREADY_EXISTS
        )
        (asserts! (is-valid-experience-level experience-level)
            ERR_INVALID_SKILL_LEVEL
        )

        (map-set volunteer-profiles { volunteer: tx-sender } {
            volunteer-id: volunteer-id,
            name: name,
            skills: skills,
            experience-level: experience-level,
            total-hours: u0,
            total-sessions: u0,
            registration-date: block-height,
            last-activity: block-height,
            is-active: true,
            preferred-causes: preferred-causes,
        })

        (var-set next-volunteer-id (+ volunteer-id u1))
        (var-set total-active-volunteers (+ (var-get total-active-volunteers) u1))

        ;; Award newcomer badge automatically
        (unwrap-panic (award-automatic-badge tx-sender BADGE_NEWCOMER))

        (ok volunteer-id)
    )
)

;; Log volunteer service hours
(define-public (log-volunteer-service
        (charity-id uint)
        (hours-worked uint)
        (service-type (string-ascii 64))
        (description (string-ascii 256))
    )
    (let (
            (service-id (var-get next-service-entry-id))
            (volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: tx-sender })
                ERR_VOLUNTEER_NOT_FOUND
            ))
            (charity-stats (default-to {
                total-hours: u0,
                total-sessions: u0,
                first-service: u0,
                last-service: u0,
                favorite-service-type: "",
            }
                (map-get? volunteer-charity-stats {
                    volunteer: tx-sender,
                    charity-id: charity-id,
                })
            ))
        )
        (asserts! (get is-active volunteer-profile) ERR_VOLUNTEER_NOT_FOUND)
        (asserts! (> hours-worked u0) ERR_INVALID_HOURS)
        (asserts! (<= hours-worked u24) ERR_INVALID_HOURS)
        ;; Max 24 hours per entry

        ;; Record the service entry
        (map-set volunteer-service-records { service-id: service-id } {
            volunteer: tx-sender,
            charity-id: charity-id,
            service-date: block-height,
            hours-worked: hours-worked,
            service-type: service-type,
            description: description,
            verified: false,
            verified-by: none,
        })

        ;; Update volunteer profile
        (map-set volunteer-profiles { volunteer: tx-sender }
            (merge volunteer-profile {
                total-hours: (+ (get total-hours volunteer-profile) hours-worked),
                total-sessions: (+ (get total-sessions volunteer-profile) u1),
                last-activity: block-height,
            })
        )

        ;; Update volunteer-charity relationship
        (map-set volunteer-charity-stats {
            volunteer: tx-sender,
            charity-id: charity-id,
        } {
            total-hours: (+ (get total-hours charity-stats) hours-worked),
            total-sessions: (+ (get total-sessions charity-stats) u1),
            first-service: (if (is-eq (get first-service charity-stats) u0)
                block-height
                (get first-service charity-stats)
            ),
            last-service: block-height,
            favorite-service-type: service-type,
        })

        ;; Update global stats
        (var-set next-service-entry-id (+ service-id u1))
        (var-set total-volunteer-hours
            (+ (var-get total-volunteer-hours) hours-worked)
        )

        ;; Check for badge achievements
        (unwrap-panic (check-volunteer-badge-eligibility tx-sender))

        (ok service-id)
    )
)

;; Verify volunteer service (charity owner or contract owner only)
(define-public (verify-volunteer-service (service-id uint))
    (let (
            (service-record (unwrap!
                (map-get? volunteer-service-records { service-id: service-id })
                ERR_INVALID_AMOUNT
            ))
            (charity-info (unwrap!
                (map-get? charities { charity-id: (get charity-id service-record) })
                ERR_CHARITY_NOT_FOUND
            ))
        )
        (asserts!
            (or
                (is-eq tx-sender CONTRACT_OWNER)
                (is-eq tx-sender (get wallet charity-info))
            )
            ERR_NOT_AUTHORIZED
        )
        (asserts! (not (get verified service-record)) ERR_ALREADY_EXISTS)

        (map-set volunteer-service-records { service-id: service-id }
            (merge service-record {
                verified: true,
                verified-by: (some tx-sender),
            })
        )

        (ok true)
    )
)

;; Create a new volunteer badge (owner only)
(define-public (create-volunteer-badge
        (name (string-ascii 64))
        (description (string-ascii 256))
        (badge-type (string-ascii 32))
        (hours-requirement uint)
        (sessions-requirement uint)
        (skill-requirement (string-ascii 16))
        (reward-points uint)
    )
    (let ((badge-id (var-get next-badge-id)))
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (> (len name) u0) ERR_INVALID_AMOUNT)
        (asserts! (is-valid-badge-type badge-type) ERR_INVALID_MILESTONE_TYPE)

        (map-set volunteer-badge-definitions { badge-id: badge-id } {
            name: name,
            description: description,
            badge-type: badge-type,
            hours-requirement: hours-requirement,
            sessions-requirement: sessions-requirement,
            skill-requirement: skill-requirement,
            reward-points: reward-points,
            is-active: true,
        })

        (var-set next-badge-id (+ badge-id u1))
        (ok badge-id)
    )
)

;; Update volunteer status (deactivate/reactivate)
(define-public (update-volunteer-status
        (volunteer principal)
        (is-active bool)
    )
    (let ((volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: volunteer })
            ERR_VOLUNTEER_NOT_FOUND
        )))
        (asserts!
            (or (is-eq tx-sender volunteer) (is-eq tx-sender CONTRACT_OWNER))
            ERR_NOT_AUTHORIZED
        )

        (map-set volunteer-profiles { volunteer: volunteer }
            (merge volunteer-profile { is-active: is-active })
        )

        ;; Update global active volunteer count
        (if is-active
            (if (not (get is-active volunteer-profile))
                (var-set total-active-volunteers
                    (+ (var-get total-active-volunteers) u1)
                )
                true
            )
            (if (get is-active volunteer-profile)
                (var-set total-active-volunteers
                    (- (var-get total-active-volunteers) u1)
                )
                true
            )
        )

        (ok true)
    )
)

;; Read-only functions for Volunteer Registry System

;; Get volunteer profile
(define-read-only (get-volunteer-profile (volunteer principal))
    (map-get? volunteer-profiles { volunteer: volunteer })
)

;; Get volunteer service record
(define-read-only (get-volunteer-service-record (service-id uint))
    (map-get? volunteer-service-records { service-id: service-id })
)

;; Get volunteer badge definition
(define-read-only (get-volunteer-badge-definition (badge-id uint))
    (map-get? volunteer-badge-definitions { badge-id: badge-id })
)

;; Get volunteer earned badge
(define-read-only (get-volunteer-earned-badge
        (volunteer principal)
        (badge-id uint)
    )
    (map-get? volunteer-earned-badges {
        volunteer: volunteer,
        badge-id: badge-id,
    })
)

;; Get volunteer charity statistics
(define-read-only (get-volunteer-charity-stats
        (volunteer principal)
        (charity-id uint)
    )
    (map-get? volunteer-charity-stats {
        volunteer: volunteer,
        charity-id: charity-id,
    })
)

;; Get volunteer system statistics
(define-read-only (get-volunteer-system-stats)
    {
        total-volunteers: (- (var-get next-volunteer-id) u1),
        total-active-volunteers: (var-get total-active-volunteers),
        total-volunteer-hours: (var-get total-volunteer-hours),
        total-service-entries: (- (var-get next-service-entry-id) u1),
        total-badges: (- (var-get next-badge-id) u1),
    }
)

;; Private functions for Volunteer Registry System

;; Validate experience level
(define-private (is-valid-experience-level (level (string-ascii 16)))
    (or
        (is-eq level "BEGINNER")
        (or
            (is-eq level "INTERMEDIATE")
            (or
                (is-eq level "ADVANCED")
                (is-eq level "EXPERT")
            )
        )
    )
)

;; Validate badge type
(define-private (is-valid-badge-type (badge-type (string-ascii 32)))
    (or
        (is-eq badge-type BADGE_NEWCOMER)
        (or
            (is-eq badge-type BADGE_REGULAR)
            (or
                (is-eq badge-type BADGE_DEDICATED)
                (or
                    (is-eq badge-type BADGE_CHAMPION)
                    (or
                        (is-eq badge-type BADGE_SPECIALIST)
                        (is-eq badge-type BADGE_LEADER)
                    )
                )
            )
        )
    )
)

;; Award automatic badge
(define-private (award-automatic-badge
        (volunteer principal)
        (badge-type (string-ascii 32))
    )
    (let ((volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: volunteer })
            ERR_VOLUNTEER_NOT_FOUND
        )))
        ;; Award newcomer badge (badge-id: u1 assumed to exist)
        (if (and
                (is-eq badge-type BADGE_NEWCOMER)
                (is-none (map-get? volunteer-earned-badges {
                    volunteer: volunteer,
                    badge-id: u1,
                }))
            )
            (begin
                (map-set volunteer-earned-badges {
                    volunteer: volunteer,
                    badge-id: u1,
                } {
                    earned-at: block-height,
                    verified: true,
                    hours-at-earning: (get total-hours volunteer-profile),
                    sessions-at-earning: (get total-sessions volunteer-profile),
                })
                (ok true)
            )
            (ok true)
        )
    )
)

;; Check volunteer badge eligibility
(define-private (check-volunteer-badge-eligibility (volunteer principal))
    (let (
            (volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: volunteer })
                ERR_VOLUNTEER_NOT_FOUND
            ))
            (total-hours (get total-hours volunteer-profile))
            (total-sessions (get total-sessions volunteer-profile))
        )
        (begin
            ;; Check for Regular badge (50+ hours, 10+ sessions)
            (if (and
                    (>= total-hours u50)
                    (>= total-sessions u10)
                    (is-none (map-get? volunteer-earned-badges {
                        volunteer: volunteer,
                        badge-id: u2,
                    }))
                )
                (map-set volunteer-earned-badges {
                    volunteer: volunteer,
                    badge-id: u2,
                } {
                    earned-at: block-height,
                    verified: true,
                    hours-at-earning: total-hours,
                    sessions-at-earning: total-sessions,
                })
                false
            )

            ;; Check for Dedicated badge (200+ hours, 25+ sessions)
            (if (and
                    (>= total-hours u200)
                    (>= total-sessions u25)
                    (is-none (map-get? volunteer-earned-badges {
                        volunteer: volunteer,
                        badge-id: u3,
                    }))
                )
                (map-set volunteer-earned-badges {
                    volunteer: volunteer,
                    badge-id: u3,
                } {
                    earned-at: block-height,
                    verified: true,
                    hours-at-earning: total-hours,
                    sessions-at-earning: total-sessions,
                })
                false
            )

            (ok true)
        )
    )
)

(define-constant ERR_CAMPAIGN_NOT_FOUND (err u430))
(define-constant ERR_CAMPAIGN_CLOSED (err u431))
(define-constant ERR_INVALID_DEADLINE (err u432))
(define-constant ERR_DONATION_MISMATCH (err u433))
(define-constant ERR_DONATION_ALREADY_TAGGED (err u434))

(define-data-var next-campaign-id uint u1)

(define-map campaigns
    { campaign-id: uint }
    {
        charity-id: uint,
        title: (string-ascii 64),
        description: (string-ascii 256),
        goal-amount: uint,
        start-height: uint,
        deadline: uint,
        is-active: bool,
        total-raised: uint,
        donation-count: uint,
    }
)

(define-map campaign-donations
    {
        campaign-id: uint,
        donation-id: uint,
    }
    {
        donor: principal,
        amount: uint,
        timestamp: uint,
    }
)

(define-map donation-campaign-index
    { donation-id: uint }
    { campaign-id: uint }
)

(define-public (create-campaign
        (charity-id uint)
        (title (string-ascii 64))
        (description (string-ascii 256))
        (goal-amount uint)
        (deadline uint)
    )
    (let (
            (cid (var-get next-campaign-id))
            (charity-info (unwrap! (map-get? charities { charity-id: charity-id })
                ERR_CHARITY_NOT_FOUND
            ))
        )
        (asserts! (> (len title) u0) ERR_INVALID_AMOUNT)
        (asserts! (> goal-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (> deadline block-height) ERR_INVALID_DEADLINE)
        (asserts!
            (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender (get wallet charity-info)))
            ERR_NOT_AUTHORIZED
        )
        (map-set campaigns { campaign-id: cid } {
            charity-id: charity-id,
            title: title,
            description: description,
            goal-amount: goal-amount,
            start-height: block-height,
            deadline: deadline,
            is-active: true,
            total-raised: u0,
            donation-count: u0,
        })
        (var-set next-campaign-id (+ cid u1))
        (ok cid)
    )
)

(define-public (close-campaign (campaign-id uint))
    (let (
            (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id })
                ERR_CAMPAIGN_NOT_FOUND
            ))
            (charity-info (unwrap!
                (map-get? charities { charity-id: (get charity-id campaign) })
                ERR_CHARITY_NOT_FOUND
            ))
        )
        (asserts!
            (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender (get wallet charity-info)))
            ERR_NOT_AUTHORIZED
        )
        (asserts! (get is-active campaign) ERR_CAMPAIGN_CLOSED)
        (map-set campaigns { campaign-id: campaign-id }
            (merge campaign { is-active: false })
        )
        (ok true)
    )
)

(define-public (tag-donation-to-campaign
        (campaign-id uint)
        (donation-id uint)
    )
    (let (
            (campaign (unwrap! (map-get? campaigns { campaign-id: campaign-id })
                ERR_CAMPAIGN_NOT_FOUND
            ))
            (donation (unwrap! (map-get? donations { donation-id: donation-id })
                ERR_INVALID_AMOUNT
            ))
        )
        (asserts! (get is-active campaign) ERR_CAMPAIGN_CLOSED)
        (asserts!
            (is-none (map-get? donation-campaign-index { donation-id: donation-id }))
            ERR_DONATION_ALREADY_TAGGED
        )
        (asserts! (is-eq (get donor donation) tx-sender) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq (get charity-id donation) (get charity-id campaign))
            ERR_DONATION_MISMATCH
        )
        (map-set campaign-donations {
            campaign-id: campaign-id,
            donation-id: donation-id,
        } {
            donor: (get donor donation),
            amount: (get amount donation),
            timestamp: block-height,
        })
        (map-set donation-campaign-index { donation-id: donation-id } { campaign-id: campaign-id })
        (map-set campaigns { campaign-id: campaign-id }
            (merge campaign {
                total-raised: (+ (get total-raised campaign) (get amount donation)),
                donation-count: (+ (get donation-count campaign) u1),
            })
        )
        (ok true)
    )
)

(define-read-only (get-campaign (campaign-id uint))
    (map-get? campaigns { campaign-id: campaign-id })
)

(define-read-only (get-campaign-donation
        (campaign-id uint)
        (donation-id uint)
    )
    (map-get? campaign-donations {
        campaign-id: campaign-id,
        donation-id: donation-id,
    })
)

(define-read-only (get-campaign-stats (campaign-id uint))
    (map-get? campaigns { campaign-id: campaign-id })
)
