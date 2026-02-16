;; =====================================================
;; ClarityGuardianModule
;; Programmable transaction guard for treasury security
;; =====================================================

;; -----------------------------
;; Data Variables
;; -----------------------------

(define-data-var admin principal tx-sender)
(define-data-var daily-limit uint u0)
(define-data-var timelock-delay uint u0)

(define-data-var spent-today uint u0)
(define-data-var last-reset uint u0)

;; -----------------------------
;; Data Maps
;; -----------------------------

;; approved recipients
(define-map whitelist principal bool)

;; queued transactions
(define-map queued-txs
  uint
  {
    recipient: principal,
    amount: uint,
    execute-after: uint,
    executed: bool
  }
)

(define-data-var tx-counter uint u0)

;; -----------------------------
;; Errors
;; -----------------------------

(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-NOT-WHITELISTED u101)
(define-constant ERR-OVER-LIMIT u102)
(define-constant ERR-NOT-READY u103)
(define-constant ERR-ALREADY-EXECUTED u104)
(define-constant ERR-NOT-FOUND u105)

;; -----------------------------
;; Helpers
;; -----------------------------

(define-read-only (is-admin)
  (is-eq tx-sender (var-get admin))
)

(define-private (reset-if-needed)
  (let ((current-block stacks-block-height))
    (if (> (- current-block (var-get last-reset)) u144)
        (begin
          (var-set spent-today u0)
          (var-set last-reset current-block)
          true)
        true
    )
  )
)

;; -----------------------------
;; Configuration
;; -----------------------------

(define-public (set-daily-limit (limit uint))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set daily-limit limit)
    (ok true)
  )
)

(define-public (set-timelock (delay uint))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set timelock-delay delay)
    (ok true)
  )
)

(define-public (add-to-whitelist (recipient principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (map-set whitelist recipient true)
    (ok true)
  )
)

;; -----------------------------
;; Queue Transaction
;; -----------------------------

(define-public (queue-transfer (recipient principal) (amount uint))
  (begin
    (asserts! (is-some (map-get? whitelist recipient)) (err ERR-NOT-WHITELISTED))

    (let ((id (var-get tx-counter))
          (execute-height (+ stacks-block-height (var-get timelock-delay))))

      (map-set queued-txs id {
        recipient: recipient,
        amount: amount,
        execute-after: execute-height,
        executed: false
      })

      (var-set tx-counter (+ id u1))
      (ok id)
    )
  )
)

;; -----------------------------
;; Execute Transaction
;; -----------------------------

(define-public (execute (tx-id uint))
  (let ((tx (map-get? queued-txs tx-id)))
    (match tx data
      (begin
        (asserts! (not (get executed data)) (err ERR-ALREADY-EXECUTED))
        (asserts! (>= stacks-block-height (get execute-after data)) (err ERR-NOT-READY))

        (reset-if-needed)

        (asserts!
          (<= (+ (var-get spent-today) (get amount data))
              (var-get daily-limit))
          (err ERR-OVER-LIMIT)
        )

        ;; update state first
        (var-set spent-today (+ (var-get spent-today) (get amount data)))

        (map-set queued-txs tx-id {
          recipient: (get recipient data),
          amount: (get amount data),
          execute-after: (get execute-after data),
          executed: true
        })

        (stx-transfer?
          (get amount data)
          (as-contract tx-sender)
          (get recipient data)
        )
      )
      (err ERR-NOT-FOUND)
    )
  )
)