;; charity-registry
;; A comprehensive charity registration and management contract for tracking charitable organizations
;; Provides functionality for charity registration, verification, profile management, and status tracking

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-CHARITY-NOT-FOUND (err u101))
(define-constant ERR-CHARITY-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-INVALID-CATEGORY (err u104))
(define-constant ERR-EMPTY-NAME (err u105))
(define-constant ERR-CHARITY-INACTIVE (err u106))
(define-constant ERR-INVALID-AMOUNT (err u107))

;; data vars
(define-data-var next-charity-id uint u1)
(define-data-var total-charities uint u0)
(define-data-var total-active-charities uint u0)
(define-data-var contract-paused bool false)

;; data maps
;; Main charity registry mapping
(define-map charities
    uint ;; charity-id
    {
        name: (string-ascii 100),
        description: (string-ascii 500),
        category: (string-ascii 50),
        owner: principal,
        status: (string-ascii 20), ;; "active", "inactive", "pending", "suspended"
        created-at: uint,
        updated-at: uint,
        total-received: uint,
        total-withdrawn: uint,
        donation-count: uint,
        verification-status: bool,
        contact-email: (string-ascii 100),
        website: (optional (string-ascii 200))
    }
)

;; Mapping from principal to charity ID for quick lookup
(define-map charity-owners
    principal ;; owner address
    uint ;; charity-id
)

;; Mapping for charity categories and their counts
(define-map category-counts
    (string-ascii 50) ;; category name
    uint ;; count of charities in this category
)

;; Track charity balances
(define-map charity-balances
    uint ;; charity-id
    uint ;; balance in microSTX
)

;; private functions
(define-private (is-valid-status (status (string-ascii 20)))
    (or 
        (is-eq status "active")
        (or 
            (is-eq status "inactive")
            (or 
                (is-eq status "pending")
                (is-eq status "suspended")
            )
        )
    )
)

(define-private (is-valid-category (category (string-ascii 50)))
    (or 
        (is-eq category "Education")
        (or 
            (is-eq category "Health")
            (or 
                (is-eq category "Environment")
                (or 
                    (is-eq category "Animal Welfare")
                    (or 
                        (is-eq category "Disaster Relief")
                        (or 
                            (is-eq category "Community Development")
                            (or 
                                (is-eq category "Human Rights")
                                (is-eq category "Other")
                            )
                        )
                    )
                )
            )
        )
    )
)

(define-private (increment-category-count (category (string-ascii 50)))
    (let
        (
            (current-count (default-to u0 (map-get? category-counts category)))
        )
        (map-set category-counts category (+ current-count u1))
    )
)

(define-private (decrement-category-count (category (string-ascii 50)))
    (let
        (
            (current-count (default-to u0 (map-get? category-counts category)))
        )
        (if (> current-count u0)
            (map-set category-counts category (- current-count u1))
            true
        )
    )
)

;; public functions
(define-public (register-charity (name (string-ascii 100)) (description (string-ascii 500)) 
                                (category (string-ascii 50)) (contact-email (string-ascii 100))
                                (website (optional (string-ascii 200))))
    (let
        (
            (charity-id (var-get next-charity-id))
            (current-block stacks-block-height)
        )
        (asserts! (not (var-get contract-paused)) (err u999))
        (asserts! (is-none (map-get? charity-owners tx-sender)) ERR-CHARITY-ALREADY-EXISTS)
        (asserts! (> (len name) u0) ERR-EMPTY-NAME)
        (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
        
        ;; Create charity record
        (map-set charities charity-id {
            name: name,
            description: description,
            category: category,
            owner: tx-sender,
            status: "pending",
            created-at: current-block,
            updated-at: current-block,
            total-received: u0,
            total-withdrawn: u0,
            donation-count: u0,
            verification-status: false,
            contact-email: contact-email,
            website: website
        })
        
        ;; Map owner to charity ID
        (map-set charity-owners tx-sender charity-id)
        
        ;; Initialize charity balance
        (map-set charity-balances charity-id u0)
        
        ;; Update counters
        (var-set next-charity-id (+ charity-id u1))
        (var-set total-charities (+ (var-get total-charities) u1))
        (increment-category-count category)
        
        (ok charity-id)
    )
)

(define-public (update-charity-profile (charity-id uint) (name (string-ascii 100)) 
                                      (description (string-ascii 500)) (contact-email (string-ascii 100))
                                      (website (optional (string-ascii 200))))
    (let
        (
            (charity-info (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get owner charity-info)) ERR-UNAUTHORIZED)
        (asserts! (> (len name) u0) ERR-EMPTY-NAME)
        
        (map-set charities charity-id 
            (merge charity-info {
                name: name,
                description: description,
                contact-email: contact-email,
                website: website,
                updated-at: stacks-block-height
            })
        )
        (ok true)
    )
)

(define-public (verify-charity (charity-id uint))
    (let
        (
            (charity-info (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        
        (map-set charities charity-id 
            (merge charity-info {
                verification-status: true,
                status: "active",
                updated-at: stacks-block-height
            })
        )
        
        (if (is-eq (get status charity-info) "pending")
            (var-set total-active-charities (+ (var-get total-active-charities) u1))
            true
        )
        
        (ok true)
    )
)

(define-public (change-charity-status (charity-id uint) (new-status (string-ascii 20)))
    (let
        (
            (charity-info (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND))
            (old-status (get status charity-info))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
        
        (map-set charities charity-id 
            (merge charity-info {
                status: new-status,
                updated-at: stacks-block-height
            })
        )
        
        ;; Update active charity counter
        (if (and (is-eq old-status "active") (not (is-eq new-status "active")))
            (var-set total-active-charities (- (var-get total-active-charities) u1))
            (if (and (not (is-eq old-status "active")) (is-eq new-status "active"))
                (var-set total-active-charities (+ (var-get total-active-charities) u1))
                true
            )
        )
        
        (ok true)
    )
)

(define-public (transfer-charity-ownership (charity-id uint) (new-owner principal))
    (let
        (
            (charity-info (unwrap! (map-get? charities charity-id) ERR-CHARITY-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get owner charity-info)) ERR-UNAUTHORIZED)
        (asserts! (is-none (map-get? charity-owners new-owner)) ERR-CHARITY-ALREADY-EXISTS)
        
        ;; Update charity owner
        (map-set charities charity-id 
            (merge charity-info {
                owner: new-owner,
                updated-at: stacks-block-height
            })
        )
        
        ;; Update owner mappings
        (map-delete charity-owners tx-sender)
        (map-set charity-owners new-owner charity-id)
        
        (ok true)
    )
)

;; read only functions
(define-read-only (get-charity (charity-id uint))
    (map-get? charities charity-id)
)

(define-read-only (get-charity-by-owner (owner principal))
    (match (map-get? charity-owners owner)
        charity-id (map-get? charities charity-id)
        none
    )
)

(define-read-only (get-charity-balance (charity-id uint))
    (map-get? charity-balances charity-id)
)

(define-read-only (get-category-count (category (string-ascii 50)))
    (default-to u0 (map-get? category-counts category))
)

(define-read-only (get-platform-stats)
    {
        total-charities: (var-get total-charities),
        total-active-charities: (var-get total-active-charities),
        next-charity-id: (var-get next-charity-id),
        contract-paused: (var-get contract-paused)
    }
)

(define-read-only (is-charity-active (charity-id uint))
    (match (map-get? charities charity-id)
        charity-info (is-eq (get status charity-info) "active")
        false
    )
)

(define-read-only (get-charity-owner (charity-id uint))
    (match (map-get? charities charity-id)
        charity-info (some (get owner charity-info))
        none
    )
)
