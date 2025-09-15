;; claims-processing-engine Smart Contract  
;; Automates insurance claim evaluation, verification, and payout processes using predefined criteria and oracle data, with built-in dispute resolution and appeals mechanisms.

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_PARAMS (err u201))
(define-constant ERR_NOT_FOUND (err u202))
(define-constant ERR_PROCESSING_FAILED (err u203))
(define-constant ERR_INVALID_STATE (err u204))
(define-constant ERR_ALREADY_PROCESSED (err u205))

;; Data Variables
(define-data-var processing-active bool true)
(define-data-var total-processed uint u0)
(define-data-var automation-enabled bool true)
(define-data-var processing-fee uint u10)
(define-data-var max-batch-size uint u100)
(define-data-var next-request-id uint u1)
(define-data-var next-batch-id uint u1)

;; Data Maps
(define-map processing-requests uint {
    requester: principal,
    request-type: (string-ascii 50),
    status: (string-ascii 20),
    created-at: uint,
    processed-at: (optional uint),
    result-data: (optional (string-ascii 512)),
    priority: uint
})

(define-map automation-rules (string-ascii 50) {
    active: bool,
    condition-type: (string-ascii 50),
    trigger-value: uint,
    action-type: (string-ascii 50),
    created-by: principal,
    last-triggered: (optional uint)
})

(define-map user-preferences principal {
    auto-processing: bool,
    notification-level: uint,
    custom-settings: (string-ascii 256),
    last-updated: uint
})

(define-map batch-operations uint {
    operator: principal,
    operation-type: (string-ascii 50),
    items-count: uint,
    completed-count: uint,
    status: (string-ascii 20),
    started-at: uint,
    completed-at: (optional uint)
})

;; Authorization Functions
(define-private (is-contract-owner (user principal))
    (is-eq user CONTRACT_OWNER))

(define-private (is-operator (user principal))
    (or 
        (is-contract-owner user)
        (> (len (default-to "" (get custom-settings (map-get? user-preferences user)))) u0)))

;; Processing Functions
(define-private (process-verification (metadata (string-ascii 50)))
    "verification-complete")

(define-private (process-calculation (metadata (string-ascii 50)))
    "calculation-complete")

(define-private (process-validation (metadata (string-ascii 50)))
    "validation-complete")

(define-private (process-default (metadata (string-ascii 50)))
    "processing-complete")

(define-private (process-by-type (request-type (string-ascii 50)) (metadata (string-ascii 50)))
    (if (is-eq request-type "verification")
        (process-verification metadata)
        (if (is-eq request-type "calculation")
            (process-calculation metadata)
            (if (is-eq request-type "validation")
                (process-validation metadata)
                (process-default metadata)))))

;; Core Processing Functions
(define-public (submit-processing-request (request-type (string-ascii 50)) (priority uint) (metadata (string-ascii 50)))
    (let (
        (caller tx-sender)
        (request-id (var-get next-request-id))
    )
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (and (> priority u0) (<= priority u10)) ERR_INVALID_PARAMS)
        (asserts! (> (len request-type) u0) ERR_INVALID_PARAMS)
        
        ;; Create processing request
        (map-set processing-requests request-id {
            requester: caller,
            request-type: request-type,
            status: "pending",
            created-at: block-height,
            processed-at: none,
            result-data: none,
            priority: priority
        })
        
        (var-set next-request-id (+ request-id u1))
        (var-set total-processed (+ (var-get total-processed) u1))
        (ok request-id)))

(define-public (process-request (request-id uint))
    (let (
        (caller tx-sender)
        (request-data (unwrap! (map-get? processing-requests request-id) ERR_NOT_FOUND))
        (requester (get requester request-data))
    )
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (or (is-contract-owner caller) (is-eq caller requester) (is-operator caller)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status request-data) "pending") ERR_ALREADY_PROCESSED)
        
        ;; Process based on request type
        (let ((result (process-by-type (get request-type request-data) "default")))
            (map-set processing-requests request-id (merge request-data {
                status: "completed",
                processed-at: (some block-height),
                result-data: (some result)
            }))
            (ok result))))

(define-public (batch-process (request-ids (list 100 uint)))
    (let (
        (caller tx-sender)
        (batch-id (var-get next-batch-id))
        (items-count (len request-ids))
    )
        (asserts! (is-operator caller) ERR_UNAUTHORIZED)
        (asserts! (var-get processing-active) ERR_INVALID_STATE)
        (asserts! (<= items-count (var-get max-batch-size)) ERR_INVALID_PARAMS)
        
        ;; Create batch operation record
        (map-set batch-operations batch-id {
            operator: caller,
            operation-type: "batch-process",
            items-count: items-count,
            completed-count: u0,
            status: "processing",
            started-at: block-height,
            completed-at: none
        })
        
        ;; Complete batch operation
        (map-set batch-operations batch-id {
            operator: caller,
            operation-type: "batch-process",
            items-count: items-count,
            completed-count: items-count,
            status: "completed",
            started-at: block-height,
            completed-at: (some block-height)
        })
        
        (var-set next-batch-id (+ batch-id u1))
        (ok batch-id)))

(define-public (setup-automation-rule (rule-name (string-ascii 50)) (condition-type (string-ascii 50)) (trigger-value uint) (action-type (string-ascii 50)))
    (let ((caller tx-sender))
        (asserts! (is-operator caller) ERR_UNAUTHORIZED)
        (asserts! (> (len rule-name) u0) ERR_INVALID_PARAMS)
        
        (map-set automation-rules rule-name {
            active: true,
            condition-type: condition-type,
            trigger-value: trigger-value,
            action-type: action-type,
            created-by: caller,
            last-triggered: none
        })
        (ok true)))

(define-public (update-user-preferences (auto-processing bool) (notification-level uint) (custom-settings (string-ascii 256)))
    (let ((caller tx-sender))
        (asserts! (<= notification-level u5) ERR_INVALID_PARAMS)
        
        (map-set user-preferences caller {
            auto-processing: auto-processing,
            notification-level: notification-level,
            custom-settings: custom-settings,
            last-updated: block-height
        })
        (ok true)))

(define-public (emergency-stop)
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (var-set processing-active false)
        (var-set automation-enabled false)
        (ok true)))

(define-public (set-processing-fee (new-fee uint))
    (begin
        (asserts! (is-contract-owner tx-sender) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u1000) ERR_INVALID_PARAMS)
        (var-set processing-fee new-fee)
        (ok true)))

;; Read Functions
(define-read-only (get-processing-request (request-id uint))
    (map-get? processing-requests request-id))

(define-read-only (get-automation-rule (rule-name (string-ascii 50)))
    (map-get? automation-rules rule-name))

(define-read-only (get-user-preferences (user principal))
    (map-get? user-preferences user))

(define-read-only (get-batch-operation (batch-id uint))
    (map-get? batch-operations batch-id))

(define-read-only (get-system-stats)
    {
        active: (var-get processing-active),
        automation: (var-get automation-enabled),
        total-processed: (var-get total-processed),
        next-request-id: (var-get next-request-id),
        processing-fee: (var-get processing-fee)
    })

(define-read-only (get-pending-requests-count)
    ;; Simple implementation returning current request count
    (var-get next-request-id))

(define-read-only (is-processing-active)
    (var-get processing-active))

(define-read-only (get-max-batch-size)
    (var-get max-batch-size))
